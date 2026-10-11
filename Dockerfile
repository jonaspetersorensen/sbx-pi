# System tools
# - nodejs: to build pi agent 
# - Research: 
#   - pandoc: a universal document converter for moving between markup and office formats. 
#   - html2text: converts HTML into plain tex
#   - lynx: a text-based web browser for terminals
# - Extras:
#   - socat: the runtime's in-VM ssh-agent forwarder is a socat process, which for some strange reason is not installed in the default shell template
#   - tmux: for multiple agents in the same terminal 

FROM docker/sandbox-templates:shell-docker

ARG NODEJS_MAJOR_VERSION=26
# Keep this default equal to DEFAULT_PI_VERSION in build.sh.
ARG PI_VERSION=1.1.0
ARG GITHUB_GH_VERSION=2.100.0
ARG OPENSPEC_VERSION=1.14.1
ARG GIT_USER_NAME
ARG GIT_USER_EMAIL

USER root

RUN apt-get update \
    && apt-get install -y curl ca-certificates gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_MAJOR_VERSION}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
       pandoc \
       html2text \
       lynx \
       socat \
       tmux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Update components that have outdated ubuntu packages
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GITHUB_GH_VERSION}/gh_${GITHUB_GH_VERSION}_linux_amd64.deb" -o /tmp/gh.deb && dpkg -i /tmp/gh.deb && rm /tmp/gh.deb

USER agent
WORKDIR /home/agent/workspace

# Install pi 
RUN mkdir -p "$HOME/.npm-global" \
  && npm config set prefix "$HOME/.npm-global" \
  && printf '\n# npm user-global prefix\nexport PATH="$HOME/.npm-global/bin:$PATH"\n' >> "$HOME/.bashrc" \
  && npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${PI_VERSION}

# Set bash to auto-launch pi 
RUN printf '\n# Auto-launch pi coding agent in interactive shells\nif [[ $- == *i* ]] && command -v pi &> /dev/null; then\n    exec pi\nfi\n' >> "$HOME/.bashrc"

# OpenSpec: pin the CLI, and keep the update check and telemetry off at build
# time and at run time, so ENV and not a per-layer export. The update check is
# opt-out and on by default (dist/core/version-check.js isCheckEnabled), and the
# copilot kit allow-lists registry.npmjs.org, so a live session could otherwise
# offer or run `npm install -g @fission-ai/openspec@latest` and replace the
# pinned package underneath an override generated from ${OPENSPEC_VERSION}. That
# is exactly the drift the anchor gate below exists to catch, so it stays off in
# the shipped image. OPENSPEC_TELEMETRY=0 also keeps a per-machine anonymous id
# out of the baked config.
ENV OPENSPEC_NO_UPDATE_CHECK=1 \
    OPENSPEC_TELEMETRY=0

# Install OpenSpec and derive the user-level schema override.
# The override in the user schemas directory shadows the built-in spec-driven
# schema for every project in the image, so shared task-planning rules need no
# per-project file. patch_schema.mjs reads the schema out of the installed
# package, applies five anchored edits, and fails this build when an anchor
# moves. See scripts/openspec/README.md.
# --mount=type=bind keeps the patch script out of the image; a COPY plus rm in a
# later layer would not, because the earlier layer keeps the file. Needs
# BuildKit, which the --mount syntax requires.
# Each layer exports PATH itself. The base image sets NPM_CONFIG_PREFIX, so npm
# installs to /usr/local/share/npm-global, which is already on PATH; if that env
# var ever goes away the ~/.npmrc prefix ($HOME/.npm-global) takes over, and RUN
# would need the export because a non-interactive RUN never reads ~/.bashrc.
# Both baked paths fall back to os.homedir(): the user schemas directory uses
# XDG_DATA_HOME, and the global config uses XDG_CONFIG_HOME. Neither is set here
# and neither is set by the base image, so build time and run time agree. A kit
# or runtime that sets either one, or runs as another user, silently stops the
# baked artifacts from resolving. Diagnose with:
#   openspec schema which spec-driven   -> must report Source: user
RUN --mount=type=bind,source=scripts/openspec/patch_schema.mjs,target=/tmp/patch_schema.mjs \
  export PATH="$HOME/.npm-global/bin:$PATH" \
  && npm install -g --ignore-scripts "@fission-ai/openspec@${OPENSPEC_VERSION}" \
  && OPENSPEC_PKG="$(dirname "$(readlink -f "$(command -v openspec)")")/.." \
  && echo "openspec ${OPENSPEC_VERSION} package root: ${OPENSPEC_PKG}" \
  && ls "${OPENSPEC_PKG}/schemas/spec-driven" \
  && node /tmp/patch_schema.mjs \
       --package-root "${OPENSPEC_PKG}" \
       --out "${XDG_DATA_HOME:-$HOME/.local/share}/openspec/schemas" \
       --openspec-version "${OPENSPEC_VERSION}"

# Bake the global OpenSpec config: prompt files only, and the nine workflows the
# design needs. The default delivery=both writes every workflow twice, and the
# default core profile leaves out new, continue and verify.
RUN export PATH="$HOME/.npm-global/bin:$PATH" \
  && openspec config set delivery commands \
  && openspec config set workflows '["propose","explore","apply","update","sync","archive","new","continue","verify"]' \
  && openspec config set profile custom \
  && echo "baked global openspec config:" \
  && cat "$HOME/.config/openspec/config.json"

# Build-time smoke check: a broken override fails the build, not the first
# session. Each check below stops the build, so a version bump that changes the
# delivery mode, the profile, or the prompt count fails here instead of in use.
RUN export PATH="$HOME/.npm-global/bin:$PATH" \
  && mkdir -p /tmp/osx-smoke && cd /tmp/osx-smoke && git init -q . \
  && openspec init --tools pi --no-animation >/dev/null \
  && openspec schema which spec-driven | grep -q "Source: user" \
  && openspec new change probe >/dev/null \
  && openspec instructions tasks --change probe | grep -q "tracer" \
  && test "$(ls -1 .pi/prompts | wc -l)" -eq 9 \
  && test ! -d .pi/skills \
  && grep -Eq '"delivery": *"commands"' "$HOME/.config/openspec/config.json" \
  && grep -Eq '"profile": *"custom"' "$HOME/.config/openspec/config.json" \
  && echo "smoke: 9 prompt files, no .pi/skills, delivery=commands, profile=custom" \
  && cd / && rm -rf /tmp/osx-smoke

# Set git config if provided
RUN if [ -n "${GIT_USER_NAME}" ]; then git config --global user.name "${GIT_USER_NAME}"; fi && \
    if [ -n "${GIT_USER_EMAIL}" ]; then git config --global user.email "${GIT_USER_EMAIL}"; fi
