# Validation — lazyvim-on-box

**Verifier:** independent fresh-eyes pass (author != implementer; judged from
the real tree only — spec traceability "Status" column not trusted)
**Date:** 2026-09-08
**Verdict:** PASS
**Result:** PASS
**Diff range reviewed:** pi-cloud `33cc715..f178e7c` on `feat/lazyvim-on-box`
(2 commits in the range proper — `097eeab` boot-sync nvim-config, `f178e7c`
docs; scaffold commit `33cc715` [spec + AD-004 + gate] sits immediately before
as the range's base and is the third feature commit. `git rev-list --count`
returns 2, not 3 — see Notes). Review was performed against the full feature
state at HEAD `f178e7c`.

## Spec-anchored outcome check (evidence-or-zero)

| Req | Verdict | Evidence (file:line) |
| --- | ------- | -------------------- |
| LVB-01 | PASS | `container/sync-configs.sh:70` `sync_forced "${HOME_DIR}/.config/nvim" "${ORG}/nvim-config.git" || true` — same FORCED helper as dotagents (`:66`); helper at `:39-55` does `mkdir -p` (`:42`), `git init` + remote reset (`:43-45`), `timeout 90 git fetch` (`:46`), `git checkout -fq -B main origin/main` (`:47`), `git clean -fdq` (`:48`) → repo-tracked content reset to origin/main. nvim runtime state untouched: comment `:68-69` ("nvim runtime state lives in ~/.local/{share,state}/nvim on the PVC and is untouched by sync") + reset only touches the config clone path. |
| LVB-02 | PASS | `container/sync-configs.sh:11` FORCED group header lists `nvim-config -> /root/.config/nvim` (`:9-11`); actual invocation `:70` reuses the shared `sync_forced` helper, byte-identical call shape to dotagents (`:66`). `docs/BOOT-SYNC.md:14-15` target-layout item (`/root/.config/nvim`, public LazyVim config), `:30` in Target layout tree, `:73-80` dedicated "nvim-config → `/root/.config/nvim` (forced)" sync-semantics section, `:142` verification one-liner. |
| LVB-03 | PASS | `container/sync-configs.sh:15` `set -uo pipefail` (unchanged); deploy-key guard `:28-30` logs "deploy key missing — skipping all repo sync" and `exit 0` (still boots); nvim-config sync non-fatal via `|| true` (`:70`) with `log "FAILED to sync …"` from helper `:53`; dotagents/pi-config callers equally tolerant (`:57`, `:66`). |
| LVB-04 | PASS (structural) | Fresh-PVC path: `sync_forced` `mkdir -p "${dir}"` (`:42`) creates `/root/.config/nvim` when absent and `git init`/fetch/`checkout -fB` provisions from origin on a bare dir (idempotent, per spec edge cases). No image bake: grep for `nvim-config\|/root/.config/nvim` across `docker/base.Dockerfile` and `Dockerfile` → zero matches (neovim binary only: base `:108-113` installs to `/opt/nvim`, `ENV PATH` `:113`). `/root` shadowing rationale restated in `docs/BOOT-SYNC.md:74-79` and AD-004. Runtime pod-apply is pending image rollout (see Notes). |
| LVB-05 | PASS | `README.md:25` neovim bullet: "The box runs your LazyVim config (`artieeez/nvim-config`), boot-synced to `~/.config/nvim`; nvim/herdr icons render client-side, so the ssh client's terminal needs a Nerd Font (phone: [docs/PHONE-TERMUX.md](docs/PHONE-TERMUX.md) §6, Mac: JetBrainsMono Nerd Font)" — no font shipped in the box; `README.md:67-69` boot-provisioning paragraph lists `nvim-config → ~/.config/nvim` among FORCED syncs. |
| LVB-06 | PASS | `docs/PHONE-TERMUX.md:79` `## 6. Nerd Font for icons (nvim / herdr glyphs)` (contiguous after §5, `:67`); client-side cause + tofu (`:82-84`); JetBrainsMono Nerd Font Regular same family as Mac (`:86`); ADB-push recipe a. (`:89-99`): stage via `/data/local/tmp` (`:96-99`), `adb push …/JetBrainsMonoNerdFont-Regular.ttf /data/local/tmp/font.ttf` (`:97`), `run-as com.termux` copy to `~/.termux/font.ttf` (`:98`), checksum verify vs Mac sha256 (`:102-103`); in-Termux curl alternative b. (`:109`); apply `termux-reload-settings` (`:113-116`); visual verify glyph row (`:119`); gotchas incl. reload rc=0 only when app foregrounded (`:135-137`). |
| LVB-07 | PASS | `docs/TROUBLESHOOTING.md:158` `## 11. Phone: nvim / herdr icons show as empty boxes (tofu)` (contiguous §1-10 `:6..122` + §11); cause = client-side font, box innocent (`:160-163`); diagnose with glyph-row `printf '\uf718 …'` (`:166-168`); fix pointer `docs/PHONE-TERMUX.md` §6 + `font.ttf`/`termux-reload-settings` (`:170-172`). |
| LVB-08 | PASS | `.specs/STATE.md:47` `### AD-004: nvim-config (LazyVim) is a FORCED config repo on the box`; `:49` Status "Decided (this feature)"; `:50-54` Decision (boot sync to `/root/.config/nvim`, FORCED semantics as dotagents, runtime state untouched, lazy-lock resets, nothing baked, fonts client-side per PHONE-TERMUX §6); `:58-61` Rationale. Handoff snapshot present `:63-76` (feature in flight, live-box + phone applied state, repo state, external action pending). |

