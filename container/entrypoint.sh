#!/usr/bin/env bash
# pi-cloud entrypoint: assemble sealed secrets into ~/.ssh and ~/.pi/agent,
# start sshd (foreground, logs to stderr), pre-create the `pi` tmux session.
set -euo pipefail

HOME_DIR=/root
SSH_DIR=${HOME_DIR}/.ssh
PI_DIR=${HOME_DIR}/.pi/agent
SECRETS_DIR=/secrets

log() { echo "[entrypoint] $*"; }
die() { log "FATAL: $*"; exit 1; }

mkdir -p "${SSH_DIR}" "${PI_DIR}"
# /root is the NFS PVC mount root (often 777); sshd StrictModes refuses key
# auth when the home dir is group/world-writable.
chmod 700 "${HOME_DIR}"
chmod 700 "${SSH_DIR}"

# ---------------------------------------------------------------------------
# SSH host keys — sealed for stability across restarts (phone known_hosts).
# Fallback: generate into the persistent home once.
# ---------------------------------------------------------------------------
if [ -f "${SECRETS_DIR}/ssh/ssh_host_ed25519_key" ]; then
  cp "${SECRETS_DIR}/ssh/ssh_host_ed25519_key" "${SSH_DIR}/ssh_host_ed25519_key"
  cp "${SECRETS_DIR}/ssh/ssh_host_ed25519_key.pub" "${SSH_DIR}/ssh_host_ed25519_key.pub" 2>/dev/null || true
else
  [ -f "${SSH_DIR}/ssh_host_ed25519_key" ] || ssh-keygen -q -t ed25519 -N "" -f "${SSH_DIR}/ssh_host_ed25519_key"
fi
chmod 600 "${SSH_DIR}/ssh_host_ed25519_key"

# ---------------------------------------------------------------------------
# Authorized keys — sealed. Empty file == no way in; keep the pod alive so
# kubectl exec can still rescue, but say so loudly.
# ---------------------------------------------------------------------------
if [ -f "${SECRETS_DIR}/ssh/authorized_keys" ]; then
  cp "${SECRETS_DIR}/ssh/authorized_keys" "${SSH_DIR}/authorized_keys"
else
  log "WARNING: no sealed authorized_keys — sshd will accept nobody."
  : > "${SSH_DIR}/authorized_keys"
fi
chmod 600 "${SSH_DIR}/authorized_keys"

# ---------------------------------------------------------------------------
# Git credentials (deploy key) + known_hosts
# ---------------------------------------------------------------------------
if [ -d "${SECRETS_DIR}/git" ]; then
  cp "${SECRETS_DIR}/git/id_ed25519" "${SSH_DIR}/id_ed25519" 2>/dev/null || true
  cp "${SECRETS_DIR}/git/id_ed25519.pub" "${SSH_DIR}/id_ed25519.pub" 2>/dev/null || true
  cp "${SECRETS_DIR}/git/known_hosts" "${SSH_DIR}/known_hosts" 2>/dev/null || true
  chmod 600 "${SSH_DIR}/id_ed25519"
  chmod 644 "${SSH_DIR}/id_ed25519.pub" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# pi agent config: default settings (image-baked templates) + sealed auth.
# Never overwrite user tweaks already persisted on the volume.
# ---------------------------------------------------------------------------
[ -f "${PI_DIR}/settings.json" ] || cp /opt/pi-agent/settings.json "${PI_DIR}/settings.json"
[ -f "${PI_DIR}/AGENTS.md" ] || cp /opt/pi-agent/AGENTS.md "${PI_DIR}/AGENTS.md"

if [ -f "${SECRETS_DIR}/pi/auth.json" ]; then
  if [ -f "${PI_DIR}/auth.json" ]; then
    tmp=$(mktemp)
    jq -s '.[0] * .[1]' "${PI_DIR}/auth.json" "${SECRETS_DIR}/pi/auth.json" > "${tmp}"
    mv "${tmp}" "${PI_DIR}/auth.json"
  else
    cp "${SECRETS_DIR}/pi/auth.json" "${PI_DIR}/auth.json"
  fi
  chmod 600 "${PI_DIR}/auth.json"
fi

# ---------------------------------------------------------------------------
# Workspace: repos live on the PVC under /workspace.
# ---------------------------------------------------------------------------
mkdir -p /workspace

# ---------------------------------------------------------------------------
# tmux: pre-create the `pi` session (wide) so `tmux attach -t pi` works on SSH.
# Auto-start pi inside it when AUTO_PI=1.
# ---------------------------------------------------------------------------
if ! tmux has-session -t pi 2>/dev/null; then
  if [ "${AUTO_PI:-0}" = "1" ]; then
    tmux new-session -d -s pi -x 240 -y 60 "pi; exec bash"
  else
    tmux new-session -d -s pi -x 240 -y 60 -n shell
  fi
  log "tmux session 'pi' created (AUTO_PI=${AUTO_PI:-0})"
fi

log "starting sshd (key-only auth)"
exec /usr/sbin/sshd -D -e