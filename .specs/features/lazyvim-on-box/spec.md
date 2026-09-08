# LazyVim on the box (nvim-config boot sync + phone Nerd Font)

## Problem Statement

The box ships a plain Neovim 0.12.5 (no config), so editing from the phone is
vanilla: no LazyVim plugins, no extras, no icons. The user's real editor
config is versioned separately at `artieeez/nvim-config` (a LazyVim starter
with language extras, public repo) and checked out locally at `~/.config/nvim`.
Icons in LazyVim/herdr UIs render **client-side**: Termux on the phone uses a
non-patched font, so glyphs show as tofu boxes. The box itself needs no font.

## Goals

- Boot-sync `artieeez/nvim-config` into `/root/.config/nvim` on every pod boot,
  with the same FORCED config-repo semantics as `dotagents` → `~/.agents`, so a
  (re)provisioned box runs the user's LazyVim config and stays current.
- Keep the existing failure tolerance: a git/network failure logs and the box
  still boots; nothing config-relevant is baked into the image (`/root` is the
  PVC mount and shadows image content anyway).
- Document the client-side Nerd Font requirement and ship the exact Termux
  install recipe (ADB push of JetBrainsMono Nerd Font, byte-matched to the
  Mac) plus the tofu-icon troubleshooting entry.

## Out of Scope

| Item | Reason |
| ---- | ------ |
| Baking nvim-config or a Nerd Font into the image | Config lives on the PVC via boot sync (matches the config-repo design); fonts are client-side, never server-side |
| Changes to `artieeez/nvim-config` itself | Config content is the user's; this feature only provisions it |
| Mac-side font setup | Mac terminal already runs JetBrainsMono Nerd Font |
| artr-gitops changes | No new secrets/env/deployment keys needed; the image rollout on merge is the existing pipeline |
| herdr UI font work | herdr renders in the ssh client's terminal; the same Termux font fix covers it |

## Assumptions & Open Questions

Every ambiguity is resolved or recorded here - nothing is left silently unclear.

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Use the user's versioned config, not a fresh starter | `artieeez/nvim-config` (LazyVim starter + extras) | User: "my nvim config is versioned in ~/.config/nvim" — that repo is the source of truth | yes |
| nvim-config is a config repo, not a work repo | FORCED sync to `/root/.config/nvim` (repo truth; box-side tracked edits reset at boot, commit & push from the box) | Mirrors `dotagents` → `~/.agents`; matches the Mac layout where the checkout lives at `~/.config/nvim` | assumed (plan default) |
| Live apply on the running pod before the image ships | Clone + headless first-run install now (persists on the `/root` PVC) | User asked to install now; plugin sync is a one-time network step | yes |
| Font family for Termux | JetBrainsMono Nerd Font Regular (same file as the Mac) | Consistent look between Mac and phone; verified byte-identical sha256 | yes |
| Phone has no reliable public DNS today | Primary recipe = ADB push from the Mac; in-Termux curl kept as alternative | `github.com`/`example.com` resolution failed from Termux during this work | assumed (observed) |
| Termux settings reload | `termux-reload-settings` with the app foregrounded | Required for running sessions to pick up `font.ttf` | yes (verified rc=0) |
| Push/PR/deploy after local commits | Requires explicit user go-ahead | Blast radius: deploy touches the cluster | no (action at end) |

**Open questions:** none - all resolved or logged above.

## User Stories

### P0: LazyVim provisioned on the box; phone renders its icons

**User Story**: As the box operator, I want the box's nvim to run the same
LazyVim config I use on the Mac, and my phone's Termux to render Nerd Font
icons, so editing from the phone over ssh feels like home.

**Why P0**: The box exists for phone-friendly editing (README: "sshd + nvim =
phone-friendly editing"); plain nvim and tofu icons defeat the purpose.

**Acceptance Criteria**:

1. WHEN the box boots and the sealed git deploy key is available THEN the boot
   sync SHALL force-sync `artieeez/nvim-config` into `/root/.config/nvim`,
   resetting repo-tracked content to `origin/main` while leaving nvim runtime
   state (`~/.local/share/nvim`, `~/.local/state/nvim`) on the PVC untouched.
2. `container/sync-configs.sh` SHALL list nvim-config in its FORCED group
   header comment and SHALL invoke the same `sync_forced` helper for it that
   `dotagents` uses, and docs/BOOT-SYNC.md SHALL list it in the target layout
   and sync-semantics sections.
3. IF the deploy key or network is unavailable THEN the boot sync SHALL log the
   failure and continue booting (existing failure tolerance, unchanged).
4. WHEN a pod boots with no `/root/.config/nvim` (fresh PVC) THEN the sync
   SHALL create the directory and provision nvim-config from origin, with no
   config baked into the Dockerfile image layer.
5. The box README SHALL describe nvim as running the user's LazyVim config
   (`artieeez/nvim-config`), boot-synced to `~/.config/nvim`, and SHALL state
   that Nerd Font icons render client-side (no font shipped in the box).
6. docs/PHONE-TERMUX.md SHALL document the Termux Nerd Font install — the ADB
   push recipe (JetBrainsMono Nerd Font Regular to `~/.termux/font.ttf` +
   `termux-reload-settings`) and an in-Termux curl alternative — and SHALL
   explain that this is what makes LazyVim/herdr icons render over ssh.
7. docs/TROUBLESHOOTING.md SHALL record the tofu-boxes/icons symptom, its
   client-side font cause, and a pointer to the PHONE-TERMUX.md recipe.
8. `.specs/STATE.md` SHALL record decision AD-004 (nvim-config is a FORCED
   config repo on the box at `/root/.config/nvim`) with status, decision, and
   rationale.

**Independent Test**: Re-run `sync-configs.sh` on the live box and observe
nvim-config checked out at `/root/.config/nvim` on `origin/main`; on the phone,
open Termux after the font install and confirm Nerd Font glyphs render (no
tofu) in a terminal and in the box's LazyVim UI over ssh.

---

## Edge Cases

- IF `:Lazy update` on the box rewrites `lazy-lock.json` locally THEN the next
  boot's forced sync resets it to origin/main — expected for config repos;
  commit + push from the box to keep lock changes.
- IF the phone is off the public internet (Tailscale-only) THEN the in-Termux
  curl recipe fails DNS and the ADB push recipe is the path.
- IF a pod restarts mid-sync THEN the next boot re-runs `sync_forced`, which is
  idempotent (`git init`/fetch/`checkout -fB`), and the box still boots.
- IF a fresh PVC has no `~/.local/share/nvim` plugins yet THEN the first `nvim`
  launch bootstraps lazy.nvim and installs plugins from the network (needs
  internet once; afterwards everything is on the PVC).

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| LVB-01 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |
| LVB-02 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |
| LVB-03 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |
| LVB-04 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |
| LVB-05 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |
| LVB-06 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |
| LVB-07 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |
| LVB-08 | P0: LazyVim provisioned on the box; phone renders its icons | Execute | implementing |

**Coverage:** 8 total, 8 mapped, 0 unmapped

---

## Success Criteria

- Live box: `nvim` over ssh shows the LazyVim UI (dashboard/statusline icons),
  and `git -C /root/.config/nvim rev-parse HEAD` equals nvim-config origin/main.
- Phone: Termux renders Nerd Font glyphs (verified by screenshot, no tofu).
- Deterministic gate `python3 scripts/validate-lazyvim-on-box.py` exits 0.
- Repo docs (README, BOOT-SYNC, PHONE-TERMUX, TROUBLESHOOTING, STATE) describe
  the new provisioning and the phone font fix consistently.
