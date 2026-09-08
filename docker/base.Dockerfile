# syntax=docker/dockerfile:1
# check=error=true

# pi.dev cloud box — stable BASE image.
#
# Deliberately split from the app image (repo-root Dockerfile): everything here
# is slow or big and changes rarely (node base, OS deps, mise + Ruby), so
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
ARG NEOVIM_VERSION=0.12.5

# ---------------------------------------------------------------------------
# Build stage: mise-managed Ruby (matches the local dev workflow; .ruby-version
# aware).
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS build

ARG RUBY_VERSION

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential autoconf automake bison pkg-config \
      curl git ca-certificates \
      libssl-dev libyaml-dev zlib1g-dev libreadline-dev \
      libffi-dev libgmp-dev libvips-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

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

# ARGs declared before the first FROM are not visible inside this stage's RUN
# commands — re-declare the ones used here.
ARG NEOVIM_VERSION
ARG RUBY_VERSION

# Runtime deps: git (pi tool), ripgrep (pi grep), sshd (entry point), sqlite3 +
# libvips (home repo specs/assets), ruby runtime libs, jq (secret assembly), bash.
# libstdc++6: runtime lib for the official neovim tarball installed below.
#
# build-essential: C toolchain (~230MB: gcc/g++/make/libc6-dev/binutils) for
# compiling native Ruby gems AT RUNTIME on the box (e.g. msgpack via bootsnap
# in `home` bundle installs). The build stage above installs the same tools to
# compile ruby, but multi-stage COPY only carries binaries out of that
# stage — nothing from it reaches this image, so without this line a fresh box
# has no cc/make and every native-gem `bundle install` fails at extconf.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      bash ca-certificates curl git ripgrep \
      openssh-server \
      sqlite3 libvips42 jq \
      libstdc++6 \
      libyaml-0-2 libssl3 zlib1g libffi8 libgmp10 libreadline8 \
      build-essential && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives && \
    mkdir -p /run/sshd && \
    # Image-baked ssh host keys would rotate on every rebuild (postinst ssh-keygen -A).
    # sshd must use ONLY the sealed keys the entrypoint materializes at /root/.ssh.
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

# mise/ruby from build stage (installs+shims, global config)
COPY --from=build /root/.local /opt/mise-root/local
COPY --from=build /opt/mise /opt/mise
COPY --from=build /root/.config/mise /opt/mise-root/config
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/opt/mise-root/config \
    PATH="/opt/mise-root/local/bin:/opt/mise/shims:${PATH}"

# The build stage's `mise use` wrote shims as symlinks to its build-time binary
# path (/root/.local/bin/mise), which this stage relocates to
# /opt/mise-root/local/bin/mise — leaving every shim dangling. Regenerate them
# against the final mise location so ruby/gem/bundle resolve in any shell, and
# fail the build if the ruby shim is still not executable.
RUN rm -f /opt/mise/shims/* && \
    PATH="/opt/mise-root/local/bin:${PATH}" \
    MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/opt/mise-root/config \
    MISE_YES=1 \
    mise use -g "ruby@${RUBY_VERSION}" && \
    test -x /opt/mise/shims/ruby && \
    test "$(readlink /opt/mise/shims/ruby)" = "/opt/mise-root/local/bin/mise"

# neovim — official prebuilt arm64 build (bookworm's apt neovim is 0.7.2, far too
# old for a modern editor). Pinned by NEOVIM_VERSION; tag URL is immutable.
# NEOVIM_VERSION re-declared above (global ARGs are not visible in RUN).
RUN curl -fsSL "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-arm64.tar.gz" \
      -o /tmp/nvim.tar.gz && \
    tar -C /opt -xzf /tmp/nvim.tar.gz && \
    mv /opt/nvim-linux-arm64 /opt/nvim && \
    rm -f /tmp/nvim.tar.gz
ENV PATH="/opt/nvim/bin:${PATH}"