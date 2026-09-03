# syntax=docker/dockerfile:1
# check=error=true

# pi.dev cloud box — thin APP image over the stable base.
#
# The heavy, rarely-changing content (node + OS deps, tmux, mise + Ruby) lives
# in docker/base.Dockerfile (pi-cloud-base). This image carries only the
# per-commit bits: pi agent version, kubectl, and container assets — so every
# push builds a small delta instead of re-baking a ~1.1GB toolchain.
#
# Build args: BASE_IMAGE defaults to the local base image name so
#   docker build -f docker/base.Dockerfile -t pi-cloud-base .
#   docker build -t pi-cloud .
# just works; CI passes the registry path + pinned tag (build-push-ocir.yaml).

ARG BASE_IMAGE=pi-cloud-base
ARG BASE_TAG=latest

FROM ${BASE_IMAGE}:${BASE_TAG}

ARG PI_VERSION=0.84.4
ARG KUBECTL_VERSION=1.36.4

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

# In-cluster kubeconfig (ServiceAccount-based, see docs)
COPY container/kubeconfig.yaml /root/.kube/config

# Container assets
COPY container/sshd_config /etc/ssh/sshd_config.d/10-pi-cloud.conf
COPY container/profile.d/pi-cloud.sh /etc/profile.d/pi-cloud.sh
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