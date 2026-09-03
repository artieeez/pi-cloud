# Troubleshooting

Every issue below was hit and fixed while bringing the box up live on the artr
cluster. Symptom → cause → fix, so the next incident is minutes, not hours.

## 1. Pod crash-loops: `tmux: error while loading shared libraries: libevent_core-2.1.so.7`

**Cause:** the final image shipped only runtime package names without the tmux
runtime libs, and Debian (bookworm) *merges* libevent 2.1 into a single
`libevent-2.1.so.7` while tmux links the classic split sonames
`libevent_core-2.1.so.7` / `libevent_extra-2.1.so.7`.

**Fix (docker/base.Dockerfile, final stage):**

```dockerfile
RUN apt-get install -y libevent-2.1-7 libncurses6 && \
    ln -s libevent-2.1.so.7.0.1 /usr/lib/$(uname -m)-linux-gnu/libevent_core-2.1.so.7 && \
    ln -s libevent-2.1.so.7.0.1 /usr/lib/$(uname -m)-linux-gnu/libevent_extra-2.1.so.7
```

Verify inside the image: `ldd /opt/tmux/bin/tmux | grep "not found"` → empty.

## 0b. Host key changed on every image rebuild (`REMOTE HOST IDENTIFICATION HAS CHANGED`)

**Cause:** Debian's openssh-server postinst runs `ssh-keygen -A` at image build,
baking fresh host keys into `/etc/ssh/ssh_host_*`. sshd used those (default
config), so every image rollout rotated the host key — even though sealed keys
were sitting in `/root/.ssh` untouched.

**Diagnose:** fingerprint sshd actually serves vs the sealed key:

```bash
kubectl exec <pod> -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
kubectl exec <pod> -- ssh-keygen -lf /root/.ssh/ssh_host_ed25519_key.pub
```

**Fix:** docker/base.Dockerfile removes the baked keys (`rm -f /etc/ssh/ssh_host_*_key*`)
and `container/sshd_config` sets `HostKey /root/.ssh/ssh_host_ed25519_key` (the
entrypoint materializes the sealed key at boot). After the fix, clear `pi`
entries from client `known_hosts` once and re-add with `accept-new`:

```bash
ssh-keygen -R pi -R pi.tailc16433.ts.net -R 100.118.244.0
```

## 2. sshd exits at startup: `Subsystem 'sftp' already defined`

**Cause:** Debian's `/etc/ssh/sshd_config` already defines `Subsystem sftp`;
a second definition (from a `sshd_config.d` drop-in) is a **fatal** config
error and sshd refuses to start.

**Fix:** don't declare `Subsystem` in `container/sshd_config` — the built-in one
wins. Keep drop-ins to overrides (Port, auth, keep-alive, hardening).

## 3. SSH auth refused: `Authentication refused: bad ownership or modes for directory /root`

**Cause:** `/root` is the mount root of the NFS PVC (`nfs-client`), provisioned
world-writable (777). With `StrictModes` (default), sshd refuses key auth when
the home directory is group/world-writable — the key is in `authorized_keys`
but every login fails with `Permission denied (publickey)`.

**Diagnose:** `grep -i "refused\|modes" <pod logs>`; `ls -ld /root`.

**Fix:** `container/entrypoint.sh` runs `chmod 700 /root` before starting sshd.
Live patch while a fix ships: `kubectl exec ... chmod 700 /root`.

## 4. SSH login works but `tmux: command not found`

**Cause:** sshd does **not** inherit the container's `ENV PATH`; login shells get
the minimal `/etc/login.defs` PATH.

**Fix:** `container/profile.d/pi-cloud.sh` (copied to `/etc/profile.d/`) exports
`/opt/tmux/bin`, mise binary/shims, and `MISE_*` vars for login shells.

## 5. Phone: `ssh: Could not resolve hostname pi.tailc16433.ts.net`

**Cause:** Tailscale was off on the phone (or MagicDNS disabled) — the box is
only reachable on the tailnet.

**Fix:** turn on the Tailscale app on the same tailnet; enable MagicDNS.
Verify with `adb shell ip addr show | grep tun0` (expect a `100.x.x.x/32`).

## 6. Phone: host reaches, auth fails even with the right key

- **known_hosts mismatch**: use `StrictHostKeyChecking accept-new` in
  `~/.ssh/config` (headless ssh can't prompt).
- **file permissions**: `chmod 600 ~/.ssh/config` (and the key) — ssh refuses
  group/world-writable userland files.
- **key not authorized yet**: the box's `authorized_keys` is sealed; a new key
  requires re-sealing `pi-secrets` (see artr-gitops `apps/pi/README.md`).

## 7. Tailscale device exists but connection times out

**Cause:** operator devices are tagged (`tag:k8s-operator`); a restrictive ACL
needs an explicit rule to let users reach the tagged node.

**Fix (admin console → Access controls):**

```json
{ "action": "accept", "src": ["*"], "dst": ["tag:k8s-operator:*"] }
```

## 8. `git push` from the box fails auth

- Deploy key not authorized: re-add `~/.ssh/id_ed25519.pub` on GitHub
  (`gh ssh-key add` or per-repo deploy keys).
- `known_hosts` missing github.com: it ships sealed in `pi-secrets`
  (`known_hosts` key → `/secrets/git/known_hosts`).
- Wrong key: the box uses `~/.ssh/id_ed25519` (the sealed deploy key) —
  `Host github.com` must not be overridden in `~/.ssh/config`.

## Build/CI notes

- The OCIR `update-gitops` job only bumps `apps/pi/deployment.yaml` when the
  file exists on `origin/main` and the image line matches; otherwise it skips
  cleanly.
- Buildkit layer cache (`type=gha`) makes image iterations fast; the slow spot
  is the first Ruby-from-source compile (~10 min on the arm64 runner).