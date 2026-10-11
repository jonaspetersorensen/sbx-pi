# Proposal

## Why

`build.sh` is the documented way to build and load this image, but it only forwards the Pi
version to `docker build`. `OPENSPEC_VERSION` is a second pin the image supports and the
README documents (`ARG OPENSPEC_VERSION=1.14.1`, consumed by the `npm install -g
@fission-ai/openspec@${OPENSPEC_VERSION}` step), yet the README has to concede that
"`build.sh` does not expose `OPENSPEC_VERSION` yet, so it always uses the Dockerfile
default" — the documented per-build pin is unreachable through the entry point everyone is
told to use. Separately, both `build.sh` (final run hint) and the README quick start point at
a root `kit/` directory that does not exist; the only kit in the repo lives at
`kits/github-copilot/`, so the first command a new reader runs after a successful build
fails.

## What Changes

- `build.sh`: accept an OpenSpec version override as a `--openspec-version VER` option and
  as an `OPENSPEC_VERSION` environment variable, mirroring how `PI_VERSION` is already
  handled, and append `--build-arg OPENSPEC_VERSION=<ver>` to the `docker build` command
  when an override is supplied. When no override is supplied, emit no `OPENSPEC_VERSION`
  build arg so the Dockerfile default keeps winning.
- `build.sh`: list the new option and environment variable in `usage()`.
- `build.sh`: change the closing run hint so it names a kit path that exists, in the
  current `sbx run --name <sandbox> ./kits/<kit>/ <workspace>` form, instead of
  `sbx run <script dir>/kit`.
- `README.md`: replace `sbx run ./kit` in manual step 3 with the same kit-path form the
  Copilot section already uses, and delete the now-false sentence saying `build.sh` does
  not expose `OPENSPEC_VERSION`.
- No change to how an unpinned build behaves: same image tags, same tar path, same
  interactive prompts.

Explicitly out of scope for this change:

- `pi-agent-configs/README.md` Development section, which still shows `sbx-pi:0.83.0` —
  that is a different repository and a different commit.
- `Dockerfile`, including its `ARG OPENSPEC_VERSION=1.14.1` default, which stays the single
  source of truth for an unpinned build.
- `scripts/openspec/` (the override patcher, verifier, and its README).
- The `generated_utc` timestamp in the generated override manifest.

## Capabilities

### New Capabilities

- `image-build-version-pinning`: the local build entry point exposes a version override for
  every version the image build can pin, and passes a pin to the image build only when the
  operator supplied one.
- `kit-run-guidance`: the run guidance this repository emits (build script output and README
  quick start) names kit paths that exist in this repository, in the argument form the
  sandbox CLI currently accepts.

### Modified Capabilities

None. `openspec list --specs` reports no specs in this project yet, so there is no existing
capability whose requirements can change; both capabilities above are new.

## Impact

- Files this change may touch: `build.sh`, `README.md`. Nothing else.
- Behaviour: additive. An unpinned `source build.sh` must produce the same `docker build`
  argument list it produces today; the new build arg appears only when the operator asks
  for a specific OpenSpec version.
- Interface: `build.sh` gains one option and one environment variable. `build.sh` is
  sourced (`source build.sh`), so its existing `return`-based control flow and its use of
  `BASH_SOURCE`/`SCRIPT_DIR` must keep working under sourcing.
- Docs: README quick start step 3 and the "Bump OpenSpec" section.
- No Dockerfile, image-layer, dependency, or `scripts/openspec/` changes; no change to the
  baked OpenSpec override or its verification checks.
