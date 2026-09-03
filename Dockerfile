# syntax=docker/dockerfile:1
# check=error=true

# pi.dev cloud box: pi coding agent + Ruby (mise) + tmux + sshd.
# Runs on the artr OKE cluster (linux/arm64). SSH (key-only) is the only entry point;
# attach to the `pi` tmux session after logging in.

ARG NODE_VERSION=24
ARG RUBY_VERSION=4.0.5
ARG PI_VERSION=0.84.4
ARG TMUX_VERSION=3.7c

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
# Final image
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim

ARG PI_VERSION

# Runtime deps: git (pi tool), ripgrep (pi grep), sshd (entry point), sqlite3 +
# libvips (home repo specs/assets), ruby runtime libs, jq (secret assembly), bash.
# libevent-2.1-7/libncurses6: runtime libs for the tmux built in the build stage.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      bash ca-certificates curl git ripgrep \
      openssh-server \
      sqlite3 libvips42 jq \
      libyaml-0-2 libssl3 zlib1g libffi8 libgmp10 libreadline8 \
      libevent-2.1-7 libncurses6 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives && \
    mkdir -p /run/sshd

# pi coding agent (pinned; --ignore-scripts per upstream docs)
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

# tmux + mise/ruby from build stage (binary, installs+shims, global config)
COPY --from=build /opt/tmux /opt/tmux
ENV PATH="/opt/tmux/bin:${PATH}"
COPY --from=build /root/.local /opt/mise-root/local
COPY --from=build /opt/mise /opt/mise
COPY --from=build /root/.config/mise /opt/mise-root/config
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/opt/mise-root/config \
    PATH="/opt/mise-root/local/bin:/opt/mise/shims:${PATH}"

# Container assets
COPY container/sshd_config /etc/ssh/sshd_config.d/10-pi-cloud.conf
COPY container/tmux.conf /root/.tmux.conf
COPY container/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY container/pi-agent/ /opt/pi-agent/
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    ln -s /usr/local/bin/entrypoint.sh /entrypoint

# Root with key-only SSH (personal dev box; never expose publicly without a
# non-root user + hardening).
USER root
WORKDIR /workspace

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]