#!/usr/bin/env node
/**
 * A/B behaviour test: does the patched schema change what the local model emits?
 *
 * Conditions differ in exactly one thing: a user-level schema override in HOME.
 * Both conditions use the real `openspec instructions tasks` payload, so the
 * prompt is what an agent would actually receive.
 *
 * Usage: node ab_slice_test.mjs [--runs 2] [--model ID] [--base-url URL]
 */

import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, cpSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const arg = (name, fallback) => {
	const i = argv.indexOf(`--${name}`);
	return i === -1 ? fallback : argv[i + 1];
};

const PKG = arg('pkg', '/tmp/osx/package');
const OSX = join(PKG, 'bin', 'openspec.js');
const HERE = new URL('.', import.meta.url).pathname;
const BASE_URL = arg('base-url', 'http://192.168.1.235:11234/v1');
const MODEL = arg('model', 'qwen3.8-flash-next@iq4_xs');
const RUNS = Number(arg('runs', '2'));

const SCENARIO = [
	'Change: CSV export for the reports page.',
	 '',
	 'Existing app: FastAPI backend, SQLite through SQLAlchemy, React frontend.',
	 'A user opens the reports page, clicks Export, the server writes the current',
	 'filtered rows to a .csv file, and the browser downloads it.',
	 'Quoting must follow RFC 4180. The export must be documented in docs/export.md.',
].join('\n');

const ROOT = mkdtempSync(join(tmpdir(), 'ab-slice-'));

function sh(cmd, args, { env = {}, cwd } = {}) {
	const r = spawnSync(cmd, args, {
		cwd,
		env: { ...process.env, ...env },
		encoding: 'utf8',
	});
	if (r.status !== 0) throw new Error(`${cmd} failed: ${r.stderr?.slice(0, 400)}`);
	return r.stdout;
}

/** Build a project for one condition; patchArgs selects the ablation. */
function buildCondition(name, { patchArgs = null } = {}) {
	const home = join(ROOT, `home-${name}`);
	const proj = join(ROOT, `proj-${name}`);
	mkdirSync(home, { recursive: true });
	mkdirSync(proj, { recursive: true });
	const env = { HOME: home, XDG_DATA_HOME: '', OPENSPEC_TELEMETRY: '0', OPENSPEC_NO_UPDATE_CHECK: '1' };
	if (patchArgs) {
		const out = sh('node', [
			join(HERE, 'patch_schema.mjs'),
			'--package-root', PKG,
			'--out', join(home, '.local', 'share', 'openspec', 'schemas'),
			'--openspec-version', 'ab-test',
			...patchArgs,
		], { env });
		process.stdout.write(`  ${out.trim()}\n`);
	}
	const run = (args) => sh('node', [OSX, ...args], { env, cwd: proj });
	run(['init', '--tools', 'pi', '--no-animation', '--no-copilot-cloud']);
	run(['new', 'change', 'add-csv-export']);
	const payload = run(['instructions', 'tasks', '--change', 'add-csv-export']);
	const source = run(['schema', 'which', 'spec-driven']);
	return { name, home, proj, env, payload, source: /Source: (\w+)/.exec(source)?.[1] };
}

/** Ask the model for tasks.md and keep the part after the "# Tasks" title. */
async function generate(condition) {
	const body = {
		model: MODEL,
		temperature: 0.4,
		max_tokens: 1400,
		messages: [
			{ role: 'system', content: condition.payload },
			{
				role: 'user',
				content:
					'Write tasks.md for this change. Follow the instructions exactly. '
					+ 'Output only the tasks.md content.\n\n'
					+ SCENARIO,
			},
		],
	};
	const res = await fetch(`${BASE_URL}/chat/completions`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
		signal: AbortSignal.timeout(300_000),
	});
	if (!res.ok) throw new Error(`model call failed: ${res.status} ${(await res.text()).slice(0, 300)}`);
	const json = await res.json();
	const text = json.choices?.[0]?.message?.content ?? '';
	const at = text.indexOf('# Tasks');
	return at === -1 ? text : text.slice(at);
}

const LAYER = /\b(database|db|schema|backend|frontend|server|api|service|ui|controller|repository|models? layer|setup|infrastructure|boilerplate|scaffolding|wiring)\b/i;
const SLICE = /\b(tracer|vertical slice|slice|end[ -]to[ -]end|e2e)\b/i;

function score(tasks) {
	const headings = (tasks.match(/^##+ .*$/gm) ?? []).map((h) => h.replace(/^#+\s*/, '').trim());
	const groups = headings.filter((h) => !/workflow follow-?up/i.test(h));
	return {
		headings: groups,
		layerish: groups.filter((h) => LAYER.test(h)).length,
		sliceish: groups.filter((h) => SLICE.test(h)).length,
		firstIsTracer: /tracer/i.test(groups[0] ?? ''),
	};
}

console.log('== build conditions ==');
const bare = buildCondition('bare', {});
const rulesOnly = buildCondition('rules-only', { patchArgs: ['--skip-example'] });
const patched = buildCondition('override', { patchArgs: [] });
for (const [label, cond] of [['bare', bare], ['rules-only', rulesOnly], ['override', patched]]) {
	console.log(`  ${label.padEnd(11)}: schema ${cond.source}, payload ${cond.payload.length} bytes`);
}

const CONDITIONS = [
	['bare', bare],
	['rules-only', rulesOnly],
	['override', patched],
];

const results = Object.fromEntries(CONDITIONS.map(([label]) => [label, []]));
for (const [label, cond] of CONDITIONS) {
	for (let i = 1; i <= RUNS; i++) {
		process.stdout.write(`== ${label} run ${i}: generating... `);
		try {
			const tasks = await generate(cond);
			const s = score(tasks);
			results[label].push(s);
			writeFileSync(join(ROOT, `tasks-${label}-${i}.md`), tasks);
			console.log(`groups=${s.headings.length} layerish=${s.layerish} sliceish=${s.sliceish} firstTracer=${s.firstIsTracer}`);
			for (const h of s.headings) console.log(`      ${h}`);
		} catch (err) {
			console.log(`ERROR ${err.message}`);
			results[label].push({ headings: [], layerish: 0, sliceish: 0, firstIsTracer: false, error: true });
		}
	}
}

const sum = (label, key) => results[label].reduce((acc, r) => acc + (r[key] ? 1 : 0), 0);
const avg = (label, key) => (results[label].reduce((acc, r) => acc + r[key], 0) / RUNS).toFixed(1);

console.log('\n== verdict ==');
console.log(`  runs per condition : ${RUNS}`);
console.log('  condition      layer groups  slice groups  first group is a tracer');
for (const [label] of CONDITIONS) {
	console.log(
		`  ${label.padEnd(14)} ${avg(label, 'layerish').padStart(7)}  ${avg(label, 'sliceish').padStart(13)}`
		+ `  ${String(sum(label, 'firstIsTracer')).padStart(3)}/${RUNS}`,
	);
}
console.log('\n  ablation reading: if rules-only matches override, the example rewrite is');
console.log('  optional; if rules-only looks like bare, the example rewrite carries the effect.');
const pass = sum('override', 'firstIsTracer') >= Math.max(1, RUNS - 1)
	&& Number(avg('override', 'layerish')) < Number(avg('bare', 'layerish'));
console.log(`\n  ${pass ? 'DESIGN SUPPORTED' : 'INCONCLUSIVE'} — outputs kept in ${ROOT}`);
