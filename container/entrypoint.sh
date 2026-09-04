#!/usr/bin/env bash
# pi-cloud entrypoint: assemble sealed secrets into ~/.ssh and ~/.pi/agent,
# run the boot sync, start the herdr server (agent host), then sshd.
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
# /root is the PVC mount: image files baked under /root are shadowed at
# runtime, so seed the PVC home from /opt copies when missing (kubeconfig).
# ---------------------------------------------------------------------------
if [ -f /opt/pi-cloud-kubeconfig.yaml ]; then
  mkdir -p "${HOME_DIR}/.kube"
  if [ ! -f "${HOME_DIR}/.kube/config" ]; then
    cp /opt/pi-cloud-kubeconfig.yaml "${HOME_DIR}/.kube/config"
    chmod 600 "${HOME_DIR}/.kube/config"
    log "seeded in-cluster kubeconfig"
  fi
fi

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
# Boot provisioning: sync pi-config -> ~/.pi/agent, dotagents -> ~/.agents and
# the work repos into ~/artieeez (docs/BOOT-SYNC.md). Non-fatal: on failure the
# box still boots on sealed auth + pi built-in defaults.
# ---------------------------------------------------------------------------
/usr/local/bin/sync-configs.sh || log "boot sync failed (continuing)"

# ---------------------------------------------------------------------------
# pi model auth: overlay the sealed auth.json onto ~/.pi/agent/auth.json. The
# file is gitignored in pi-config so the boot sync never touches it; this merge
# deliberately runs AFTER sync.
# ---------------------------------------------------------------------------
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
# Repos live on the PVC under ~/artieeez (mirrors the Mac layout); guarantee it
# exists so the boot herdr pane can be rooted at ~/artieeez.
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/artieeez"

# ---------------------------------------------------------------------------
# herdr: terminal workspace manager hosting pi agents. Start the headless
# server at boot so agents survive SSH disconnects and inherit the container
# env (PI_CLOUD, DEEPINFRA_API_KEY). Attach later with `herdr` over ssh, or
# `herdr --remote pi-cloud` from a device that has the herdr CLI.
# ---------------------------------------------------------------------------
HDR_SOCK="${HOME_DIR}/.config/herdr/herdr.sock"
# The whole herdr section runs with errexit/pipefail OFF: a herdr CLI or jq
# hiccup during startup must never stop sshd from coming up.
set +e
if [ ! -S "${HDR_SOCK}" ]; then
  ( setsid herdr server >/var/log/herdr-server.log 2>&1 < /dev/null & )
fi
ready=0
for _ in $(seq 1 30); do
  if [ -S "${HDR_SOCK}" ]; then ready=1; break; fi
  sleep 1
done
if [ "${ready}" != "1" ]; then
  log "WARNING: herdr server not ready (see /var/log/herdr-server.log)"
else
  log "herdr server ready"
  sleep 2   # let the server finish restoring any persisted session state
  # Shell pane rooted at ~/artieeez for the user. herdr restores topology from
  # persisted state across pod restarts, so only create the pane when none at
  # ~/artieeez exists yet (no stacking panes on every boot).
  NEW_PANE="$(herdr pane list 2>/dev/null | jq -r '.result.panes[] | select(.cwd == "'"${HOME_DIR}"'/artieeez") | .pane_id' 2>/dev/null | head -1)"
  ROOT_PANE=""
  if [ -z "${NEW_PANE}" ]; then
    ROOT_PANE="$(herdr pane list 2>/dev/null | jq -r '.result.panes[] | select(.cwd == "/root") | .pane_id' 2>/dev/null | head -1)"
    if [ -n "${ROOT_PANE}" ]; then
      NEW_PANE="$(herdr pane split --pane "${ROOT_PANE}" --direction right --cwd "${HOME_DIR}/artieeez" 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null)"
    fi
  fi
  [ -n "${NEW_PANE}" ] && log "herdr shell pane ready at ~/artieeez (${NEW_PANE})"
  if [ "${AUTO_PI:-0}" = "1" ]; then
    TARGET="${NEW_PANE:-${ROOT_PANE}}"
    if [ -n "${TARGET}" ] && herdr agent start pi --kind pi --pane "${TARGET}" >/dev/null 2>&1; then
      log "pi agent started in herdr pane (AUTO_PI=1)"
    else
      log "pi agent start failed (run 'herdr' on the box to start it manually)"
    fi
  fi
fi
set -e

log "starting sshd (key-only auth)"
exec /usr/sbin/sshd -D -e