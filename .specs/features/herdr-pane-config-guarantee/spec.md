# herdr pane login-shell config guarantee

## Problem Statement

`herdr-panes-and-c-manpages` pinned `[terminal] default_shell = "/bin/bash"` and
`shell_mode = "login"` in `~/.config/herdr/config.toml`, but only when that file
had no `[terminal]` section (AC-07 of that spec). The box's PVC config already
carried `[terminal] default_shell = "bash"` from before that feature, so the pin
never ran. herdr kept `shell_mode = "auto"`, which spawns non-login shells on
Linux, and every pane skipped `/etc/profile.d/pi-cloud.sh`: no `/opt/nvim/bin`
on PATH (`nvim: command not found`), no `PI_CLOUD=1`, no sealed-key exports.

Confirmed live on 2026-10-15 in pane `w18:p4`: pane `PATH` was sshd's minimal
`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`,
`command -v nvim` was empty, while an ssh login shell resolved
`/opt/nvim/bin/nvim` with `PI_CLOUD=1`. The all-or-nothing guard makes the pin
unreachable on any box whose config predates the feature, which is permanent
state on the PVC.

## Goals

- [ ] Every boot guarantees both required `[terminal]` keys whatever the config
      file already contains, before the herdr server starts.
- [ ] The guarantee never corrupts, reorders, or drops unrelated config; it
      refuses an unsafe layout instead of guessing.
- [ ] A deterministic behavioral gate exercises the guarantee against fixture
      configs, and runs where the artifact runs (the box ships no python3, so the
      gate is bash + awk + coreutils).

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Changing herdr, its config schema, or its `shell_mode` default | Upstream behavior is fixed; the box provisions config |
| Restarting or reloading a running herdr server from the entrypoint | The guarantee runs before the server starts at boot; a live server is the operator's call (documented remediation) |
| Migrating existing panes to login shells | herdr resolves the shell when a pane is created; existing panes keep their env. Create a new pane |
| `/etc/profile.d/pi-cloud.sh` content or the `TERM` fallback | Unchanged from `herdr-panes-and-c-manpages` |
| Installing python3 on the box | Not needed: the guarantee and its gate run on POSIX shell tooling (bash, awk, coreutils) |
| General TOML editing of the herdr config | Only the two required keys are owned; everything else is the user's |

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Ownership of `[terminal].default_shell` and `[terminal].shell_mode` | The box forces both to the required values and logs every override | The invariant (pane env matches an ssh login shell) is a box contract, not a preference; an explicit `non_login` reintroduces the reported bug silently | yes |
| Relation to AC-07 of `herdr-panes-and-c-manpages` | Superseded: a targeted per-key guarantee replaces the coarse "skip when `[terminal]` exists" rule | AC-07 made the pin unreachable exactly on boxes that already had a config, which is this box | yes |
| Unsafe config layouts (root-level `terminal.shell_mode`/`terminal.default_shell` dotted keys, duplicate `[terminal]` sections) | Refuse: leave the file untouched, exit non-zero, warn, keep booting | Both layouts would risk a duplicate TOML key if edited mechanically, and a duplicate key breaks the config herdr already reads | yes |
| Backup of the previous config on every change | `<config>.bak-pi-cloud`, overwritten on each change | Bounded file count; mirrors herdr's own `.bak-*` convention from `config reset-keys` | yes |
| Line endings | Match a trailing CR, rewrite only the touched lines with the file's own line ending | A CRLF config must not be read as "no `[terminal]` section", which would append a duplicate section | yes |
| Gate language for the behavioral fixtures | Bash (`scripts/validate-herdr-pane-config.sh`) | The box image ships no python3, and this behavior must be reproducible on the box; the existing python gate keeps the repo-wiring checks and delegates behavior. The gate's real floor is bash, awk, grep, sed, diff and coreutils, all present in the image | yes |
| Failing guaranteed keys block boot | No: the entrypoint logs and continues | sshd must come up on a box with a broken config so the operator can repair it | yes |
| On-box remediation of an already-running server | Operator runs the helper, then `herdr server reload-config`, then opens a new pane; recorded in TROUBLESHOOTING 13 | The entrypoint cannot retroactively fix a server it did not start | yes |

**Open questions:** none.

## User Stories

### P1: New herdr panes carry the ssh login-shell environment ⭐ MVP

