#!/usr/bin/env bash
# sync-configs.sh — boot-time provisioning for the pi-cloud box.
#
# Runs from the container entrypoint BEFORE sshd starts (and re-runnable by
# hand). Every step is failure-tolerant: a git/network failure logs and moves
# on — the box still boots on sealed auth + built-in defaults.
#
# Groups (see docs/BOOT-SYNC.md):
#   FORCED   pi-config   -> /root/.pi/agent   (reset to origin/main; ignored
#            dotagents   -> /root/.agents      runtime files survive: auth.json,
#            nvim-config -> /root/.config/nvim  sessions/, npm/, trust.json, ...)
#   NON-FORCED artr-gitops pi-cloud oracle-cluster home home-knowledge
#            -> /root/artieeez/<name>        clone, else fetch + ff-only pull
#                                             (local box work is never clobbered)
set -uo pipefail

HOME_DIR=/root
SSH_DIR=${HOME_DIR}/.ssh
PI_DIR=${HOME_DIR}/.pi/agent
AGENTS_DIR=${HOME_DIR}/.agents
REPOS_ROOT=${HOME_DIR}/artieeez
WORK_REPOS=(artr-gitops pi-cloud oracle-cluster home home-knowledge)
ORG=git@github.com:artieeez

log() { echo "[sync] $*"; }

# Nothing can clone without the deploy key (+ known_hosts).
if [ ! -f "${SSH_DIR}/id_ed25519" ] || [ ! -f "${SSH_DIR}/known_hosts" ]; then
  log "deploy key missing — skipping all repo sync (seal /secrets/git first)"
  exit 0
fi
export GIT_SSH_COMMAND="ssh -i ${SSH_DIR}/id_ed25519 -o IdentitiesOnly=yes"

# ---------------------------------------------------------------------------
# FORCED: config repos — repo is the truth, local tracked edits are discarded.
# Order matters: checkout materializes .gitignore FIRST, then `git clean -fd`
# (ignored-aware) removes strays without touching auth.json/sessions/npm/...
# ---------------------------------------------------------------------------
sync_forced() {
  local dir=$1 url=$2
  mkdir -p "${dir}"
  if ( cd "${dir}" \
      && git init -q 2>/dev/null || true \
      && git remote remove origin 2>/dev/null || true \
      && git remote add origin "${url}" \
      && timeout 90 git fetch -q origin \
      && git checkout -fq -B main origin/main \
      && git clean -fdq ); then
    log "synced ${url} -> ${dir}"
    return 0
  fi
  log "FAILED to sync ${url} -> ${dir}"
  return 1
}

# pi-config (also npm-install extension deps when it lands)
if sync_forced "${PI_DIR}" "${ORG}/pi-config.git"; then
  if ( cd "${PI_DIR}" && timeout 300 npm install --no-audit --no-fund >/dev/null 2>&1 ); then
    log "npm install ok in ${PI_DIR}"
  else
    log "npm install failed in ${PI_DIR} (extensions may not compile)"
  fi
fi

# dotagents (skills -> ~/.agents)
sync_forced "${AGENTS_DIR}" "${ORG}/dotagents.git" || true

# nvim-config (LazyVim editor config -> ~/.config/nvim; nvim runtime state
# lives in ~/.local/{share,state}/nvim on the PVC and is untouched by sync)
sync_forced "${HOME_DIR}/.config/nvim" "${ORG}/nvim-config.git" || true

# ---------------------------------------------------------------------------
# NON-FORCED: work repos under /root/artieeez (mirrors Mac ~/artieeez).
# ---------------------------------------------------------------------------
mkdir -p "${REPOS_ROOT}"
for name in "${WORK_REPOS[@]}"; do
  dir="${REPOS_ROOT}/${name}"
  if [ ! -d "${dir}/.git" ]; then
    if timeout 90 git clone -q "${ORG}/${name}.git" "${dir}" 2>/dev/null; then
      log "cloned ${name} -> ${dir}"
    else
      log "clone failed: ${name}"
    fi
  elif ( cd "${dir}" && timeout 90 git pull -q --ff-only 2>/dev/null ); then
    log "updated ${name}"
  else
    log "left ${name} as-is (uncommitted work or diverged — not clobbering)"
  fi
done

log "done"