## Deterministic gate

`python3 scripts/validate-lazyvim-on-box.py` (from repo root, real tree):

```
[PASS] LVB-01
[PASS] LVB-02
[PASS] LVB-03
[PASS] LVB-04
[PASS] LVB-05
[PASS] LVB-06
[PASS] LVB-07
[PASS] LVB-08

8/8 PASS
```

→ exit 0.

`python3 /Users/arturwebber/.agents/skills/tlc-spec-driven/scripts/validate_spec.py .specs/features/lazyvim-on-box --root .`:

```
validate_spec: 0 error(s), 0 warning(s) in .specs/features/lazyvim-on-box/spec.md
```

→ exit 0.

## Discrimination sensor (isolated scratch, /tmp, deleted after)

Method: full repo copied to `mktemp -d /tmp/lazyvim-sensor-*` preserving relative
layout (`.git` excluded), baseline gate run = 8/8 PASS, then one behavior-level
mutant at a time (revert via `cp` from the real tree between mutants), each run
as `python3 <scratch>/scripts/validate-lazyvim-on-box.py --root <scratch>`.

| Mutant | Expected flip | Result |
| ------ | ------------- | ------ |
| (m1) Remove the nvim-config `sync_forced` call + comment from scratch `container/sync-configs.sh` | LVB-02 (+LVB-03 tolerance clause) → FAIL | KILLED — `[FAIL] LVB-02 … call missing`, `[FAIL] LVB-03 — non_fatal=False …`; 6/8, exit 1 |
| (m2) Remove `nvim-config -> /root/.config/nvim` from the FORCED group header comment in scratch `sync-configs.sh` | LVB-01 → FAIL | KILLED — `[FAIL] LVB-01 — group header entry missing`; 7/8, exit 1 |
| (m3) Delete the `## 6. Nerd Font for icons` heading line in scratch `docs/PHONE-TERMUX.md` | LVB-06 → FAIL | KILLED — `[FAIL] LVB-06 — heading=False font=True …`; 7/8, exit 1 |
| (m4) Remove the whole AD-004 block from scratch `.specs/STATE.md` | LVB-08 → FAIL | KILLED (exit 1) — but noisily: gate raises `IndexError` on `state.split("### AD-004",1)[1]` (check 8 does not guard for absence) instead of printing `[FAIL] LVB-08`. Non-zero exit kills the mutant; see Notes for the gate wart. |
| (m5) Delete §11 (tofu) from scratch `docs/TROUBLESHOOTING.md` | LVB-07 → FAIL | KILLED — `[FAIL] LVB-07 — section=False pointer=False`; 7/8, exit 1 |

No survivors. Scratch deleted (`rm -rf`). Real tree untouched: no `git stash` was
ever used; `git status --porcelain` before and after the sensor run is empty
(clean) — the only new repo file is this `validation.md`, uncommitted by design.

## Residual risks / Notes

1. **Commit-count mismatch in the review range:** the brief said 3 commits in
   `33cc715..f178e7c`; `git rev-list --count 33cc715..f178e7c` = 2. The third
   feature commit `33cc715` ("chore(spec): scaffold… spec, AD-004, gate") is the
   range's base, so `33cc715..f178e7c` diff-stats only the 2 implementation
   commits. The full feature = `5c77885..f178e7c` (3 commits); I reviewed the
   complete feature state at HEAD.
2. **Spec traceability Status column is stale by design:** all 8 rows still read
   "implementing" although the work is committed. This is why verification was
   tree-anchored; consider flipping to "implemented" at PR time.
3. **Gate robustness wart (non-blocking):** `validate-lazyvim-on-box.py:139`
   computes `has_status` unconditionally after a `split("### AD-004", 1)[1]` that
   raises `IndexError` when the marker is absent (surfaced by m4). Exit code is
   still 1 so no mutant survives, but CI would log a traceback instead of a clean
   `[FAIL] LVB-08`. Suggest `has_status = "### AD-004" in state and "Status:" in state.split("### AD-004",1)[1][:200]`… guarded.
4. **Runtime outcomes pending merge (out of repo scope):** live-box re-run of
   `sync-configs.sh` checking out origin/main, first-`nvim` lazy.nvim bootstrap
   on a fresh PVC, and Termux glyph rendering were applied by hand per STATE.md's
   Handoff snapshot but are not reproducible from this repo; the updated
   `sync-configs.sh` reaches pods only after image rebuild + rollout post-merge.
5. **Pre-existing stale doc header (not a feature gap):** `docs/BOOT-SYNC.md:3`
   still says "Design draft — nothing here is implemented yet" although
   `sync-configs.sh` is implemented and shipped; unchanged by this feature
   (identical on `33cc715` and `origin/main`). Cosmetic cleanup opportunity.
6. **STATE.md Handoff snapshot wording** ("Commits pending; then Verifier…")
   was written pre-commit; the commits it describes now exist. Harmless
   snapshot artifact.
7. The spec's AD-004 assumption "nvim-config is a config repo, not a work repo"
   and "public repo" flag match the script's `git@github.com:artieeez/nvim-config.git`
   URL under the sealed account deploy key; repo existence is not verifiable from
   this tree.
