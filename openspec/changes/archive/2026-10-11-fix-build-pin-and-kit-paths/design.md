# Design

## Context

See `proposal.md` — Why, and `specs/*/spec.md` for the requirements. Only the current-state
facts that constrain the approach:

- `build.sh` is sourced (`source build.sh`), so it uses `return` rather than `exit`, and its
  option parser is a hand-rolled `while [[ $# -gt 0 ]]; case ...` loop. `usage()` documents
  options and an `Environment:` block that today lists only `PI_VERSION`.
- Pi version resolution has two paths that write the same `PI_VERSION` variable: the
  environment variable (non-empty `PI_VERSION` skips the release selector) and
  `--version VER` (assigns the same variable, also skipping the selector).
- The image build already receives an array of build args, `BUILD_ARGS`, seeded with
  `PI_VERSION` and conditionally appended with `GIT_USER_NAME` / `GIT_USER_EMAIL`. Both the
  `docker` and `sudo docker` branches expand the same array, so there is exactly one append
  site to change.
- `Dockerfile` declares `ARG OPENSPEC_VERSION=1.14.1` and uses it to install
  `@fission-ai/openspec@${OPENSPEC_VERSION}`; that default is the only version default in the
  system today.
- The closing line of the script is `echo "To run the kit: sbx run ${SCRIPT_DIR}/kit"`. No
  root `kit/` exists; the kits live under `${SCRIPT_DIR}/kits/` (currently
  `kits/github-copilot/`). The README's Copilot section already shows the current CLI form:
  `sbx run --name my-pi-copilot ./kits/github-copilot/ .`, with a note that `--kit` is
  deprecated and the workspace is the last positional argument.

## Goals / Non-Goals

**Goals:**

- One default per pin, living in the `Dockerfile`; `build.sh` stays silent about
  `OPENSPEC_VERSION` unless the operator supplies it.
- `build.sh`'s new option behaves like its closest existing neighbour (`--version`), so
  there is one mental model for "pin a version at build time".
- Run guidance that cannot rot the next time a kit is added, i.e. derived from the `kits/`
  directory rather than copied into prose twice.
- A way to prove both fixes on a machine with neither `docker` nor `sbx` installed.

**Non-Goals:**

- Changing which versions are default (`Dockerfile`), the override patcher/verifier under
  `scripts/openspec/`, or the `generated_utc` manifest field.
- Touching `pi-agent-configs/README.md`, which shows `sbx-pi:0.83.0` in its Development
  section (other repository, other commit).
- Reworking the existing looseness of the argument parser (a flag with no value, or
  `--version` with an empty value, behaves oddly today for `PI_VERSION`). Whatever is done
  for `OPENSPEC_VERSION` mirrors that behaviour instead of fixing it; a parser cleanup is a
  separate change.
- Fixing the relative `OUTPUT_TAR="out/sbx-pi-v${PI_VERSION}.tar"` in Step 2, which ignores
  the `OUTPUT_DIR`/`OUTPUT_TAR` computed from `SCRIPT_DIR` at the top of the file and so
  depends on the caller's working directory. It is a real defect, unrelated to the two this
  change fixes; it is recorded here only so it is not mistaken for part of this change.
- Adding files. This change edits `build.sh` and `README.md` only, so its verification has to
  be runnable from a shell without a committed test harness.

## Decisions

### D1 — A named option plus environment variable, not a generic build-arg passthrough

Add `--openspec-version VER` and honour an exported `OPENSPEC_VERSION`, writing both into one
`OPENSPEC_VERSION` variable exactly the way `--version` / `PI_VERSION` already work; the
option wins because it is assigned during parsing, after the environment value is already
present.

- Why: it matches the shape an operator already knows from this script, keeps `usage()` the
  single place where the pin surface is documented, and adds no new parsing concept.
- Alternative considered: a generic `--build-arg K=V` pass-through. Rejected: it silently
  allows overrides of `PI_VERSION` and the git args that already have dedicated flags, it
  makes `usage()` unhelpful, and it widens the interface far past the defect.
- Alternative considered: environment variable only. Rejected: the README's existing "custom
  version" affordance is a flag, and `source build.sh OPENSPEC_VERSION=...` is not a thing.

### D2 — Append the build arg only when non-empty

`if [[ -n "${OPENSPEC_VERSION:-}" ]]; then BUILD_ARGS+=("--build-arg"
"OPENSPEC_VERSION=${OPENSPEC_VERSION}"); fi`, placed with the existing conditional appends
and before the `docker build` call.

- Why: identical in shape to the `GIT_USER_NAME` / `GIT_USER_EMAIL` guards two lines above,
  and it guarantees an unpinned build sends exactly today's argument list, which is what
  keeps the `Dockerfile` default authoritative.
- Alternative considered: always send it, defaulting `OPENSPEC_VERSION` to `1.14.1` in the
  script. Rejected: two places holding the same version, which is the drift the Dockerfile
  ARG exists to avoid.

### D3 — Echo the effective pin in the summary, and in `usage()`

