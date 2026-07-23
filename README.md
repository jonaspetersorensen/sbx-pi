# sbx-pi

Custom template image for running [Pi Coding Agent](https://pi.dev/) inside Docker Sandboxes `sbx`.


## Docs 

- [Pi Coding Agent](https://pi.dev/)
  - [Releases | Github](https://github.com/earendil-works/pi/releases)
- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)


## How to build, load and run a local template

The `Dockerfile` extends the `shell` base image, so run it with the `shell` agent.

 ```sh
# 1. Build and tag the image locally
PI_VERSION=0.81.1
docker build --build-arg "PI_VERSION=${PI_VERSION}" -t "sbx-pi:${PI_VERSION}" .

# 2. Load the local image into the sandbox runtime (its image store is separate from your host Docker)
docker image save "sbx-pi:${PI_VERSION}" -o "./out/sbx-pi-v${PI_VERSION}.tar"
sbx template load "./out/sbx-pi-v${PI_VERSION}.tar"

# 3. Create and run a sandbox using the template
sbx run --name pi --template "sbx-pi:${PI_VERSION}" shell
```

The `pi` coding agent launches automatically in the interactive shell.
