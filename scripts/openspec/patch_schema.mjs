#!/usr/bin/env node
/**
 * Build-time patch: derive a user-level OpenSpec schema override from the
 * schema shipped inside the installed @fission-ai/openspec package.
 *
 * Zero dependencies beyond Node itself, which the sandbox image already
 * installs to run pi and openspec.
 *
 * Why derive instead of copy:
 *   A copied schema freezes. When the image bumps the openspec version, the
 *   copy keeps the old workflow and nothing warns you. Deriving at build time
 *   re-applies the patch to the current upstream schema, so upstream workflow
 *   changes reach every sandbox, and an upstream edit that moves an anchor
 *   fails the image build loudly.
 *
 * Behaviour:
 *   - Reads <package-root>/schemas/spec-driven/{schema.yaml,templates/}
 *   - Writes <out>/spec-driven/{schema.yaml,templates/,.override-manifest.yaml}
 *   - Every anchor must appear exactly once, else exit 1 (build fails)
 *   - Output depends only on the input; re-running rewrites the same bytes
 *
 * OpenSpec resolves schemas: project openspec/schemas/ > user
 * ${XDG_DATA_HOME|~/.local/share}/openspec/schemas/ > package built-in. An
 * override in the user directory therefore applies to every project created
 * in the image, with no per-project setup.
 */

