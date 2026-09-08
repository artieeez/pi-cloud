# Boot sync: pi-cloud config + repo provisioning

> Design draft — nothing here is implemented yet. Decided constraints from the
> Mac/pi-cloud delta work: single source of truth per machine, keys never in
> git (sealed on the box, `auth.json`/env paste on the Mac), host-neutral
> shared config (host specifics self-gate or inject via extension).

## Goal

On every pi-cloud pod boot, before sshd starts:

1. **pi-config** (`artieeez/pi-config`, private) → managed clone at `/root/.pi/agent`
2. **dotagents** (`artieeez/dotagents`, private) → managed clone at `/root/.agents`
3. **nvim-config** (`artieeez/nvim-config`, public LazyVim config) → managed
   clone at `/root/.config/nvim`
4. **work repos** → `/root/artieeez/<name>` mirroring the Mac `~/artieeez` layout:
   `artr-gitops`, `pi-cloud`, `oracle-cluster`, `home`, `home-knowledge`
5. `npm install` in `/root/.pi/agent` (extension deps)

Auth stays as today: entrypoint merges sealed `/secrets/pi/auth.json` into
`~/.pi/agent/auth.json` (gitignored in pi-config, so sync can't clobber it).
Box environment context comes from the `pi-cloud-context` extension (in
pi-config, self-gated on `PI_CLOUD=1`) instead of a pi-cloud-custom AGENTS.md.

## Target layout (PVC under `/root`)

```
/root/.pi/agent        pi-config clone (config repos: FORCED sync — reset to origin/main)
/root/.agents          dotagents clone (skills; FORCED sync)
/root/.config/nvim     nvim-config clone (LazyVim editor config; FORCED sync)
/root/.ssh             assembled from /secrets (host keys, authorized_keys, deploy key, known_hosts)
/root/.pi/agent/auth.json   gitignored — merged from sealed secrets at boot
/root/artieeez/
  artr-gitops          WORK repos: clone if missing, else fetch + ff-only pull
  pi-cloud             (never force-reset: box-side work must survive)
  oracle-cluster
  home
  home-knowledge
```

## Sync semantics per group

### pi-config → `/root/.pi/agent` (forced)

Must replace repo-tracked files with `origin/main` while **preserving ignored
runtime files**: `auth.json`, `models-store.json`, `sessions/`, `npm/`, `bin/`,
`node_modules/`, `trust.json`, `missions/`, `run-history.jsonl`.

```bash
cd /root/.pi/agent
git init -q 2>/dev/null || true            # no-op when already a repo
git remote remove origin 2>/dev/null || true
git remote add origin git@github.com:artieeez/pi-config.git
git fetch -q origin
git checkout -fq -B main origin/main       # materialize repo files incl. .gitignore,
                                           # overwriting any baked-template copies
git clean -fdq                             # ignored-aware: drops strays, keeps auth.json etc.
```

Then `npm install --no-audit --no-fund` (incremental; no-op when up to date).

> **Pre-flight check to run in a sandbox before shipping**: confirm that with a
> fresh dir containing a fake `auth.json` + baked `settings.json`, the sequence
> (a) replaces `settings.json` with the repo's, (b) leaves `auth.json` intact,
> (c) leaves `HEAD` on `main`. Ordering choice: sealed-auth merge runs AFTER
> sync so `auth.json` is created post-`clean`.

### dotagents → `/root/.agents` (forced)

Same sequence with `artieeez/dotagents`. Preserves ignored `.pi/tasks/`; the
untracked `matt-tree.json` never exists on the box.

### nvim-config → `/root/.config/nvim` (forced)

Same sequence with `artieeez/nvim-config` (public repo). Neovim runtime state
lives OUTSIDE the config clone (`~/.local/share/nvim` for plugins/Mason,
`~/.local/state/nvim` for logs), so the reset never touches installed plugins;
on a fresh PVC the first `nvim` launch bootstraps lazy.nvim and installs
plugins from the network (one-time, needs internet). Box-side `lazy-lock.json`
edits (e.g. `:Lazy update`) reset at boot — expected; commit + push them.

### Work repos → `/root/artieeez/<name>` (non-forced)

```bash
mkdir -p /root/artieeez
[ -d /root/artieeez/<name>/.git ] || git clone git@github.com:artieeez/<name>.git /root/artieeez/<name>
git -C /root/artieeez/<name> fetch -q origin
git -C /root/artieeez/<name> merge -q --ff-only origin/main 2>/dev/null || true
```

`--ff-only` never destroys local commits or uncommitted work (e.g. a resealed
`pi-auth-sealed.yaml` in `artr-gitops`). Local state wins; the user pushes.

## Entrypoint order (revised)

1. Assemble `/root/.ssh` from `/secrets` (host keys, `authorized_keys`,
   deploy key + `known_hosts`) — unchanged.
2. **Run `sync-configs.sh`** (the above). Non-fatal: on git/network failure,
   log and continue (first boot with no network still boots pi on sealed auth;
   re-run manually via `/usr/local/bin/sync-configs.sh`).
3. Merge sealed `auth.json` → `~/.pi/agent/auth.json` (jq overlay) — AFTER sync.
4. ~No baked-template fallback~ (decision: DELETE) — `settings.json`/`AGENTS.md`
   stop being shipped in the image; a network-less first boot simply runs pi
   on its built-in defaults until a sync succeeds.
5. herdr server starts with a shell pane rooted at `/root/artieeez` (was
   `/workspace`) — pi's cwd context then mirrors the Mac's `~/artieeez`
   (`AUTO_PI=1` opens a pi agent pane inside it).

## Image / deployment changes (pi-cloud + artr-gitops)

- `artr-gitops/apps/pi/deployment.yaml`: add env `PI_CLOUD: "1"` (activates the
  `pi-cloud-context` extension injection).
- pi-cloud `Dockerfile`: `WORKDIR /root/artieeez` (mkdir in image),
  `COPY container/sync-configs.sh`, drop `/workspace` creation claims.
- **`/root` is the PVC mount and shadows image content** — nothing config-relevant
  is baked under `/root` anymore: kubeconfig (`container/kubeconfig.yaml`) is
  baked to `/opt/pi-cloud-kubeconfig.yaml` and seeded by the entrypoint into
  `/root/.kube/config` when absent (fixes the box's silently-broken kubectl:
  it had no kubeconfig, defaulting to localhost:8080).
- `container/pi-agent/` (baked `settings.json` + `AGENTS.md`): **deleted** —
  real global AGENTS comes from pi-config; env context from the extension;
  settings from the repo. Dockerfile stops COPYing it; entrypoint drops the
  `/opt/pi-agent` references.
- Docs (`README.md`, container comments, artr-gitops `apps/pi/README.md`):
  workspace now `/root/artieeez/*`; mention boot sync + `PI_CLOUD`.

## Failure modes

| Case | Behavior |
|---|---|
| No network / git fails on first boot | sync logs + continues; pi boots on sealed auth + built-in defaults; `sync-configs.sh` re-runnable |
| Deploy key not sealed (`/secrets/git` missing) | repo sync skipped with a log (matches current "no git pushes without it") |
| `PI_CLOUD` env missing | box runs but without injected env context (extension inert) |
| User edits `~/.pi/agent` files on the box | lost on next boot for tracked files (config repos are forced) — expected, commit from the box instead |
| Uncommitted work in `/root/artieeez/*` | preserved (`--ff-only` refuses to clobber) |

## Verification (after deploy)

```bash
ssh pi-cloud 'git -C ~/.pi/agent log --oneline -1'       # == pi-config main
ssh pi-cloud 'git -C ~/.agents log --oneline -1'          # == dotagents main
ssh pi-cloud 'git -C ~/.config/nvim log --oneline -1'     # == nvim-config main
ssh pi-cloud 'ls /root/artieeez'                          # the 5 repos
ssh pi-cloud 'jq keys ~/.pi/agent/auth.json'              # deepseek + google + opencode-go once google is sealed
kubectl get pod -n pi -o jsonpath='{.spec.containers[0].env}' | grep PI_CLOUD
ssh pi-cloud 'ls ~/.pi/agent/extensions'                  # hermes-acp/worktree/pi-cloud-context present
```

## Open questions (confirm before implementing)

1. Forced sync on config repos (`pi-config`, `dotagents`), never on the 5 work
   repos — **assumed yes**.
2. herdr/pi default cwd `/root/artieeez` (retiring the tmux-era `/workspace`
   layout) — **assumed yes** (docs/template updates included).
3. Baked `/opt/pi-agent` files — **decision: delete, no fallback**.
4. `google` sealing: run `./reseal-pi-auth.sh google` (script now committed to
   `artr-gitops` at `apps/pi/reseal-pi-auth.sh`, `0c0d823`).
5. Deploy key verified: the sealed `id_ed25519` is registered as the GitHub
   **account** SSH key for `artieeez` (not per-repo deploy keys) — access to
   all seven repos confirmed.
