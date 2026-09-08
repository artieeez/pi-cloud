# STATE — pi-cloud project memory

## Decisions

### AD-001: Drop tmux from the base image (republish as ruby-4.0.5-5)

- **Status:** Decided (this feature)
- **Decision:** tmux is removed entirely from `docker/base.Dockerfile` (no compile
  stage, no runtime libs/symlinks, no `/opt/tmux`, no PATH entry). The base is
  republished under a new tag `ruby-4.0.5-5` (counter continues, tmux segment
  drops). Delivered as one PR; `build-push-ocir.yaml` gains a manifest-wait step
  (`docker manifest inspect`, up to 600s) so a single merge can never race the
  base publish — build-base publishes the new tag, the app build waits for it.
- **Rationale:** herdr replaced tmux as the pane/workspace host; nothing in the
  box shells out to tmux. The repo's own README already slated tmux for removal
  "at the next base rebuild". Removing it deletes a from-source compile and its
  runtime deps (~libevent/libncurses) from the image.

### AD-002: Version bumps on pi-cloud via hosted Renovate + herdr sha-sync helper

- **Status:** Decided (this feature)
- **Decision:** pi-cloud adopts the hosted Renovate app (already used on
  artr-gitops). Custom managers drive every version ARG in the app Dockerfile:
  `PI_VERSION`/`PLAYWRIGHT_CLI_VERSION` (npm datasource), `KUBECTL_VERSION`
  (github-releases kubernetes/kubernetes), `GH_VERSION` (github-releases
  cli/cli), `HERDR_VERSION` (github-releases herdrdev/herdr). kubectl/gh keep
  curl + official checksum verification; herdr keeps its hand-pinned
  `HERDR_SHA256` enforced by the build. Because Renovate cannot compute a
  release-asset hash, a small `herdr-sha-sync` helper (workflow + script)
  patches `HERDR_SHA256` onto any PR that changes `HERDR_VERSION`.
- **Rationale:** uniform proposal source (one bot queue, reviewable PRs) while
  keeping per-ecosystem canonical integrity mechanisms. Replacing kubectl/gh
  verification with a lockfile would be an integrity downgrade; the helper is
  the only honest way to keep herdr's checksum strict and inside Renovate.

### AD-003: Tag-based pinning, no digest pinning

- **Status:** Decided (this feature)
- **Decision:** Container image pins stay tag-based; digest pinning
  (`pinDigests`) is deliberately NOT enabled. Recorded in `renovate.json`
  (own-image packageRule) and here.
- **Rationale:** matches the estate norm (no `@sha256:` digests anywhere) and
  homelab practice; digest churn PRs cost more than they save at this scale.
  Own OCIR images are already immutable via `sha-<7>` git build tags. Revisit
  if a stricter posture is ever wanted.

### AD-004: nvim-config (LazyVim) is a FORCED config repo on the box

- **Status:** Decided (this feature)
- **Decision:** `artieeez/nvim-config` (public LazyVim config) syncs at boot
  into `/root/.config/nvim` with the same FORCED semantics as `dotagents` →
  `/root/.agents`: reset to origin/main on boot, nvim runtime state under
  `~/.local/{share,state}/nvim` on the PVC untouched, and box-side
  `lazy-lock.json` edits (`:Lazy update`) reset unless committed + pushed.
  Nothing config-relevant is baked into the image (`/root` is the PVC mount);
  fonts are never shipped server-side — Nerd Font icons render client-side, so
  the phone's Termux gets JetBrainsMono Nerd Font (`docs/PHONE-TERMUX.md` §6).
- **Rationale:** the box exists for phone-friendly editing with the user's real
  editor; the config is versioned separately (`~/.config/nvim` on the Mac, same
  repo), so boot-sync keeps every (re)provisioned pod on nvim-config
  origin/main and mirrors the Mac layout exactly.

## Handoff snapshot

- **Feature in flight:** `.specs/features/lazyvim-on-box/` on branch
  `feat/lazyvim-on-box` (nvim-config boot sync → `/root/.config/nvim` +
  Termux Nerd Font docs + AD-004). Commits `33cc715..7a2476f`;
  **Verifier PASS** (`validation.md`, 8/8 AC evidence + 5/5 discrimination
  mutants killed). Awaiting PR open → user merge/promote.
- **Live box (applied, persists on the `/root` PVC):** nvim-config cloned at
  `/root/.config/nvim` on origin/main and LazyVim plugins installed (first-run
  headless sync). The updated `sync-configs.sh` reaches pods only after the
  image rebuild + rollout that follows the PR merge.
- **Phone (applied):** Termux font = JetBrainsMono Nerd Font Regular
  (`~/.termux/font.ttf`, sha256 matches the Mac file), reloaded; glyphs render.
- **Repo state:** pi-cloud on `feat/lazyvim-on-box` (from `main`); no other
  branches in flight.
- **External action pending:** open PR (user approved); deploy follows on
  merge via the normal image rebuild + rollout (`build-push-ocir.yaml`).
