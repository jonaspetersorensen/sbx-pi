#!/usr/bin/env bash
# Acceptance checks for the OpenSpec "shadow + build-time patch" design.
#
# Simulates one image build (the patch step) plus fresh sandbox projects, and
# asserts the properties the design depends on. Needs only: node, git, coreutils,
# sed. No python.
#
# Usage: bash verify.sh            # uses /tmp/osx/package as the openspec package
#        OSX_PKG=/path/to/openspec-package bash verify.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSX_PKG="${OSX_PKG:-/tmp/osx/package}"
OSX_BIN="${OSX_BIN:-node ${OSX_PKG}/bin/openspec.js}"
OSX="${OSX_BIN}"
RUN="$(mktemp -d /tmp/osx-verify.XXXXXX)"

# Preflight: the checks read the schema out of an installed openspec package.
if [ ! -f "${OSX_PKG}/schemas/spec-driven/schema.yaml" ]; then
	printf 'OSX_PKG (%s) has no schemas/spec-driven/schema.yaml.\n' "${OSX_PKG}" >&2
	printf 'Point OSX_PKG at the installed @fission-ai/openspec package, for example:\n' >&2
	printf '  npm install -g --ignore-scripts @fission-ai/openspec@1.14.1\n' >&2
	printf '  export NPM_CONFIG_PREFIX="$HOME/.npm-global"\n' >&2
	printf '  OSX_PKG="$(dirname "$(readlink -f "$(command -v openspec)")")/.." bash verify.sh\n' >&2
	printf 'A fresh sandbox has no cached copy, so install first.\n' >&2
	exit 2
fi
if ! command -v node >/dev/null 2>&1; then
	printf 'node is required and was not found on PATH.\n' >&2
	exit 2
fi

# A clean HOME simulates a sandbox that has never run openspec.
export HOME="${RUN}/home"
export OPENSPEC_TELEMETRY=0
export OPENSPEC_NO_UPDATE_CHECK=1
unset XDG_DATA_HOME XDG_CONFIG_HOME
mkdir -p "${HOME}"

PASS=0
FAIL=0
ok() {
	PASS=$((PASS + 1))
	printf '  PASS  %s\n' "$1"
}
bad() {
	FAIL=$((FAIL + 1))
	printf '  FAIL  %s\n' "$1"
}
has() {
	grep -qF -- "$2" <<<"$1"
}

echo "== build step: derive the user-level override from the package =="
USER_SCHEMAS="${HOME}/.local/share/openspec/schemas"
node "${HERE}/patch_schema.mjs" \
	--package-root "${OSX_PKG}" \
	--out "${USER_SCHEMAS}" \
	--openspec-version "test" || {
	echo "  FAIL  build step exited non-zero"
	exit 1
}

mkproj() {
	local d="${RUN}/$1"
	mkdir -p "${d}"
	(
		cd "${d}" || exit 1
		git init -q . 2>/dev/null
		${OSX} init --tools pi --no-animation --no-copilot-cloud >/dev/null 2>&1
		${OSX} new change probe >/dev/null 2>&1
	)
	echo "${d}"
}

PROJ="$(mkproj proj-a)"
tasks() { (cd "${PROJ}" && ${OSX} instructions tasks --change probe 2>/dev/null); }

TASKS="$(tasks)"
DESIGN="$(cd "${PROJ}" && ${OSX} instructions design --change probe 2>/dev/null)"
WHICH="$(cd "${PROJ}" && ${OSX} schema which spec-driven 2>/dev/null)"
LIST="$(cd "${PROJ}" && ${OSX} schemas 2>/dev/null)"

echo "== resolves from the user dir with no project setup =="
has "$WHICH" "Source: user" && ok "V1 override resolves from the user schema dir" \
	|| bad "V1 override did not resolve from the user dir: ${WHICH}"
has "$LIST" "user override" && ok "V2 'openspec schemas' shows the override" \
	|| bad "V2 override not listed in 'openspec schemas'"

