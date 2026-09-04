# pi-cloud

A persistent, SSH-accessible dev box on the artr OKE cluster (oracle-cluster) for running
[pi](https://pi.dev) (+ Ruby) from an Android phone or any SSH client.

## What's inside

- **pi coding agent** (global npm, pinned 0.84.x) — run `pi` inside tmux
- **kubectl v1.36.1** with an in-cluster kubeconfig (`pi-admin` SA, cluster-admin) —
  the box can inspect Argo apps, pods, and logs directly
- **Ruby** via [mise](https://mise.jdx.dev) (4.0.5, matches `home`) — `mise` is `.ruby-version` aware
- **tmux 3.7c** built from source (≥3.5 needed for `extended-keys-format csi-u`, see pi's tmux docs)
- **sshd** (key-only, root, hardened) — the only entry point, port 22
- **neovim 0.12.5** (official arm64 build) — tmux + sshd + nvim = phone-friendly editing
- git, ripgrep, sqlite3, libvips, jq, Node 24

## Two images: base + app

The image is split so per-commit builds stay small and the cluster node stores
one copy of the heavy layers:

- **`pi-cloud-base`** (`docker/base.Dockerfile`) — node + OS deps + tmux + neovim
  + mise/Ruby (~800MB). Rebuilt rarely (ruby/node/tmux/OS bumps) by `build-base.yaml`
  (path-triggered push + `workflow_dispatch`); pushed as
  `vcp.ocir.io/axtvnrdemzo7/pi-cloud-base:ruby-4.0.5_tmux-3.7c` (+ `latest`).
- **`pi-cloud`** (repo-root `Dockerfile`) — thin delta over the base: pi agent
  version, kubectl, container assets (`container/`). Built on every push.

## How it's deployed

GitHub Action builds `linux/arm64` → pushes to OCIR (`vcp.ocir.io/axtvnrdemzo7/pi-cloud`)
→ bumps the image tag in `artieeez/artr-gitops/apps/pi/deployment.yaml` → Argo CD syncs.

The app build pins `BASE_TAG` (both workflows must stay in sync when the base is
re-published under a new tag).

## Secrets volume layout (`/secrets`, mounted from SealedSecrets)

| Path | Contents | Optional? |
|---|---|---|
| `/secrets/ssh/ssh_host_ed25519_key(.pub)` | stable host keys | generated into the PVC home if absent |
| `/secrets/ssh/authorized_keys` | your SSH public keys | no → nobody can log in |
| `/secrets/git/id_ed25519(.pub)` | GitHub deploy key for `artieeez/*` | yes — no git pushes without it |
| `/secrets/git/known_hosts` | `github.com` host key | yes |
| `/secrets/pi/auth.json` | pi `auth.json` (opencode-go + friends) | no → pi has no model auth |

Entrypoint copies these into `/root/.ssh` and `/root/.pi/agent`, runs the boot
sync (see below), then starts sshd and a pre-created `pi` tmux session.

## Boot provisioning (config + repos)

On every boot the entrypoint runs `sync-configs.sh` (deploy key required, see
`/secrets/git`): it force-syncs your `pi-config` → `~/.pi/agent` and `dotagents`
→ `~/.agents`, then clones/updates the work repos under **`~/artieeez`**
(`artr-gitops`, `pi-cloud`, `oracle-cluster`, `home`, `home-knowledge`) —
mirroring your Mac `~/artieeez` layout. The image ships no baked pi config; the
box's environment context is injected by the `pi-cloud-context` extension
(`PI_CLOUD=1`). Details: [docs/BOOT-SYNC.md](docs/BOOT-SYNC.md).

## Using it

```bash
ssh root@pi.<tailnet>.ts.net      # via Tailscale operator (recommended)
tmux attach -t pi                 # the pre-created session; or start `pi` in it
```

From devices on your tailnet, MagicDNS short names work, so it's just:

```bash
ssh pi          # or `ssh pi-cloud` with the ssh config entry (Mac + phone)
```

Set-up + access details:

| Doc | Contents |
|---|---|
| [docs/ACCESS.md](docs/ACCESS.md) | hostnames, ssh config, Mac aliases (`pi-cloud` / `picloud`) |
| [docs/PHONE-TERMUX.md](docs/PHONE-TERMUX.md) | Termux over ADB, keygen, phone ssh config, 16 KB dialog |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | every runtime gotcha hit during bring-up + fixes |
| [docs/BOOT-SYNC.md](docs/BOOT-SYNC.md) | boot provisioning design: config + repo sync, layout |

`AUTO_PI=1` on the Deployment boots pi directly inside the tmux session.

## Local build

```bash
# base first (only needed once per base change), then the app image
docker build -f docker/base.Dockerfile -t pi-cloud-base .
docker build -t pi-cloud .
docker run -d -p 2222:22 -v "$PWD/.secrets:/secrets:ro" --name pi-cloud pi-cloud
ssh -p 2222 root@localhost
```