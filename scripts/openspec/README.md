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

The scripts are verified against `@fission-ai/openspec@1.14.1` outside Docker.
The Dockerfile wiring is not applied yet; it is specified in the image ticket in
this repository's issue tracker.
