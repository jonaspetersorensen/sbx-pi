# sbx-pi

Custom template image for running [Pi Coding Agent](https://pi.dev/) inside Docker Sandboxes `sbx`.

Keep Pi customizations in a separate, version-controlled config repo that you install as a Pi package, copy or symlink into your personal pi-sandbox rather than hard-baking everything into this template.

## Docs

- [Pi Coding Agent](https://pi.dev/)
  - [Releases | Github](https://github.com/earendil-works/pi/releases)
- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
- Example pi-config repo: [pi-agent-config](https://github.com/LEUNGUU/pi-agent-config)


## How to build, load and run a local template

### Quick start (script)

```sh
# Build + load
source build.sh

# Custom version
source build.sh --version 0.85.1
```

### Manual steps

```sh
# 1. Build and tag the image locally
PI_VERSION=0.85.1
docker build --build-arg "PI_VERSION=${PI_VERSION}" \
  -t "sbx-pi:${PI_VERSION}" -t "sbx-pi:latest" .

# 2. Load the local image into the sandbox runtime (its image store is separate from your host Docker)
docker image save "sbx-pi:${PI_VERSION}" "sbx-pi:latest" \
  -o "./out/sbx-pi-v${PI_VERSION}.tar"
sbx template load "./out/sbx-pi-v${PI_VERSION}.tar"

# 3. Create and run the sandbox kit.
sbx run --name <sandbox-name> ./kits/github-copilot/ .
```

The `pi` coding agent will launch automatically in the interactive shell.

### Update git settings

Docker sandboxes come with a _clean_ git install, update the config to match your values.

```sh
# Read your current settings on host
git config --global user.name
git config --global user.email

# Start a shell inside the sandbox
sbx exec -it <sandbox-name> bash

# When inside set the config, it will persist:
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```



## OpenSpec

The image installs the OpenSpec CLI and ships a task-planning override that every
project in the sandbox inherits.

The override shadows the built-in `spec-driven` schema. OpenSpec resolves a schema
from the project first, then the user directory, then the installed package. The
image writes the override to the user directory
(`~/.local/share/openspec/schemas/spec-driven`), so a project needs no file and no
setup.

The image generates the override at build time.
`scripts/openspec/patch_schema.mjs` reads the schema out of the installed package,
applies five anchored edits, and writes the result. If upstream rewording moves an
anchor, the patch stops and the build fails. That is intentional: a stale copy of
the upstream workflow never ships.

The image also bakes the global config to `profile: custom`, `delivery: commands`,
and nine workflows. `openspec init --tools pi` then writes nine prompt files under
`.pi/prompts/` and writes no `.pi/skills/`.

### Opt one project out

Copy the package schema (`$(npm root -g)/@fission-ai/openspec/schemas/spec-driven`)
into `openspec/schemas/spec-driven/` inside that project. A project schema wins over
the user override. To drop the override for the whole image, delete
`~/.local/share/openspec/schemas/spec-driven`; resolution falls back to the package
schema.

### Bump OpenSpec

```sh
docker build --build-arg OPENSPEC_VERSION=1.14.1 -t sbx-pi:0.99.1 .
```

The image sets `OPENSPEC_NO_UPDATE_CHECK=1`, so the CLI never updates itself and
never replaces the package underneath the baked override. Upgrade only here, in a
rebuild, where the anchor gate can check the new version.

If the build fails with `anchor for '...' matched 0 times`, upstream reworded the
workflow. Update the anchors in `scripts/openspec/patch_schema.mjs`, then run
`scripts/openspec/verify.sh`. Never hand-edit the generated override; every build
rewrites it. The script form of the same pin is `source build.sh --openspec-version
1.14.1` (it also honours an exported `OPENSPEC_VERSION`); with no override it sends no
`OPENSPEC_VERSION` build arg and the Dockerfile default is used. See
`scripts/openspec/README.md` for the mechanism, the 22 checks, and the drift runbook.

`build.sh` is sourced, so an exported `OPENSPEC_VERSION` stays set in your shell and
applies to every later build. After a pinned build, run `unset OPENSPEC_VERSION`, or
build in a subshell: `bash -c 'source build.sh --openspec-version 1.14.1'`.

## Configure GitHub Copilot authentication

1. Add a sbx secret for copilot 
1. Add `github-copilot` as a provider in pi `models.json` (not in scope of this repo)
1. Create sandbox using the github-copilot kit to configure proxy-managed credentials using the secret we declared in step 1 


### Step 1: Add secret 

`secret set copilot --command 'gh auth token'`

### Step 2: Add github-copilot as a provider in pi model.json 

Example:
```json
{
  "providers": {
    "github-copilot": {
      "baseUrl": "https://api.githubcopilot.com"
    }
  }
}
```

### Step 3: Create sandbox using the github-copilot kit 

```
# Note that parameter "--kit" is deprecated.
# Kits should now be inserted into first positional slot and workspace in last slot
sbx run --name my-pi-copilot ./kits/github-copilot/ .
```