import {
	cpSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	renameSync,
	rmSync,
	writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const SCHEMA_NAME = 'spec-driven';

/**
 * Anchors are exact upstream file text. Each must match exactly once.
 * Indentation is part of the anchor: instruction bodies sit inside a YAML
 * block scalar, so content lines start with six spaces.
 */
const REPLACEMENTS = [
	{
		why: 'make the override visible in `openspec schemas`',
		find: 'description: Default OpenSpec workflow - proposal \u2192 specs \u2192 design \u2192 tasks',
		replace:
			'description: Default OpenSpec workflow, sandbox override ' +
			'(tracer-bullet-first slices) - proposal \u2192 specs \u2192 design \u2192 tasks',
	},
	{
		why: 'task groups are vertical slices',
		isRules: true,
		find: '      - Group related tracked tasks under ## numbered headings',
		replace: [
			'      - Group related tracked tasks under ## numbered headings, one heading',
			'        per vertical slice. A group that touches only one technical layer,',
			'        such as database, service, or UI, is a horizontal slice: split it.',
		].join('\n'),
	},
	{
		why: 'tracer-bullet-first ordering, stub disclosure, stop on red',
		isRules: true,
		find: '      - Order tasks by dependency (what must be done first?)',
		replace: [
			'      - Order task groups so the first implementation group is a tracer',
			'        bullet: one narrow working path through every relevant layer, with',
			'        an executable end-to-end check. Keep unavoidable setup before it,',
			'        and state why setup cannot live inside the first slice.',
			'      - Use real integration boundaries in the tracer bullet. When a boundary',
			'        must be stubbed, name what stays unvalidated and add a task that',
			'        replaces the stub.',
			"      - Require the first slice's end-to-end check to pass before any later",
			'        group starts. Do not defer initial integration to a final test phase.',
			'      - Order later groups by observable behaviour, not by technical layer.',
		].join('\n'),
	},
	{
		why: 'worked example shows a tracer bullet, then slices',
		isExample: true,
		find: [
			'      ## 1. Setup',
			'',
			'      - [ ] 1.1 Create new module structure and verify expected files are present',
			'      - [ ] 1.2 Add dependencies to package.json and verify package installation succeeds',
			'',
			'      ## 2. Core Implementation',
			'',
			'      - [ ] 2.1 Implement data export function and verify the export test passes',
			'      - [ ] 2.2 Add CSV formatting utilities and verify unit tests cover quoting and delimiters',
			'      - [ ] 2.3 Document the export API in docs/export.md and verify the documented command runs as written',
		].join('\n'),
		replace: [
			'      ## 1. Tracer bullet',
			'',
			'      - [ ] 1.1 Add the CSV export dependency and verify the install succeeds',
			'      - [ ] 1.2 Wire one narrow export end to end: request -> service -> file',
			'            writer -> download link, and verify the flow runs in the app',
			'',
			'      ## 2. Slice: quoting rules',
			'',
			'      - [ ] 2.1 Add quoting through all relevant layers and verify the export test passes',
			'      - [ ] 2.2 Add the delimiter case and verify unit tests cover quoting and delimiters',
			'',
			'      ## 3. Slice: documented API',
			'',
			'      - [ ] 3.1 Document the export API in docs/export.md and verify the documented command runs as written',
		].join('\n'),
	},
	{
		why: 'design names the tracer bullet',
		isRules: true,
		find: '      Focus on architecture and approach, not line-by-line implementation.',
		replace: [
			'      Tracer bullet: name the smallest meaningful end-to-end path that',
			'      proves this approach and exercises its highest-risk integration. State',
			'      which layers it crosses and how it gets exercised. Separate the',
			'      prerequisites that must exist first from infrastructure a later slice',
			'      can carry.',
			'',
			'      Focus on architecture and approach, not line-by-line implementation.',
		].join('\n'),
	},
];

function parseArgs(argv) {
	const args = {};
	for (let i = 0; i < argv.length; i += 1) {
		const key = argv[i];
		if (!key.startsWith('--')) fail(`expected --option, got ${key}`);
		const name = key.slice(2);
		const next = argv[i + 1];
		if (next === undefined || next.startsWith('--')) {
			args[name] = true;
		} else {
			args[name] = next;
			i += 1;
		}
	}
	if (!args['package-root']) fail('--package-root is required');
	if (!args.out) fail('--out is required');
	return args;
}

/**
 * Ablation switches, used by the A/B experiment only. The image build passes
 * neither, so the production patch always applies all five edits.
 *   --skip-example  keep the upstream worked example, change only the rules
 *   --skip-rules    change only the worked example, keep the upstream rules
 */
function activePatches(args) {
	if (args['skip-example']) return REPLACEMENTS.filter((r) => !r.isExample);
	if (args['skip-rules']) return REPLACEMENTS.filter((r) => r.isExample);
	return REPLACEMENTS;
}

function fail(message) {
	console.error(`patch_schema: ERROR: ${message}`);
	process.exit(1);
}

function countOccurrences(haystack, needle) {
	return haystack.split(needle).length - 1;
}

const args = parseArgs(process.argv.slice(2));
const openspecVersion = args['openspec-version'] ?? 'unknown';

const srcDir = join(args['package-root'], 'schemas', SCHEMA_NAME);
const srcYaml = join(srcDir, 'schema.yaml');
const srcTemplates = join(srcDir, 'templates');
if (!existsSync(srcYaml)) fail(`upstream schema not found: ${srcYaml}`);
if (!existsSync(srcTemplates)) fail(`upstream templates not found: ${srcTemplates}`);

const upstream = readFileSync(srcYaml);
let text = upstream.toString('utf8');
const applied = [];

for (const { find, replace, why } of activePatches(args)) {
	const hits = countOccurrences(text, find);
	if (hits !== 1) {
		fail(
			`anchor for '${why}' matched ${hits} times, expected exactly 1. ` +
				'The upstream schema changed shape. Update patch_schema.js before this ' +
				'image is built.',
		);
	}
	text = text.replace(find, replace);
	applied.push(why);
}

const outRoot = args.out;
const outDir = join(outRoot, SCHEMA_NAME);
const staging = mkdtempSync(join(tmpdir(), 'openspec-schema-'));
const stagedDir = join(staging, SCHEMA_NAME);
mkdirSync(stagedDir, { recursive: true });

writeFileSync(join(stagedDir, 'schema.yaml'), text, { encoding: 'utf8', flag: 'wx' });
cpSync(srcTemplates, join(stagedDir, 'templates'), { recursive: true });

const manifest = [
	'# Generated at image build time. Do not edit; edit patch_schema.js.',
	`schema: ${SCHEMA_NAME}`,
	`generated_utc: ${new Date().toISOString()}`,
	'generated_by: patch_schema.js',
	`openspec_version: ${openspecVersion}`,
	`upstream_schema_sha256: ${createHash('sha256').update(upstream).digest('hex')}`,
	'patches_applied:',
	...applied.map((why) => `  - ${why}`),
	'',
].join('\n');
writeFileSync(join(stagedDir, '.override-manifest.yaml'), manifest, 'utf8');

// Stage first, then swap: a failed anchor check above leaves the previous
// override untouched.
mkdirSync(outRoot, { recursive: true });
rmSync(outDir, { recursive: true, force: true });
renameSync(stagedDir, outDir);
rmSync(staging, { recursive: true, force: true });

console.log(
	`patch_schema: wrote ${outDir} ` +
		`(upstream sha256 ${createHash('sha256').update(upstream).digest('hex').slice(0, 12)}, ` +
		`${applied.length} patches applied)`,
);