echo "== tracer-bullet guidance reaches the model =="
has "$TASKS" "tracer" && ok "V3 tasks instruction carries tracer-bullet guidance" \
	|| bad "V3 tracer guidance missing from the tasks instruction"
has "$TASKS" "vertical slice" && ok "V3b task groups declared as vertical slices" \
	|| bad "V3b vertical-slice wording missing"
has "$TASKS" "## 1. Setup" && bad "V4 layer-first example still present" \
	|| ok "V4 upstream layer-first example removed"
has "$TASKS" "Create new module structure" && bad "V4b setup-first example survived" \
	|| ok "V4b upstream setup example replaced"
has "$DESIGN" "Tracer bullet:" && ok "V5 design instruction names the tracer bullet" \
	|| bad "V5 design guidance missing"

echo "== patched schema is a valid schema =="
VAL="$(cd "${PROJ}" && ${OSX} schema validate spec-driven 2>&1)"
has "$VAL" "valid" && ok "V6 'openspec schema validate' accepts the patched schema" \
	|| bad "V6 validation failed: $(head -3 <<<"$VAL")"
TEMPL="$(cd "${PROJ}" && ${OSX} templates --schema spec-driven --json 2>/dev/null)"
has "$TEMPL" ".local/share/openspec/schemas" && ok "V7 templates resolve from the override" \
	|| bad "V7 templates did not resolve from the override"

echo "== no per-project config needed =="
CFG="${PROJ}/openspec/config.yaml"
grep -qE '^(rules|context|operations):' "${CFG}" \
	&& bad "V8 init wrote active rules; the test is not clean" \
	|| ok "V8 project config.yaml has no active rules; guidance came from the override"
grep -qE '^schema: spec-driven$' "${CFG}" \
	&& ok "V8b stock project config.yaml works unedited" \
	|| bad "V8b config.yaml does not select spec-driven"

echo "== control: without the override, upstream behaviour is unchanged =="
BASE_HOME="${RUN}/home-bare"
CTRL="${RUN}/proj-ctrl"
mkdir -p "${BASE_HOME}" "${CTRL}"
(
	cd "${CTRL}" || exit 1
	HOME="${BASE_HOME}" ${OSX} init --tools pi --no-animation --no-copilot-cloud >/dev/null 2>&1
	HOME="${BASE_HOME}" ${OSX} new change probe >/dev/null 2>&1
	HOME="${BASE_HOME}" ${OSX} instructions tasks --change probe 2>/dev/null
) >"${RUN}/ctrl-tasks.txt"
CTRL_TASKS="$(cat "${RUN}/ctrl-tasks.txt")"
if has "$CTRL_TASKS" "## 1. Setup" && ! has "$CTRL_TASKS" "tracer"; then
	ok "V9 control (no override) still shows the upstream layer-first example"
else
	bad "V9 control unexpected: the patch may not be what changed the output"
fi

echo "== generated Pi prompts do not fight the schema =="
PROMPTS="$(cat "${PROJ}/.pi/prompts/"*.md 2>/dev/null)"
has "$PROMPTS" "database, service" && bad "V10 a Pi prompt prescribes layer-based grouping" \
	|| ok "V10 generated Pi prompts carry no competing grouping rule"

echo "== patch is idempotent =="
SUM1="$(sha256sum "${USER_SCHEMAS}/spec-driven/schema.yaml" | cut -d' ' -f1)"
node "${HERE}/patch_schema.mjs" --package-root "${OSX_PKG}" --out "${USER_SCHEMAS}" \
	--openspec-version "test" >/dev/null 2>&1
SUM2="$(sha256sum "${USER_SCHEMAS}/spec-driven/schema.yaml" | cut -d' ' -f1)"
[ "${SUM1}" = "${SUM2}" ] && ok "V11 re-running the patch is byte-identical" \
	|| bad "V11 patch is not idempotent (${SUM1:0:8} vs ${SUM2:0:8})"

