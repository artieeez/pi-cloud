#!/usr/bin/env bash
# herdr-sha-sync.sh — keep ARG HERDR_SHA256 in sync with ARG HERDR_VERSION.
#
# Renovate bumps HERDR_VERSION on its PRs but cannot compute a release-asset
# hash. This script (invoked by .github/workflows/herdr-sha-sync.yaml on PRs
# touching Dockerfile) downloads the published herdr-linux-aarch64 asset for
# the PR head's HERDR_VERSION and rewrites HERDR_SHA256 to its sha256.
#
# Idempotent: exits 0 with no file change when the sha already matches, so a
# non-herdr Dockerfile PR or the helper's own push is a clean no-op. Fails
# loudly (exit 1, no edit) if the asset cannot be fetched — e.g. an unknown
# version or a renamed release asset.
#
# The script only edits the file; committing/pushing happens in the workflow
# (needs GITHUB_TOKEN). DRY_RUN=1 skips nothing extra — set it to keep the edit
# for inspection in tests.
set -euo pipefail

DOCKERFILE="${DOCKERFILE:-Dockerfile}"

version="$(sed -n 's/^ARG HERDR_VERSION=//p' "${DOCKERFILE}")"
declared_sha="$(sed -n 's/^ARG HERDR_SHA256=//p' "${DOCKERFILE}")"
if [ -z "${version}" ] || [ -z "${declared_sha}" ]; then
  echo "herdr-sha-sync: ARG HERDR_VERSION/HERDR_SHA256 not both present in ${DOCKERFILE}; nothing to do"
  exit 0
fi

url="https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-aarch64"
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
if ! curl -fsSL "${url}" -o "${tmp}"; then
  echo "herdr-sha-sync: failed to download ${url} (unpublished version or renamed asset?)" >&2
  exit 1
fi
computed_sha="$(sha256sum "${tmp}" | awk '{print $1}')"

if [ "${computed_sha}" = "${declared_sha}" ]; then
  echo "herdr-sha-sync: HERDR_SHA256 already matches v${version} — nothing to do"
  exit 0
fi

sed -i "s/^ARG HERDR_SHA256=.*/ARG HERDR_SHA256=${computed_sha}/" "${DOCKERFILE}"
echo "herdr-sha-sync: updated HERDR_SHA256 to ${computed_sha} for v${version}"
