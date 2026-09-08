# Phone (Termux) setup

Goal: Termux on Android, SSH client + keypair, so the phone can log into the
box over Tailscale. Everything below was done over ADB (USB debugging).

## 1. Install Termux over ADB

Use the **GitHub builds** — the Google Play version is deprecated/outdated.

```bash
# arm64 phones (check: adb shell getprop ro.product.cpu.abi)
BASE=https://github.com/termux/termux-app/releases/download/v0.118.3
curl -fsSL -O "$BASE/termux-app_v0.118.3+github-debug_arm64-v8a.apk"
curl -fsSL -O "$BASE/termux-app_v0.118.3+github-debug_sha256sums"

# Termux:API (optional; clipboard/notifications integrations)
BASE2=https://github.com/termux/termux-api/releases/download/v0.53.0
curl -fsSL -O "$BASE2/termux-api-app_v0.53.0+github.debug.apk"

# verify checksums, then:
adb install -r termux-app_v0.118.3+github-debug_arm64-v8a.apk
adb install -r termux-api-app_v0.53.0+github.debug.apk
```

The GitHub builds are debuggable, which lets you drive setup headlessly:

```bash
adb shell am start -n com.termux/.app.TermuxActivity   # run first-boot bootstrap
adb shell run-as com.termux ls files/usr/bin/pkg       # wait until it exists
```

## 2. Package install + SSH key (headless)

```bash
TERMUX='adb shell run-as com.termux env PREFIX=/data/data/com.termux/files/usr \
  HOME=/data/data/com.termux/files/home \
  PATH=/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin \
  /data/data/com.termux/files/usr/bin/bash -c'

$TERMUX "apt-get update"
$TERMUX "apt-get install -y openssh"
$TERMUX "mkdir -p ~/.ssh && ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C 'termux-s23@artr'"
$TERMUX "cat ~/.ssh/id_ed25519.pub"          # add this line to the box's authorized_keys
```

Quoting gotcha: adb flattens the command line — inner double quotes are eaten.
Wrap the whole `run-as ... bash -c "..."` in single quotes on your side so the
*device* shell keeps the quotes:

```bash
adb shell 'run-as com.termux env ... /data/.../bash -c "apt-get update"'
```

## 3. Add the key to the box

The box's `authorized_keys` is **sealed** (source of truth), so add the phone
key to `artr-gitops/apps/pi/pi-secrets-sealed.yaml` by re-sealing `pi-secrets`
with the Mac + phone lines (see `artr-gitops/apps/pi/README.md` → "Rotating /
adding keys"), then push; Argo syncs; the next pod start picks it up.

## 4. Tailscale on the phone

- Install the Tailscale Android app and log into the **same tailnet** as the box.
- Enable MagicDNS (Settings → DNS → MagicDNS) — required for `pi` / `pi.tailc16433.ts.net`.
- Status check from the Mac: `tailscale status` shows `pi` and your phone.

## 5. SSH config in Termux

```bash
$TERMUX "printf 'Host pi-cloud pi\n  HostName pi\n  User root\n  ServerAliveInterval 30\n  StrictHostKeyChecking accept-new\n' > ~/.ssh/config && chmod 600 ~/.ssh/config"
$TERMUX "ssh pi-cloud 'herdr status'"
```

> Agents live in **herdr** panes on the box (no tmux). From Termux, `ssh pi-cloud`
> then `herdr` opens the full-screen TUI; killing the ssh session does **not** stop
> panes — reattach with `herdr` again later. (A native herdr client in Termux is not
> set up yet — the in-ssh TUI is the phone path.)

## 6. Nerd Font for icons (nvim / herdr glyphs)

LazyVim on the box (dashboard, statusline, git signs, pickers) and herdr's TUI
draw Nerd Font icons **client-side**: the ssh client's terminal renders them,
so Termux needs a patched font or glyphs show as empty boxes (tofu). The box
itself ships no font (by design — see docs/TROUBLESHOOTING.md §11).

This installs **JetBrainsMono Nerd Font Regular** — the same family as the Mac
terminal — as Termux's font. Two routes:

a. **ADB push from the Mac (recommended)** — byte-identical to your Mac file
   and works even when the phone has no public DNS (github.com did not resolve
   from Termux during setup, so the in-Termux download below is only an
   alternative). Android's scoped storage also blocks reading `/sdcard` from
   `run-as`, so stage via `/data/local/tmp`:

```bash
adb shell 'chmod 755 /data/local/tmp'                 # let the app uid traverse
adb push ~/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf /data/local/tmp/font.ttf
adb shell 'run-as com.termux sh -c "mkdir -p /data/data/com.termux/files/home/.termux && cp /data/local/tmp/font.ttf /data/data/com.termux/files/home/.termux/font.ttf"'
adb shell 'rm -f /data/local/tmp/font.ttf && chmod 771 /data/local/tmp'   # clean up

# verify: checksums must match (the Mac file is the same bytes)
shasum -a 256 ~/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf
adb shell 'run-as com.termux sha256sum /data/data/com.termux/files/home/.termux/font.ttf'
```

b. **In-Termux download** — only when the phone has public internet:

```bash
$TERMUX "curl -fsSL -o ~/.termux/font.ttf https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/Regular/JetBrainsMonoNerdFont-Regular.ttf"
```

Then apply (Termux must be running in the foreground for the reload broadcast):

```bash
adb shell 'input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard; am start -n com.termux/.app.TermuxActivity'
adb shell 'run-as com.termux env PREFIX=/data/data/com.termux/files/usr HOME=/data/data/com.termux/files/home PATH=/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin /data/data/com.termux/files/usr/bin/bash -c termux-reload-settings'
```

Verify visually: print a glyph row in a Termux session
(`printf '\uf718 \ue0b0 \uf85a \uf4a2\n'`) — patched glyphs render as icons
(git branch, triangles, …), not empty rectangles.

## Notes / gotchas

- **"Compatibility issue" dialog (libtermux.so / libtermux-bootstrap.so,
  "segment load not aligned")**: shown by Termux 0.118.x's ELF-alignment check.
  On 4 KB page devices (`adb shell getconf PAGE_SIZE` → 4096) it is a false
  positive — dismiss it. On real 16 KB-page devices, use the alignment-fix line:
  `v0.119.0-beta.3`, asset `termux-app_v0.119.0-beta.3+apt-android-7-github-debug_arm64-v8a.apk`.
- Userland config files created with `>`/`>>` may be 0644 — ssh refuses
  world-writable keys/configs, so `chmod 600` them.
- The phone key (`termux-s23@artr`) is sealed into the box — wipe-and-reinstall
  of the phone just needs key rotation (`scripts/seal-pi-auth.sh` is only for the
  LLM key; the ssh rotation flow is in artr-gitops `apps/pi/README.md`).
- `termux-reload-settings` returns rc=0 only when the Termux app is running; if
  a reload seems ineffective, force-stop Termux (it re-reads `font.ttf` when a
  session starts). `cp` keeps app ownership, so no `chmod` on `font.ttf` needed.