Add the option under `Options:` and the variable under `Environment:`, and print the OpenSpec
version in the existing `=== Summary ===` block only when an override was supplied (the same
conditional style the git identity lines use), before the "Proceed with build?" gate.

- Why: the environment-variable path is invisible by construction, and this script's only
  safety net is a summary the operator confirms before the build runs.

### D4 — Derive the run hint from `kits/`, one line per kit

Replace the final `echo` with a loop over the kit directories under `${SCRIPT_DIR}/kits/`,
printing one ready-to-paste line per kit in the current positional form
(`sbx run --name <sandbox-name> <script dir>/kits/<kit>/ <workspace>`), with the kit
directory name filled in and the sandbox name and workspace left as obvious placeholders. If
the glob matches nothing, print a single line that names `kits/` and says no kit was found
there, rather than inventing a path.

- Why: it names only paths that exist, which is the requirement, and it cannot go stale when
  a second kit lands — the exact failure mode being repaired.
- Alternative considered: hardcode `kits/github-copilot/`. Rejected for the same reason the
  current bug exists: prose that outlives the tree.
- Alternative considered: print the path only and keep `sbx run ./kit`-shaped arguments.
  Rejected: the deprecated `--kit` form and the missing workspace slot are half the defect.

### D5 — README keeps one canonical run command per audience

Manual step 3 becomes the positional form with a real kit path, matching the Copilot section
(`sbx run --name <name> ./kits/github-copilot/ .`). In "Bump OpenSpec", replace the sentence
that says `build.sh` does not expose `OPENSPEC_VERSION` with the sourced-script form
(`source build.sh --openspec-version 1.14.1`), leaving the explicit `docker build` example in
place as the manual path.

- Why: two run commands in one file that disagree is how the wrong one got copied; the
  Copilot section is already correct, so the quick start is made to match it rather than
  inventing a third form.

## Risks / Trade-offs

- [`source build.sh` in a shell that already exports `OPENSPEC_VERSION` for unrelated
  tooling silently changes what gets baked] → the summary prints the effective value before
  the build is confirmed, and `usage()` documents the variable, so the override is visible at
  the one gate the script already has.
- [The `kits/` glob prints nothing useful if the directory is renamed or empty] → the
  no-match branch names `kits/` explicitly and says nothing was found; it never prints a path
  it did not observe.
- [Two version flags invite an OpenSpec/Pi version pair that the image cannot satisfy] →
  unchanged from today's hand-run `docker build`; the image build itself fails if the
  OpenSpec version does not exist on npm. No new validation is invented here.
- [Mirroring `--version`'s parser looseness copies a wart (`--openspec-version` with no
  value aborts the sourced shell under `set -e`)] → accepted deliberately for consistency;
  fixing it means changing `--version` too, which is out of scope and would need its own
  requirement.
- [A kit-name-derived hint cannot be verified by `bash -n` alone] → mitigated by the tracer
  bullet below, which actually runs the closing lines with stub commands on `PATH`.

## Migration Plan

Additive; no migration and no data or interface to roll forward. Deploy is a single commit
touching `build.sh` and `README.md`. Rollback is reverting it: an unpinned `source build.sh`
behaves identically before and after, which is also the first regression check.

## Tracer bullet

Smallest end-to-end path: an operator pinning the OpenSpec version on a machine with no
`docker` and no `sbx`, and seeing that pin arrive at the image build command, with the
override discoverable in help and the effective value confirmed before the build starts.

Layers it crosses: `build.sh` argument parsing → `usage()`/summary surface → `BUILD_ARGS`
array → the `docker build` invocation. The highest-risk integration is the conditional append
reaching the actual `docker build` argument vector, because that is where an unset variable
could either drop the pin or inject `OPENSPEC_VERSION=` and override the Dockerfile default
with an empty value. The corrected closing run hint is a separate slice: it changes no value
that flows into the build, and the same stubbed run exercises it.

How it is exercised, without docker or sbx and without adding files to the repo: in a scratch
copy of the checkout, put a stub directory first on `PATH` containing a `docker` and an `sbx`
script that print their arguments one per line and exit 0; run
`printf 'Y\n' | source build.sh --version <pi> --git-user-name a --git-user-email b@x --openspec-version 1.14.1`
(the two git flags and `--version` skip the interactive release selector and git dialog, so
only the final confirmation reads stdin); assert the stub's captured `build` line contains
`--build-arg OPENSPEC_VERSION=1.14.1` and that the summary printed above it names the same
version. The same command with `--openspec-version` removed is the negative half of the same
slice and must show no `OPENSPEC_VERSION` on the `build` line. What stays unvalidated because
both `docker` and `sbx` are stubbed: that the image build accepts the argument and installs
the requested OpenSpec version, and that a printed run hint works against a real sandbox
runtime. A later task replaces the stub with one real docker-capable run.

Prerequisites that must exist first: none beyond the current tree — no new tool, no schema or
spec work, no refactor of `build.sh`. Infrastructure a later slice can carry: a permanent
check script for this run (deliberately not added, see Non-Goals), and any future dry-run
mode for `build.sh`.
