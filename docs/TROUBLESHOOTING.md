# Troubleshooting

Every issue below was hit and fixed while bringing the box up live on the artr
cluster. Symptom → cause → fix, so the next incident is minutes, not hours.

## 1. Host key changed on every image rebuild (`REMOTE HOST IDENTIFICATION HAS CHANGED`)

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

## 4. SSH login shells miss the box toolchain (`mise`, `nvim` not on PATH)

**Cause:** sshd does **not** inherit the container's `ENV PATH`; login shells get
the minimal `/etc/login.defs` PATH.

**Fix:** `container/profile.d/pi-cloud.sh` (copied to `/etc/profile.d/`) exports
`/opt/nvim/bin`, `/opt/mise-root/local/bin`, `/opt/mise/shims`, and the `MISE_*`
vars for login shells.

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

## 9. `bundle install` fails: native gem extconf — no C compiler (msgpack/bootsnap)

**Symptom:** in a fresh worktree, `bundle install` dies compiling a native gem
(e.g. msgpack 1.8.4, a bootsnap dependency) with *"extconf failed … The
compiler failed to generate an executable file … You have to install
development tools first"*. `which gcc cc make g++` all come back empty.

**Cause:** `docker/base.Dockerfile` is multi-stage: `build-essential` is
installed in the **build** stage (to compile Ruby), but multi-stage
COPY only carries binaries out — the shipped base final stage was runtime
packages only, so a fresh box has no C toolchain. This is true of **every**
base tag ever published (the final stage apt list is unchanged since the
pre-split Dockerfile); it is not a stale-tag/drift problem.

**Fix (baked):** the base final stage now installs `build-essential`
(>= ruby-4.0.5-5). Runtime ad hoc, until that base is deployed:

```bash
apt-get update && apt-get install -y build-essential   # box has network + apt
```

Note the image `rm -rf`s the apt lists at build time, so any runtime
`apt-get install` needs the `apt-get update` first. The mise-managed Ruby
ships its headers (`/opt/mise/installs/ruby/4.0.5/include`), so compilers
alone are enough — no extra ruby-dev needed.

## 10. `playwright-cli open` fails: Chromium distribution 'chrome' not found / chrome-for-testing not installed

**Symptom:** `playwright-cli open <url>` (no flags) errors with *"Chromium
distribution 'chrome' is not found at /opt/google/chrome/chrome"*;
`playwright-cli open --browser chromium <url>` errors with *"Browser
chrome-for-testing is not installed; expected executable at
/opt/ms-playwright/chromium-1243/chrome-linux-arm64/chrome"*.

**Cause:** the CLI's default browser resolution never picks the baked
headless shell. With no config it forces `channel: "chrome"` (system Google
Chrome, not installed); `--browser chromium` forces
`channel: "chrome-for-testing"` (the full chromium build, also not baked —
`--only-shell` skips it). Only the chromium **headless shell**
(`chromium_headless_shell-1243`) is baked.

**Fix (baked):** the image ships `/opt/pi-cloud-playwright-cli.config.json`
and sets `PLAYWRIGHT_MCP_CONFIG` (Dockerfile ENV + profile.d export for sshd
sessions). The config pins `browser.browserName: "chromium"` with **no**
channel, so playwright launches its headless-shell build (playwright's
normal headless default), plus `chromiumSandbox: false` (container runs as
root) and `headless: true`. `playwright-cli open <url>` then works out of
the box; snapshot/close etc. run against the same session.

Runtime workaround (until that image is deployed):

```bash
playwright-cli install-browser chrome-for-testing   # ~187MB download
playwright-cli open --browser chromium <url>
```

Caveats: `--browser chromium|chrome` (and `--headed`) explicitly select
builds that are **not** baked — keep using the default `open` on the box.
Anything installed at runtime under `/opt/ms-playwright` lives in the
container's writable layer and **vanishes on redeploy** (only `/root` is on
the PVC); bake browser changes into the Dockerfile instead.

## Build/CI notes

- The OCIR `update-gitops` job only bumps `apps/pi/deployment.yaml` when the
  file exists on `origin/main` and the image line matches; otherwise it skips
  cleanly.
- Buildkit layer cache (`type=gha`) makes image iterations fast; the slow spot
  is the first Ruby-from-source compile (~10 min on the arm64 runner).