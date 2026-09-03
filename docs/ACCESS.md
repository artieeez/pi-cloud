# Accessing the box

> **TL;DR** — from any device on your tailnet: `ssh pi` or `ssh pi-cloud`.

## Tailnet names

| Name | Resolves via | Notes |
|---|---|---|
| `pi` | Tailscale MagicDNS (short name) | works from any tailnet device with MagicDNS |
| `pi.tailc16433.ts.net` | Tailscale MagicDNS (FQDN) | the operator-registered device name |
| `100.118.244.0` | direct tailnet IP | stable; handy for scripts |
| `pi.artr.com.br` (optional) | Tailscale "Custom DNS names" | set this up in the admin console if you want a pretty permanent name |

The device is a `LoadBalancer` Service exposed by the Tailscale operator (`loadBalancerClass: tailscale`, hostname annotation `pi`). It is **only reachable from the tailnet** — not from the public internet.

## SSH config (recommended)

Both the Mac and the phone have `~/.ssh/config` entries:

```
Host pi-cloud pi
  HostName pi
  User root
  ServerAliveInterval 30
  StrictHostKeyChecking accept-new
```

So either of these work:

```bash
ssh pi          # short name resolves via MagicDNS
ssh pi-cloud    # alias with keep-alive
```

## Mac conveniences (`~/.zshrc`)

```bash
alias pi-cloud="ssh pi-cloud"                 # ssh pi-cloud
alias picloud="ssh -t pi-cloud 'tmux attach -t pi 2>/dev/null || tmux new -s pi'"
```

- `pi-cloud` — a plain shell on the box
- `picloud` — one word: SSH + attach to the `pi` tmux session (creates it if missing); `Ctrl+B D` to detach without killing work

## Phone (Termux)

Full one-time setup: see [docs/PHONE-TERMUX.md](PHONE-TERMUX.md).

```bash
ssh pi-cloud        # from inside Termux
```

## First-connect notes

- Host keys are sealed (`pi-secrets` -> `/secrets/ssh/ssh_host_ed25519_key`), so
  `known_hosts` entries stay stable across pod restarts.
- Login is **key-only** (root). Keys currently authorized: Mac + phone
  (`termux-s23@artr`). Rotate by re-sealing — see `../artr-gitops/apps/pi/README.md`.

## Making it prettier (optional)

Tailscale admin console → **DNS → Custom DNS names** → map e.g. `pi.artr.com.br`
to the device. It resolves only inside the tailnet, so no public exposure.