# ==========================================================================================
# Stage: base
# Shared tooling. Used by CI directly (target=base) and as the foundation for the dev stage.
# ==========================================================================================
FROM debian:bookworm-slim AS base

ARG HELM_VERSION=3.18.0
ARG YAMLFMT_VERSION=0.21.0
ARG JUST_VERSION=1.51.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    python3 \
    python3-venv \
    python3-pip \
  && rm -rf /var/lib/apt/lists/*

# helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
  | tar -xz -C /tmp linux-amd64/helm \
  && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
  && rm -rf /tmp/linux-amd64 \
  && helm version --short

# yamlfmt — must match the rev pinned in .pre-commit-config.yaml.
RUN curl -fsSL "https://github.com/google/yamlfmt/releases/download/v${YAMLFMT_VERSION}/yamlfmt_${YAMLFMT_VERSION}_Linux_x86_64.tar.gz" \
  | tar -xz -C /usr/local/bin yamlfmt \
  && yamlfmt -version

# just
RUN curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  | tar -xz -C /usr/local/bin just \
  && just --version

# =============================================================================
# Stage: dev
# Non-root user for the devcontainer. Used by humans or agents for development.
# =============================================================================
FROM base AS dev

# Install tools needed for development
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    yq \
    jq \
    vim \
    # Required for init-firewall.sh
    sudo \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    # jq \
    # curl \
    aggregate \
  && rm -rf /var/lib/apt/lists/*

# ARG GH_VERSION=2.65.0
# RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
#   | tar -xz -C /usr/local/bin --strip-components=2 "gh_${GH_VERSION}_linux_amd64/bin/gh" \
#  && gh --version

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN groupadd --gid ${USER_GID} ${USERNAME} \
  && useradd  --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
  && mkdir -p /home/${USERNAME}/.claude \
  && chown -R ${USER_UID}:${USER_GID} /home/${USERNAME}/.claude

# RUN mkdir -p /home/${USERNAME}/.pi \
#   && chown -R ${USER_UID}:${USER_GID} /home/${USERNAME}/.pi

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/sbin/
# The script is owned by root and read-only.
# The dev user can run it via sudo, but not edit it to disable the firewall.
RUN chown root:root /usr/local/sbin/init-firewall.sh && \
  chmod 0555 /usr/local/sbin/init-firewall.sh && \
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/sbin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

USER ${USERNAME}
# The dev container runtime sets WORKDIR to /workspaces/<repo-name> anyways.
# WORKDIR /workspace

# TODO
# Enforce organisation policy: this is the only way to enforce policy that contributors can't override by editing.
# See https://code.claude.com/docs/en/devcontainer#enforce-organization-policy
# RUN mkdir -p /etc/claude-code
# COPY managed-settings.json /etc/claude-code/managed-settings.json