**User Story**: As the box operator, I want a new herdr pane to source the same
environment as an ssh login shell, so that `nvim`, the Ruby toolchain,
`PI_CLOUD`, and the sealed keys are present when I work from my phone or Mac.

**Why P1**: This is the reported failure. herdr is the box's primary session
host, so a pane without the login-shell env defeats the box.

**Acceptance Criteria** (each line is one EARS pattern):

1. WHEN the entrypoint starts the herdr server THEN the box SHALL guarantee `default_shell = "/bin/bash"` and `shell_mode = "login"` in the `[terminal]` section of `~/.config/herdr/config.toml` before the server starts.
2. IF the herdr config already declares a `[terminal]` section THEN the box SHALL insert only the required keys that are missing or non-conforming and SHALL leave every other line byte-identical.
3. IF the two required keys already hold the required values THEN the box SHALL leave the config file byte-identical and SHALL NOT rewrite it.
4. IF the herdr config declares no `[terminal]` section THEN the box SHALL append a `[terminal]` section carrying both required keys.
5. IF the required keys appear outside a `[terminal]` section as root-level `terminal.*` dotted keys THEN the box SHALL leave the file untouched and exit non-zero.
6. IF the herdr config declares more than one `[terminal]` section THEN the box SHALL leave the file untouched and exit non-zero.
7. IF the config guarantee exits non-zero THEN the entrypoint SHALL continue booting and SHALL log the failure.
8. WHEN the config guarantee modifies the file THEN the box SHALL keep the previous content at `<config>.bak-pi-cloud`.
9. WHEN a new herdr pane opens THEN its shell SHALL be a bash login shell that sources `/etc/profile.d/pi-cloud.sh`, so `nvim` resolves as in an ssh login shell.
10. The config guarantee SHALL run with the box's POSIX shell tooling (bash, awk, coreutils) and SHALL NOT require python3.

**Independent Test**: Run the helper against a fixture config copied from the
live box (`[terminal]` with `default_shell = "bash"` and no `shell_mode`), then
open a new herdr pane and run `command -v nvim` and `echo $PI_CLOUD`.

---

### P1: The guarantee is gated deterministically ⭐ MVP

**User Story**: As the maintainer, I want a gate that exercises the guarantee
against fixture configs, so that a regression fails a command instead of the box.

**Why P1**: The previous feature's gate asserted the wrong behavior
("existing `[terminal]` untouched") and passed while the box was broken.

**Acceptance Criteria**:

1. WHEN the behavioral gate runs THEN it SHALL exercise the guarantee against fixtures covering both required keys, byte-preservation of unrelated config, and both refusal paths.
2. IF any fixture assertion fails THEN the gate SHALL exit non-zero.
3. The behavioral gate SHALL run with the box's POSIX shell tooling (bash, awk, grep, sed, diff, coreutils) and SHALL NOT require python3.
4. The repo gate SHALL fail if the entrypoint stops invoking the guarantee before the herdr server starts.

**Independent Test**: Run `bash scripts/validate-herdr-pane-config.sh` on the box
and `python3 scripts/validate-herdr-panes.py` where python3 exists; both exit 0.

---

### P2: The troubleshooting record matches the mechanism

**User Story**: As the box operator, I want `docs/TROUBLESHOOTING.md` to name the
real cause, so that the next occurrence of this failure class is a one-minute fix.

**Why P2**: The current entry documents the pre-`[terminal]` guard that never ran
on this box, and its workaround (`. /etc/profile.d/pi-cloud.sh`) leaves the pane
in a non-login shell.

**Acceptance Criteria**:

1. WHEN the operator reads `docs/TROUBLESHOOTING.md` section 13 THEN the entry SHALL state the pre-existing-`[terminal]` root cause and the on-box remediation (`herdr-pane-config`, `herdr server reload-config`, then a new pane).
2. WHEN a new pane is created after the remediation THEN the entry SHALL tell the operator that existing panes keep their old environment.

**Independent Test**: Read section 13 and follow the remediation on the box.

---

## Edge Cases

- IF the config file is missing THEN the box SHALL create it with the `[terminal]` section and both keys.
- IF the config file is empty THEN the box SHALL write the `[terminal]` section with both keys.
- IF the config declares `shell_mode` in a different table (for example `[ui]`) THEN the box SHALL leave that line untouched.
- IF the config's `[terminal]` section is the last line and has no trailing newline THEN the box SHALL still repair it and exit zero.
- IF the config cannot be written THEN the box SHALL leave any existing content untouched, exit non-zero, and keep booting.
- IF a required key holds a comment on the same line (for example `shell_mode = "auto" # legacy`) THEN the box SHALL replace the whole line with the required key.

