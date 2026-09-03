# syntax=docker/dockerfile:1
# check=error=true

# pi.dev cloud box — stable BASE image.
#
# Deliberately split from the app image (repo-root Dockerfile): everything here
# is slow or big and changes rarely (node base, OS deps, tmux, mise + Ruby), so
# it is built and pushed only when these files/versions change. The app image
# `FROM`s this base, so per-commit builds are small deltas and the cluster node
# stores the base layer set only once (cri-o layer dedup).
#
# Triggers: push touching docker/base.Dockerfile or the base workflow, or
# workflow_dispatch (see .github/workflows/build-base.yaml).
#
# Local build:
#   docker build -f docker/base.Dockerfile -t pi-cloud-base .

ARG NODE_VERSION=24
ARG RUBY_VERSION=4.0.5
ARG TMUX_VERSION=3.7c
ARG NEOVIM_VERSION=0.12.5

# ---------------------------------------------------------------------------
# Build stage: tmux 3.7c (bookworm ships 3.3a; pi needs >= 3.5 for csi-u keys)
# and mise-managed Ruby (matches the local dev workflow; .ruby-version aware).
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS build

ARG RUBY_VERSION
ARG TMUX_VERSION

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential autoconf automake bison pkg-config \
      curl git ca-certificates \
      libevent-dev libncurses-dev \
      libssl-dev libyaml-dev zlib1g-dev libreadline-dev \
      libffi-dev libgmp-dev libvips-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# tmux from source (release tarball, no vendored deps needed beyond libevent/ncurses)
RUN curl -fsSL "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz" -o /tmp/tmux.tar.gz && \
    tar -C /tmp -xzf /tmp/tmux.tar.gz && \
    cd /tmp/tmux-${TMUX_VERSION} && \
    ./configure --prefix=/opt/tmux >/dev/null && \
    make -j"$(nproc)" >/dev/null && \
    make install >/dev/null && \
    rm -rf /tmp/tmux*

# mise (version manager) + Ruby runtime
# - installs ruby 4.0.5 into /opt/mise (MISE_DATA_DIR)
# - writes global config (ruby tool) to ~/.config/mise/config.toml
# - creates shims under /opt/mise/shims so `ruby` resolves via .ruby-version
ENV PATH="/root/.local/bin:${PATH}" \
    MISE_DATA_DIR=/opt/mise \
    MISE_YES=1

RUN curl -fsSL https://mise.jdx.dev/install.sh | sh && \
    mise use -g "ruby@${RUBY_VERSION}"

# ---------------------------------------------------------------------------
# Final base
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim

# Runtime deps: git (pi tool), ripgrep (pi grep), sshd (entry point), sqlite3 +
# libvips (home repo specs/assets), ruby runtime libs, jq (secret assembly), bash.
# libstdc++6: runtime lib for the official neovim tarball installed below.
# libevent-2.1-7/libncurses6: runtime libs for the tmux built in the build stage.
# Debian merges libevent into a single libevent-2.1.so.7;  tmux links the classic
# libevent_core/libevent_extra split sonames -> provide compat symlinks.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      bash ca-certificates curl git ripgrep \
      openssh-server \
      sqlite3 libvips42 jq \
      libstdc++6 \
      libyaml-0-2 libssl3 zlib1g libffi8 libgmp10 libreadline8 \
      libevent-2.1-7 libncurses6 && \
    ln -s libevent-2.1.so.7.0.1 /usr/lib/$(uname -m)-linux-gnu/libevent_core-2.1.so.7 && \
    ln -s libevent-2.1.so.7.0.1 /usr/lib/$(uname -m)-linux-gnu/libevent_extra-2.1.so.7 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives && \
    mkdir -p /run/sshd && \
    # Image-baked ssh host keys would rotate on every rebuild (postinst ssh-keygen -A).
    # sshd must use ONLY the sealed keys the entrypoint materializes at /root/.ssh.
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

# tmux + mise/ruby from build stage (binary, installs+shims, global config)
COPY --from=build /opt/tmux /opt/tmux
ENV PATH="/opt/tmux/bin:${PATH}"
COPY --from=build /root/.local /opt/mise-root/local
COPY --from=build /opt/mise /opt/mise
COPY --from=build /root/.config/mise /opt/mise-root/config
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/opt/mise-root/config \
    PATH="/opt/mise-root/local/bin:/opt/mise/shims:${PATH}"

# neovim — official prebuilt arm64 build (bookworm's apt neovim is 0.7.2, far too
# old for a modern editor). Pinned by NEOVIM_VERSION; tag URL is immutable.
RUN curl -fsSL "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-arm64.tar.gz" \
      -o /tmp/nvim.tar.gz && \
    tar -C /opt -xzf /tmp/nvim.tar.gz && \
    mv /opt/nvim-linux-arm64 /opt/nvim && \
    rm -f /tmp/nvim.tar.gz
ENV PATH="/opt/nvim/bin:${PATH}"