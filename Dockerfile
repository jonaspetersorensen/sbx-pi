# System tools
# - nodejs: to build pi agent 
# - Research: 
#   - pandoc: a universal document converter for moving between markup and office formats. 
#   - html2text: converts HTML into plain tex
#   - lynx: a text-based web browser for terminals

FROM docker/sandbox-templates:shell-docker

ARG NODEJS_MAJOR_VERSION=24
ARG PI_VERSION=0.83.0
ARG GITHUB_GH_VERSION=2.97.0
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

# Set git config if provided
RUN if [ -n "${GIT_USER_NAME}" ]; then git config --global user.name "${GIT_USER_NAME}"; fi && \
    if [ -n "${GIT_USER_EMAIL}" ]; then git config --global user.email "${GIT_USER_EMAIL}"; fi