## Requirement Traceability

| Requirement ID | Story | Verification (deterministic) | Runtime check (on-box, post-deploy) | Status |
| -------------- | ----- | ---------------------------- | ----------------------------------- | ------ |
| HPC-01 | P1: pane env | `scripts/validate-herdr-panes.py` HDP-02 (entrypoint invokes the guarantee before `setsid herdr server`) | new pane → `echo $PATH` contains `/opt/nvim/bin` | Verified |
| HPC-02 | P1: pane env | gate checks `HPC-02 pre-existing [terminal] gains shell_mode=login and default_shell=/bin/bash`, `HPC-02 unrelated sections stay byte-identical`, `HPC-02 auto/non-login values forced to login, sibling keys kept`, `HPC-02 single-quoted non-conforming value is forced to login` | diff of `~/.config/herdr/config.toml` after a boot | Verified |
| HPC-03 | P1: pane env | gate checks `HPC-03 compliant config is not rewritten`, `HPC-03 compliant config writes no backup`, `HPC-03 key order of a compliant config is preserved`, `HPC-03 single-quoted but compliant values are preserved` (all md5-based) | config mtime unchanged across a second boot | Verified |
| HPC-04 | P1: pane env | gate checks `HPC-04 missing config created with both keys`, `HPC-04 empty config gains [terminal] with both keys`, `HPC-04 unrelated-only config appends [terminal] and keeps its lines` | first boot on a fresh PVC | Verified |
| HPC-05 | P1: pane env | gate check `HPC-05 root-level terminal.* dotted keys refused untouched` (non-zero exit plus `cmp` of the fixture) | not applicable (operator repairs by hand) | Verified |
| HPC-06 | P1: pane env | gate check `HPC-06 duplicate [terminal] refused untouched` (non-zero exit plus `cmp` of the fixture) | not applicable (operator repairs by hand) | Verified |
| HPC-07 | P1: pane env | `scripts/validate-herdr-panes.py` HDP-02 (entrypoint call is guarded, boot continues) | boot with a refused config → sshd still accepts | Verified |
| HPC-08 | P1: pane env | gate check `HPC-08 previous content kept at <config>.bak-pi-cloud` (backup compared byte for byte with the pre-change fixture) | `~/.config/herdr/config.toml.bak-pi-cloud` present after a repair | Verified |
| HPC-09 | P1: pane env | `scripts/validate-herdr-pane-config.sh` gate assertions: `grep -q '/opt/nvim/bin' container/profile.d/pi-cloud.sh` plus the `shell_mode = "login"` key assertions (the two facts that make a pane a login shell with the toolchain on PATH) | new pane → `command -v nvim` and `echo $PI_CLOUD` | Verified |
| HPC-10 | P1: pane env | `scripts/validate-herdr-pane-config.sh` assertion: the helper contains no python/node/ruby invocation; runs on the box | helper runs on the box | Verified |
| HPC-11 | P1: gate | `scripts/validate-herdr-pane-config.sh` exits 0 with all fixture assertions | run the gate on the box | Verified |
| HPC-12 | P1: gate | gate self-check: injected fault makes the gate exit non-zero | not applicable | Verified |
| HPC-13 | P1: gate | gate uses bash, awk, grep, sed, diff, cmp, tr, md5sum and cut, with the python3 TOML parse check optional and its guard asserted in-gate | `bash scripts/validate-herdr-pane-config.sh` on the box | Verified |
| HPC-14 | P2: docs | `scripts/validate-herdr-panes.py` HDP-05 (TROUBLESHOOTING 13 names herdr, `shell_mode`, login, and the remediation command) | read section 13 | Verified |
| HPC-15 | P1: gate | `scripts/validate-herdr-panes.py` HDP-02 (gate asserts the entrypoint call order) | not applicable | Verified |

**Coverage:** 15 total, 15 mapped to gate assertions, 0 unmapped.

## Success Criteria

- [ ] A fresh boot on a box whose PVC config already has `[terminal]` produces
      login-shell panes: `nvim` opens inside a new pane over ssh.
- [ ] A compliant config is never rewritten (mtime and bytes stable across boots).
- [ ] The behavioral gate exits zero on the box and non-zero when the helper's
      required-key logic is broken.
