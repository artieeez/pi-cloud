# herdr panes get toolchain env; base ships C/POSIX man pages

## Problem Statement

Two box defects surfaced from use:

1. `nvim` does not open inside herdr panes. herdr's default `shell_mode` is
   `auto`, which spawns **interactive non-login** shells on Linux. They never
   source `/etc/profile.d/pi-cloud.sh`, which is the mechanism sshd login
   shells rely on for the toolchain PATH, `PI_CLOUD`, and the sealed
   `DEEPINFRA_API_KEY`/`GH_TOKEN` exports. Pane env therefore differs
   arbitrarily from ssh login-shell env, and the pane's `TERM` depends on what
   the headless `herdr server` inherited (entrypoint runs with no terminal, so
   `TERM` can be empty). The fix makes panes login shells and guarantees `TERM`
   server-side, so a pane's environment is identical to an ssh login shell.
2. `man pthread` finds nothing. The base installs `manpages` (section 1 pages
   only); the C programmer docs live elsewhere: `pthread(3posix)` and the other
   POSIX pages come from `manpages-posix-dev`, the Linux section-3 variants
   (`printf(3)`, `pthread_create(3)`) from `manpages-dev`.

## Goals

- Every new herdr pane is a bash **login shell** sourcing
  `/etc/profile.d/pi-cloud.sh`, with a non-empty `TERM` guaranteed in the
  server environment, so `nvim`, the toolchain, `PI_CLOUD`, and the sealed
  keys are present inside panes exactly as in ssh login shells.
- The base image carries C and POSIX programmer man pages and is republished
  as `ruby-4.0.5-7` with both build workflows in sync.
- Each fix gets a `docs/TROUBLESHOOTING.md` entry in the existing
  symptom → cause → fix format.

## Acceptance Criteria

- AC-01: WHEN the box creates a new herdr terminal pane THEN the pane shell
  SHALL be bash run as a login shell, so `/etc/profile.d/pi-cloud.sh` applies
  the toolchain PATH, `PI_CLOUD=1`, and the sealed-key exports inside the
  pane.
- AC-02: WHEN the entrypoint starts the herdr server THEN `TERM` SHALL be
  non-empty (fallback `xterm-256color`) in the server and the panes it spawns.
- AC-03: WHEN the base image is republished THEN `BASE_TAG` SHALL be
  `ruby-4.0.5-7` in `.github/workflows/build-base.yaml` AND
  `.github/workflows/build-push-ocir.yaml`.
- AC-04: WHEN `man pthread` runs on the box THEN the `pthread(3posix)` page
  SHALL render.
- AC-05: WHEN `man 3 printf` runs on the box THEN the `printf(3)` page SHALL
  render.
- AC-06: WHEN the herdr config file already declares a `[terminal]` section
  THEN the entrypoint SHALL NOT modify it (the config write is idempotent).

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| herdr `shell_mode` default on Linux is non-login | panes must be forced to `login` | herdr docs: `auto` = login only on macOS, non-login elsewhere | docs (on-box check post-deploy) |
| `pthread` man page lives in `manpages-posix-dev` | install `manpages-dev manpages-posix manpages-posix-dev` | Debian bookworm filelists: `man3/pthread.3posix.gz` + `man3/pthread_create.3.gz` | packages.debian.org |
| The herdr config file is user-owned on the PVC | entrypoint writes only when `[terminal]` is absent | Never clobber a user config | by design |
| Exact nvim-in-herdr failure text | not required for the fix | Login-shell env + TERM fallback covers PATH, env, and TERM failure classes; runtime confirmation is a post-deploy check | pending on box |
| Base republish follows AD-001 convention | next counter `ruby-4.0.5-7`, tag synced in the same PR | AD-001 established the pattern | yes |

**Open questions:** the exact nvim error text inside the pane remains unobserved
(no box access from this environment); it is recorded as a post-deploy runtime
confirmation, not a design input — the fix is complete for the PATH, env, and
TERM failure classes regardless of the message.

## Out of Scope

| Item | Reason |
| ---- | ------ |
| Changing herdr itself or its upstream config docs | The box provisions config; herdr behavior is fixed upstream |
| nvim-config / LazyVim changes | Editor content is the user's; this feature only makes the pane env sane |
| tmux-style pane tooling | herdr already hosts panes (AD-001) |
| `/usr/share/doc` or locale restoration | Size trade recorded in AD-…/less-man-pages; man only |
## User Stories

### P0: nvim opens inside a herdr pane with the full toolchain env

**User story:** As the box operator, I want to open nvim inside a herdr pane
(over ssh from my phone or Mac) and have it behave exactly like an ssh login
shell, because herdr is my primary session host.

**Why P0:** The box exists for phone-friendly editing; herdr is the pane host
(AD-001); a pane missing the toolchain env and a sane TERM defeats the box.

### P0: `man pthread` renders C documentation on the box

**User story:** As a box user writing C, I want `man pthread` and `man 3 printf`
to render reference material, because the box is a general dev box and the man
pages for the C library are part of that.

**Why P0:** The less/man-pages feature restored sections 1/5/7 only; C
programmers hit the gap on first `man pthread`.

## Requirement Traceability

| Req | Verification (deterministic) | Runtime check (on-box, post-deploy) |
| --- | ---------------------------- | ----------------------------------- |
| AC-01 | `scripts/validate-herdr-panes.py` HDP-02 (entrypoint writes `[terminal] shell_mode=login`) | `herdr` attach → `type bash; echo $PI_CLOUD $PATH` in a new pane |
| AC-02 | `scripts/validate-herdr-panes.py` HDP-01/HDP-03 (TERM fallback in entrypoint + profile.d) | new pane → `echo ${TERM:-EMPTY}` non-empty |
| AC-03 | `scripts/validate-c-man-pages.py` CMP-03 (tag sync in both workflows) + `scripts/validate-toolchain.py` TCH-02/03 | workflow diff on PR |
| AC-04 | `scripts/validate-c-man-pages.py` CMP-02 (packages present) + focused image gate: `man -w pthread` | box → `man pthread` renders |
| AC-05 | same as AC-04 (CMP-02 package set) | box → `man 3 printf` renders |
| AC-06 | `scripts/validate-herdr-panes.py` HDP-04 (guard keeps existing `[terminal]` untouched) | second boot: config file unchanged |
