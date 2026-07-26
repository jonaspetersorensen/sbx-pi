FROM docker/sandbox-templates:shell

ARG NODEJS_MAJOR_VERSION=24
ARG PI_VERSION=0.82.1

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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER agent

RUN mkdir -p "$HOME/.npm-global" \
  && npm config set prefix "$HOME/.npm-global" \
  && printf '\n# npm user-global prefix\nexport PATH="$HOME/.npm-global/bin:$PATH"\n' >> ~/.bashrc \
  && npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${PI_VERSION}

RUN printf '\n# Auto-launch pi coding agent in interactive shells\nif [[ $- == *i* ]] && command -v pi &> /dev/null; then\n    exec pi\nfi\n' >> ~/.bashrc