echo "== drift guard: a changed upstream anchor fails the build =="
DRIFT="${RUN}/drift"
mkdir -p "${DRIFT}/schemas"
cp -r "${OSX_PKG}/schemas/spec-driven" "${DRIFT}/schemas/spec-driven"
sed -i 's/- Order tasks by dependency (what must be done first?)/- Order tasks however the model prefers./' \
	"${DRIFT}/schemas/spec-driven/schema.yaml"
ERR="$(node "${HERE}/patch_schema.mjs" --package-root "${DRIFT}" \
	--out "${RUN}/drift-out" 2>&1)"
RC=$?
if [ $RC -ne 0 ] && has "$ERR" "anchor"; then
	ok "V12 build fails loudly when an anchor disappears"
else
	bad "V12 patch accepted a changed upstream (rc=${RC})"
fi
[ -e "${RUN}/drift-out/spec-driven/schema.yaml" ] \
	&& bad "V13 failed patch still wrote an override" \
	|| ok "V13 a failed patch writes nothing"

echo "== manifest records upstream drift =="
MAN="${USER_SCHEMAS}/spec-driven/.override-manifest.yaml"
NOW="$(sha256sum "${DRIFT}/schemas/spec-driven/schema.yaml" | cut -d' ' -f1)"
grep -q "upstream_schema_sha256: ${NOW}" "${MAN}" \
	&& bad "V14 manifest hash matches the drifted schema; drift is invisible" \
	|| ok "V14 manifest hash detects that the upstream schema changed"
grep -q "^patches_applied:" "${MAN}" && ok "V14b manifest lists the applied patches" \
	|| bad "V14b manifest has no patch list"

echo "== a project can still opt out =="
PROJ2="$(mkproj proj-b)"
mkdir -p "${PROJ2}/openspec/schemas"
cp -r "${OSX_PKG}/schemas/spec-driven" "${PROJ2}/openspec/schemas/spec-driven"
W2="$(cd "${PROJ2}" && ${OSX} schema which spec-driven 2>/dev/null)"
T2="$(cd "${PROJ2}" && ${OSX} instructions tasks --change probe 2>/dev/null)"
if has "$W2" "Source: project" && ! has "$T2" "tracer"; then
	ok "V15 a project opts out with its own openspec/schemas/spec-driven"
else
	bad "V15 project override did not take precedence: $(head -2 <<<"$W2")"
fi

echo "== untouched artifacts still resolve =="
PROP="$(cd "${PROJ}" && ${OSX} instructions proposal --change probe 2>&1)"
ARCF="$(cd "${PROJ}" && ${OSX} instructions archive --change probe 2>&1)"
if has "$PROP" "Why" && ! has "$PROP" "Error"; then
	ok "V16 proposal instruction unaffected"
else
	bad "V16 proposal instruction broke"
fi
has "$ARCF" "Error:" && bad "V17 archive instruction broke" || ok "V17 archive instruction unaffected"

echo "== 'openspec update' does not clobber the override =="
(
	cd "${PROJ}" || exit 1
	${OSX} update --force >/dev/null 2>&1
	${OSX} schema which spec-driven 2>/dev/null
	${OSX} instructions tasks --change probe 2>/dev/null
) >"${RUN}/after-update.txt"
AFTER="$(cat "${RUN}/after-update.txt")"
if has "$AFTER" "Source: user" && has "$AFTER" "tracer"; then
	ok "V18 'openspec update' leaves the user override in force"
else
	bad "V18 'openspec update' changed the override"
fi

echo
echo "== artifacts for inspection =="
echo "  override : ${USER_SCHEMAS}/spec-driven/schema.yaml"
echo "  manifest : ${USER_SCHEMAS}/spec-driven/.override-manifest.yaml"
echo "  project  : ${PROJ}"
echo "  run dir  : ${RUN}"
echo
printf 'RESULT: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
