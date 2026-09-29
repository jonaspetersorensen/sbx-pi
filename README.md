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
sbx run ./kit
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
sbx run --name my-pi-copilot --kit ./kits/github-copilot/ pi
```

