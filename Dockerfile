# syntax=docker/dockerfile:1
# check=error=true

# pi.dev cloud box — thin APP image over the stable base.
#
# The heavy, rarely-changing content (node + OS deps, mise + Ruby) lives
# in docker/base.Dockerfile (pi-cloud-base). This image carries only the
# per-commit bits: pi agent version, kubectl, gh, playwright-cli, and container
# assets — so every push builds a small delta instead of re-baking a ~1.1GB
# toolchain.
#
# Build args: BASE_IMAGE defaults to the local base image name so
#   docker build -f docker/base.Dockerfile -t pi-cloud-base .
#   docker build -t pi-cloud .
# just works; CI passes the registry path + pinned tag (build-push-ocir.yaml).

ARG BASE_IMAGE=pi-cloud-base
ARG BASE_TAG=latest

FROM ${BASE_IMAGE}:${BASE_TAG}

ARG PI_VERSION=0.85.1
ARG KUBECTL_VERSION=1.36.4
ARG HERDR_VERSION=0.8.2
# herdr-linux-aarch64 sha256 (release assets carry no checksum sidecar; pinned here)
ARG HERDR_SHA256=f55610658e1c2e0d2aaef730b4b2ab885f7f8ba00285ab372bfb14f2e3d5b40d
ARG GH_VERSION=2.100.0
# @playwright/cli (browser automation CLI for pi UAT); its chromium headless
# shell is baked at image build — see the install-browser RUN below.
ARG PLAYWRIGHT_CLI_VERSION=0.1.19

# pi coding agent (pinned; --ignore-scripts per upstream docs)
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

# kubectl, pinned to the cluster server version (check: kubectl version -o json)
# sha256 sidecar = https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/arm64/kubectl.sha256
RUN cd /tmp && \
    curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/arm64/kubectl" && \
    curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/arm64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - && \
    install -m 0755 kubectl /usr/local/bin/kubectl && \
    rm -f kubectl kubectl.sha256

# herdr (agent multiplexer; pinned, checksum-verified — no upstream sidecar)
RUN cd /tmp && \
    curl -fsSLO "https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-aarch64" && \
    echo "${HERDR_SHA256}  herdr-linux-aarch64" | sha256sum -c - && \
    install -m 0755 herdr-linux-aarch64 /usr/local/bin/herdr && \
    rm -f herdr-linux-aarch64

# gh (GitHub CLI, pinned) — verified against the release checksums file, which
# carries one line per asset; grep the arm64 tarball line and sha256sum -c it.
RUN cd /tmp && \
    curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_arm64.tar.gz" && \
    curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" && \
    grep "gh_${GH_VERSION}_linux_arm64.tar.gz\$" "gh_${GH_VERSION}_checksums.txt" | sha256sum -c - && \
    tar -xzf "gh_${GH_VERSION}_linux_arm64.tar.gz" && \
    install -m 0755 "gh_${GH_VERSION}_linux_arm64/bin/gh" /usr/local/bin/gh && \
    rm -rf "gh_${GH_VERSION}_linux_arm64" "gh_${GH_VERSION}_linux_arm64.tar.gz" "gh_${GH_VERSION}_checksums.txt"

# playwright-cli (pinned, npm) — browser automation for pi UAT on the box.
# The npm package is small; the chromium headless shell (~110MB download) is
# the heavy part. Browsers bake under /opt, NOT the default ~/.cache under
# /root: /root is the PVC mount and shadows image content at runtime, so a
# browser baked there would vanish on first boot. PLAYWRIGHT_BROWSERS_PATH is
# exported here (entrypoint/herdr inherit it) and re-exported in profile.d for
# sshd sessions, which reset the container env.
#
# Headless shell only, via PLAYWRIGHT_MCP_CONFIG: with no config the CLI
# forces channel 'chrome' (system Google Chrome at /opt/google/chrome/chrome),
# and `--browser chromium` forces channel 'chrome-for-testing' (the full
# chromium build) — neither is baked here. The global config shipped below
# pins browserName=chromium with NO channel, so playwright launches its
# chromium headless shell build — the one baked by --only-shell — and the box
# has no display anyway. chromiumSandbox:false because the container runs as
# root. Validated on the box: `playwright-cli open <url>` then snapshot/close
# work end-to-end with only chromium_headless_shell-1243 present.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PLAYWRIGHT_MCP_CONFIG=/opt/pi-cloud-playwright-cli.config.json
COPY container/playwright-cli.config.json /opt/pi-cloud-playwright-cli.config.json
RUN npm install -g "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" && \
    playwright-cli install-browser chromium --only-shell --with-deps && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# In-cluster kubeconfig (ServiceAccount-based, see docs). Baked OUTSIDE /root:
# /root is the PVC mount at runtime and shadows image content — the entrypoint
# seeds /root/.kube/config from here when absent.
COPY container/kubeconfig.yaml /opt/pi-cloud-kubeconfig.yaml

# Container assets
COPY container/sshd_config /etc/ssh/sshd_config.d/10-pi-cloud.conf
COPY container/profile.d/pi-cloud.sh /etc/profile.d/pi-cloud.sh
COPY container/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY container/sync-configs.sh /usr/local/bin/sync-configs.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sync-configs.sh && \
    ln -s /usr/local/bin/entrypoint.sh /entrypoint

# Root with key-only SSH (personal dev box; never expose publicly without a
# non-root user + hardening).
USER root
# ~/artieeez mirrors the Mac ~/artieeez layout (see docs/BOOT-SYNC.md).
WORKDIR /root/artieeez

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]