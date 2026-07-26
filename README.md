# sbx-pi

Custom template image for running [Pi Coding Agent](https://pi.dev/) inside Docker Sandboxes `sbx`.

Keep Pi customizations in a separate, version-controlled config repo that you install as a Pi package, copy or symlink into your personal pi-sandbox rather than hard-baking everything into this template.


## Docs 

- [Pi Coding Agent](https://pi.dev/)
  - [Releases | Github](https://github.com/earendil-works/pi/releases)
- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
- Example pi-config repo: [pi-agent-config](https://github.com/LEUNGUU/pi-agent-config)


## How to build, load and run a local template


 ```sh
# 1. Build and tag the image locally
PI_VERSION=0.82.1
docker build --build-arg "PI_VERSION=${PI_VERSION}" -t "sbx-pi:${PI_VERSION}" .

# 2. Load the local image into the sandbox runtime (its image store is separate from your host Docker)
docker image save "sbx-pi:${PI_VERSION}" -o "./out/sbx-pi-v${PI_VERSION}.tar"
sbx template load "./out/sbx-pi-v${PI_VERSION}.tar"

# 3. Create and run a sandbox using the template. This is where you add your pi customizations.
sbx run --name pi-sandbox --template "sbx-pi:${PI_VERSION}" shell
```

The `pi` coding agent will launch automatically in the interactive shell.


