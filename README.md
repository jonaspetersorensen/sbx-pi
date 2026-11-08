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
source build.sh --version 1.1.0
```

With no `--version`, `build.sh` offers the latest Pi release and falls back to
`DEFAULT_PI_VERSION`, which equals `ARG PI_VERSION` in `Dockerfile`.

### Manual steps

```sh
# 1. Build and tag the image locally
PI_VERSION=1.1.0
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
docker build --build-arg OPENSPEC_VERSION=1.14.1 -t sbx-pi:1.1.0 .
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

`build.sh` runs in a child shell even when sourced, so a failure or abort never closes your
terminal or tmux pane, and `--openspec-version` does not leak into your shell. An exported
`OPENSPEC_VERSION` is still honoured.

## Bump pinned versions

`scripts/bump_versions.sh` looks up the latest Node.js LTS major, Pi, GitHub CLI and OpenSpec
releases and pins them as exact defaults in `Dockerfile` and `build.sh`. Use `--dry-run` to
preview. After a bump, rebuild; if the build fails with `anchor for '...' matched 0 times`,
follow the OpenSpec drift steps above.

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


## Configure the local Qwen endpoint key

The local endpoint (`http://192.168.1.235:11234/v1`) speaks plain HTTP and requires a Bearer
key. A kit `credentials` entry cannot inject over plain HTTP (the proxy forwards it unchanged and
the endpoint answers `401`). A host side custom secret does work: the sandbox holds a
placeholder, and the egress proxy swaps in the real key in the request headers.

### Choose a kit

`sbx run` accepts one kit, so pick the one that matches the providers you need:

| Kit | Use it for |
| --- | --- |
| `./kits/local-qwen/` | Local Qwen only. Opens the network route to `192.168.1.235`. |
| `./kits/github-copilot/` | Copilot only. Adds the Copilot credential. |
| `./kits/all/` | Copilot and local Qwen in one sandbox. Keep it in sync with the other two. |

The `local-qwen` and `all` kits carry no key. The key comes from a host side custom secret
(step 1), so it works the same with either kit.

### Step 1: Add the custom secret (before creating the sandbox)

```sh
# Reads the key without putting it in shell history
read -rsp 'Local Qwen API key: ' KEY; echo
sbx secret set-custom --host 192.168.1.235 --env LOCAL_QWEN_API_KEY \
  --placeholder 'local-qwen-{rand}' --value "$KEY"
unset KEY
```

The secret is global, so every new sandbox gets `LOCAL_QWEN_API_KEY` set to the placeholder.
It does not appear in a sandbox that already exists; recreate that sandbox.

### Step 2: Point pi at the endpoint (not in scope of this repo)

In pi `models.json`, read the key from the environment variable:

```json
{
  "providers": {
    "local-qwen": {
      "baseUrl": "http://192.168.1.235:11234/v1",
      "api": "openai-completions",
      "apiKey": "${LOCAL_QWEN_API_KEY}"
    }
  }
}
```

### Step 3: Create the sandbox

```sh
# Local Qwen only
sbx run --name my-pi-qwen ./kits/local-qwen/ .

# Copilot and local Qwen
sbx run --name my-pi-all ./kits/all/ .
```

### Step 4: Verify

Run inside the sandbox. Only a request that reaches the endpoint proves the swap; `pi auth check`
reports `ready` for any value.

```sh
echo "$LOCAL_QWEN_API_KEY"   # prints local-qwen-<random>, never the real key
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $LOCAL_QWEN_API_KEY" http://192.168.1.235:11234/v1/models   # expect 200
curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'Authorization: Bearer anything' http://192.168.1.235:11234/v1/models              # expect 401
```

The `200` and the `401` together show the test can fail. If the first call returns `401`, the
secret was missing when the sandbox was created.

`scripts/verify_credential_proxy.sh` checks the Copilot hosts in a kit and reports `injected`,
`passthrough` (key not replaced), `421` (host in `inject` but not in `network.allow`) or
`unreachable`. It sends a bogus key, so it does not apply to the Qwen custom secret; use the
`curl` calls above.

### Rotate or remove the key

```sh
sbx secret ls                    # lists custom secrets, with placeholder and target host
sbx secret rm --help             # remove the custom secret, then run step 1 again to rotate
```

Recreate sandboxes after a change so they pick up the new placeholder.

### Limits

- The proxy replaces the header whatever the client sends. It hides the key; it does not limit which process may use the endpoint.
- The endpoint speaks plain HTTP, so the key crosses the LAN in clear text. TLS on port 11234 would not help the swap: the proxy tunnels HTTPS on non-443 ports without inspecting it.
- Any process that reaches the proxy can call every registered host.
- The custom secret lives on the host, not in the kit. Create it before the sandbox, or `LOCAL_QWEN_API_KEY` is unset.
