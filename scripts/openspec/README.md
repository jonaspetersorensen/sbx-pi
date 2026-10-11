# OpenSpec schema override scripts

These scripts give every project created in this sandbox image the same task
planning rules: vertical slices, and a tracer bullet first.

They work through one mechanism. OpenSpec resolves a workflow schema from
three places, in this order:

1. project — `./openspec/schemas/<name>/`
2. user — `${XDG_DATA_HOME:-~/.local/share}/openspec/schemas/`
3. the schema built into the installed package

A schema written to the **user** directory shadows the built-in `spec-driven`
schema. Projects inherit it with no per-project file and no action from the
model.

`openspec/config.yaml` cannot do this. That file is project-only, its `rules:`
key only adds to the built-in instruction, and the machine-wide
`~/.config/openspec/config.json` does not read rules at all. See
[`pi-agent-configs#498`](https://github.com/jonaspetersorensen/pi-agent-configs/issues/498)
for the decision record and the measurements behind it.

## Files

| file | purpose |
|---|---|
| `patch_schema.mjs` | Build step. Reads the schema from the installed package, applies five anchored edits, writes the override plus `.override-manifest.yaml`. Node only, no dependencies. |
| `verify.sh` | 22 mechanism checks: resolution, injection, idempotency, drift guard, project opt-out. |
| `ab_slice_test.mjs` | Behaviour A/B against an OpenAI-compatible endpoint: upstream schema versus rules-only versus full override. |

## Patched behaviour

1. The schema description says `sandbox override`, so `openspec schemas` reveals the shadow.
2. Task groups are vertical slices. A group that touches one technical layer gets split.
3. The first implementation group is a tracer bullet. Stubs need disclosure. A failing end-to-end check stops the slice.
4. The upstream worked example, which shows `## 1. Setup` then `## 2. Core Implementation`, is replaced.
5. `design` names the tracer bullet before tasks exist.

Point 4 carries most of the effect. With the rules injected and the upstream
example left in place, the test model still opened with `## 1. Setup` and put
the tracer bullet second.

Every anchor must match exactly once, or `patch_schema.mjs` exits non-zero and
writes nothing. That is the drift guard: when upstream rewords the workflow,
the image build stops instead of shipping a stale fork.

## Run the checks

Both scripts read the installed package from disk, so install OpenSpec first; a
fresh sandbox has no cached copy. Set `OSX_PKG` to the package root, that is the
directory that contains `schemas/spec-driven/`:

```sh
OSX_PKG="$(dirname "$(readlink -f "$(command -v openspec)")")/.."
OSX_PKG="${OSX_PKG}" bash verify.sh
```

The behaviour test also needs a model endpoint:

```sh
node ab_slice_test.mjs --runs 2 \
  --base-url http://192.168.1.235:11234/v1 \
  --model qwen3.8-flash-next@iq4_xs
```

## Drift runbook

If the build fails with `anchor for '...' matched 0 times`:

1. Diff the upstream schema against the last one you patched, at
   `${OPENSPEC_PKG}/schemas/spec-driven/schema.yaml`.
2. Update the affected `find` string in `patch_schema.mjs`. Keep the intent, not
   the old wording.
3. Run `verify.sh`, then rebuild.

Never hand-edit the generated override in `${XDG_DATA_HOME:-~/.local/share}/openspec/schemas`.
Every build rewrites it.

## Status

The scripts are verified against `@fission-ai/openspec@1.14.1`, outside Docker and
inside the built image: `verify.sh` passes 22 of 22 checks there.

Read the scope of that number before you rely on it. `verify.sh` does not read
the baked image. It sets its own `HOME`, unsets `XDG_DATA_HOME` and
`XDG_CONFIG_HOME`, and regenerates the override in a temporary home, so it checks
the mechanism and never the shipped override or the shipped global config. The
Dockerfile smoke layer is what checks the baked artifacts.

The Dockerfile applies the wiring. It installs
`@fission-ai/openspec@${OPENSPEC_VERSION}` (default `1.14.1`), runs
`patch_schema.mjs` into the user schemas directory, writes the global config
(`profile: custom`, `delivery: commands`, nine workflows), and runs a smoke check
that asserts the override resolves from the user directory, that a task
instruction mentions the tracer bullet, that `openspec init --tools pi` writes
nine prompt files and no `.pi/skills`, and that the baked config still reports
`delivery=commands` and `profile=custom`. A broken override therefore fails the
build instead of the first session. Raise the version with `--build-arg
OPENSPEC_VERSION=...`.

The image sets `OPENSPEC_NO_UPDATE_CHECK=1` and `OPENSPEC_TELEMETRY=0` as `ENV`,
so they also hold at run time. Without the first, a session could update the
package to `latest` and leave the override, which was generated from the older
version, behind. That is the drift the anchor gate prevents at build time.
Upgrade only by rebuilding with a new `OPENSPEC_VERSION`.
