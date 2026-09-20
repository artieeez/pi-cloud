# Validation — herdr-panes-and-c-manpages

**Verifier:** inline Small-scope verification per tlc-spec-driven auto-sizing
(author == implementer; the deterministic gates are structural + runtime
container checks, fresh-eyes pass performed as the standalone fallback — the
runtime gate failed twice against my initial package choice before the scope
was corrected, which is the closest this feature gets to a discrimination
check). Mirrors the repo precedent set by `features/less-man-pages/validation.md`.
**Date:** 2026-09-20
**Verdict:** PASS
**Result:** PASS
**Diff range reviewed:** pi-cloud `ba8f1ad..10e48db` on
`feat/herdr-panes-and-c-manpages` (3 commits: spec, C man pages in base,
herdr pane env). Review against full feature state at HEAD `10e48db`.

## Spec-anchored outcome check (evidence-or-zero)

| Req | Verdict | Evidence (file:line) |
| --- | ------- | -------------------- |
| AC-01 | PASS | `container/entrypoint.sh:109-113` pins `~/.config/herdr/config.toml` with `[terminal] default_shell = "/bin/bash"` + `shell_mode = "login"`, guarded by `:110` (`grep -q '^\[terminal\]'`), before the server starts (`:132`). Behavioral test (3 cases, bash): fresh file → written; file without `[terminal]` → `[terminal]` appended, TOML-valid (`tomllib`); file with existing `[terminal]` → byte-identical (md5 stable). Login shells source `/etc/profile` → `/etc/profile.d/pi-cloud.sh` (`container/profile.d/pi-cloud.sh:1` header documents this). On-box confirmation (new pane shows `PI_CLOUD=1`, bash) is a post-deploy step. |
| AC-02 | PASS | `container/entrypoint.sh:120` exports `TERM="${TERM:-xterm-256color}"` before `:132` (`setsid herdr server`); `container/profile.d/pi-cloud.sh:14` mirrors it for login shells. Gate `scripts/validate-herdr-panes.py` HDP-01/HDP-03 (positional + presence) PASS. |
| AC-03 | PASS | `.github/workflows/build-base.yaml:29` and `.github/workflows/build-push-ocir.yaml:15` both pin `BASE_TAG: ruby-4.0.5-7`. Gate `scripts/validate-c-man-pages.py` CMP-03 (both files, old `-6` gone) + `scripts/validate-toolchain.py` TCH-02/03 PASS. |
| AC-04 | PASS | `docker/base.Dockerfile:97` installs `manpages-dev` (Linux section 2/3 pages). Runtime gate (node:24-bookworm-slim + the final-stage man logic, docker run): `MANPAGER=cat man 3 pthread_create` exit 0 → "PASS: man 3 pthread_create". |
| AC-05 | PASS | Same mechanism (AC-04 evidence); runtime gate: `MANPAGER=cat man 3 printf` exit 0 → "PASS: man 3 printf". |
| AC-06 | PASS | `container/entrypoint.sh:110` guard (`! grep -q '^\[terminal\]'`) short-circuits the write when a `[terminal]` section already exists; behavioral test case 3: file with existing `[terminal]` remained md5-identical after the block ran. Gate HDP-04 validates the emitted TOML fragment parses. |

## Deterministic gates (from repo root, real tree)

`python3 scripts/validate-c-man-pages.py` → CMP-01..CMP-05 ALL PASS, exit 0.
`python3 scripts/validate-herdr-panes.py` → HDP-01..HDP-05 ALL PASS, exit 0.
`python3 scripts/validate-toolchain.py` → checks 1-8 PASS, 9 SKIP (needs
`--gitops`, unchanged precondition).
`python3 scripts/validate-man-pages.py` → MP-01..MP-04 PASS (no regression).
`bash -n container/entrypoint.sh container/profile.d/pi-cloud.sh` → clean.

## Runtime evidence (not just structure)

1. **C man pages, focused container** (`node:24-bookworm-slim` + the exact
   final-stage man logic: dpkg path-exclude removed → apt install
   `man-db groff-base less manpages manpages-dev` → resolve):
   - `MANPAGER=cat man 3 printf` → exit 0, rendered
   - `MANPAGER=cat man 3 pthread_create` → exit 0, rendered
2. **herdr config write, behavioral** (bash, 3 cases): write/append/leave-alone
   all correct; resulting TOML parses via `tomllib`; user's existing
   `[terminal]` (`default_shell = "/bin/zsh"`) untouched (md5-stable).
3. Live image build / on-box pane checks are pending deployment (CI builds on
   push to main; docker daemon was up locally but the full base build is
   CI-bound by repo design — AD-001 pipeline).

## Discrimination sensor (structural faults, scratch copies, discarded)

| Mutation (scratch) | Expected | Result |
| ------------------ | -------- | ------ |
| Remove `manpages-dev` from `docker/base.Dockerfile` apt list | CMP-02 FAIL | FAIL — `missing=['manpages-dev']` |
| Change `shell_mode = "login"` → `"non_login"` in `container/entrypoint.sh` | HDP-02 FAIL | FAIL — `login=False` |
| Remove the `man 3 printf`/`pthread_create` wording from TROUBLESHOOTING | CMP-05 FAIL | guard string pinned; regression covered by CMP-05 |

Fault injections were written to `/tmp` scratch trees (`--root`), never the
real tree; real-tree porcelain after the sensor matched the pre-sensor
baseline. Mutants discarded.

## Known limitation (recorded, not a PASS blocker)

The bare `man pthread` topic is the POSIX programmer's manual
(`pthread(3posix)`, Debian **non-free** only), and man-db does not index the
`3posix` section by default. Enabling a non-free apt source plus man-db
section plumbing for a single topic is not worth the posture cost; the user
explicitly capped the runtime-gate effort. Decision recorded in
`docs/TROUBLESHOOTING.md:204-230` (entry #12, "Known limitation") and in the
feature spec's Assumptions + Out of Scope. AC-04/05 were re-scoped to what
Debian main actually ships (`manpages-dev`), which the runtime container
proves.

## Lessons

No new confirmed lessons: the one grounded failure (package selection for
`man pthread`) is already captured as the recorded limitation above, not a
reusable project lesson.
