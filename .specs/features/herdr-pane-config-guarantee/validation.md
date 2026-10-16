# herdr-pane-config-guarantee Validation

**Date**: 2026-10-15 (re-verification pass 3, final)
**Spec**: `.specs/features/herdr-pane-config-guarantee/spec.md`
**Diff range**: `git diff main...HEAD` = `5de3f72`, `dc453f8`, `2993e30`, `cbaa2fd`, `1524383`, `dd99ef8` (spec; helper, entrypoint, Dockerfile, behavioral gate; structural gate, docs, STATE, superseded spec; quote-agnostic value comparison + single-quote fixtures; spec AC-10 and gate AC wording; comment-safe value extraction + 24-check gate + traceability cells naming real check labels)
**Verifier**: independent sub-agent (author != verifier), read-only over the real tree

---

## Task Completion

No `tasks.md` exists for this feature (spec-only, Medium scope per `.specs/STATE.md`). Completion is assessed against the six shipped commits and the spec's story set.

| Work item | Status | Notes |
| --------- | ------ | ----- |
| `5de3f72` spec HPC-01..HPC-15 | Done | `validate_spec.py` exits 0, 0 errors / 0 warnings |
| `dc453f8` helper `container/herdr-pane-config.sh` | Done | bash + awk + coreutils, no python3 |
| `dc453f8` entrypoint wiring | Done | `container/entrypoint.sh:111` guarded call before `container/entrypoint.sh:132` server start |
| `dc453f8` Dockerfile install | Done | `Dockerfile:95-96` copies + chmod +x `/usr/local/bin/herdr-pane-config` |
| `dc453f8` behavioral gate | Done | `scripts/validate-herdr-pane-config.sh`, exit 0 |
| `2993e30` structural gate retarget | Done | `scripts/validate-herdr-panes.py` HDP-01..HDP-06, exit 0 |
| `2993e30` docs / STATE / supersede AC-07 | Done | section 13 rewritten; AC-07 of the prior feature marked superseded |
| `cbaa2fd` single-quote fix | Done | both `value_of` programs strip surrounding single or double quotes; gate gains `run_single_quoted` (22 checks total) |
| `1524383` spec wording | Done | AC-10 / gate AC -> POSIX shell tooling; HPC-09 cell cites real gate assertions; HPC-13 cell states the real floor; all fifteen rows Verified; STATE records the on-box runtime |
| `dd99ef8` comment-safe value extraction | Done | `value_of` in both awk programs (`container/herdr-pane-config.sh:61-74`, `:136-149`) stops at the closing quote, so a comment after the closing quote no longer breaks equality; gate gains `run_commented_values` (24 checks); the six traceability cells name real check labels |
| Runtime repair of the live box | Parent-reported | config repair re-derived read-only; pane env parent-reported, see Runtime Evidence |

---

## Re-verification pass 2

The prior pass returned PASS with three spec-precision gaps (G1, G2, G3). This pass re-derived all evidence at HEAD `1524383`; gate and sensor results below are from this pass.

- Baseline `git status --porcelain`: three pre-existing untracked artifacts (`?? .specs/LESSONS.md`, `?? .specs/lessons.json`, `?? .specs/features/herdr-pane-config-guarantee/validation.md`). Identical after the sensor. No staged files.
- Behavioral gate: `bash scripts/validate-herdr-pane-config.sh` -> 22 passed, 0 failed, exit 0.
- Structural gate: `python3 scripts/validate-herdr-panes.py` -> HDP-01..HDP-06 PASS, exit 0.

### Gap resolution

| Gap | Status | Evidence |
| --- | ------ | -------- |
| G1 single-quoted compliant config must not be rewritten | Resolved | Scratch helper run: a single-quoted compliant config is byte-identical (`md5 3ca0646d...` unchanged, "already guaranteed ... no change"); a single-quoted `'non_login'` is forced to canonical `"login"`. Sensor mutant R4 breaks single-quote stripping only and is killed by the new gate check `scripts/validate-herdr-pane-config.sh:124`. |
| G2 every traceability cell points at a real assertion | Resolved (core) | HPC-09's cell now cites `scripts/validate-herdr-pane-config.sh:197-198` (`grep -q '/opt/nvim/bin'`) plus the `shell_mode = "login"` key checks at `scripts/validate-herdr-pane-config.sh:93`; the runtime-only pane claim sits in the spec's "Runtime check (on-box, post-deploy)" column, not as a gate assertion. Residual N2 below. |
| G3 stated dependency floor matches invoked tooling | Resolved (core) | The helper invokes only bash builtins, awk and coreutils (`container/herdr-pane-config.sh:26-27`, `:198-244`). The gate AC-3 and the assumptions table now state `bash, awk, grep, sed, diff, coreutils`, which matches the gate's real commands (`tr`, `grep`, `sed`, `diff`, `md5sum`, `mktemp`, `cmp`, `rm`). Residual N3 below. |

---

## Re-verification pass 3 (final)

Pass 2 returned PASS with three residuals (N2 stale `F<n>` traceability tokens, N3 abbreviated dependency floor, N4 no-space-comment byte-identity). Commit `dd99ef8` addresses all three. This pass re-derived every result at HEAD `dd99ef8` from scratch; it did not write the implementation.

- Baseline `git status --porcelain`: three pre-existing untracked artifacts (`?? .specs/LESSONS.md`, `?? .specs/lessons.json`, `?? .specs/features/herdr-pane-config-guarantee/validation.md`). Identical after the discrimination sensor. No staged files.
- Behavioral gate: `bash scripts/validate-herdr-pane-config.sh` -> **24 passed, 0 failed**, exit 0.
- Structural gate: `python3 scripts/validate-herdr-panes.py` -> HDP-01..HDP-06 PASS, exit 0.

### Residual resolution (N2, N3, N4)

| Residual | Status | Evidence (re-derived this pass) |
| -------- | ------ | ------------------------------- |
| N2 no traceability cell may cite a gate identifier that does not exist | Resolved | `grep -nE '\bF[0-9]+\b' spec.md` returns nothing. Every backticked gate identifier in the traceability table matched exactly one label the gate actually emits: 34 backtick spans scanned, 0 unmatched `HPC-*` / `edge:` labels (all 24 real labels checked against the table). The six former cells now read the real labels, e.g. `HPC-02 unrelated sections stay byte-identical`, `HPC-03 compliant config is not rewritten`, `HPC-04 missing config created with both keys`, `HPC-05 root-level terminal.* dotted keys refused untouched`, `HPC-08 previous content kept at <config>.bak-pi-cloud` (`spec.md:133-150`). |
| N3 stated dependency floor must equal the commands actually invoked | Resolved | The HPC-13 cell now reads `bash, awk, grep, sed, diff, cmp, tr, md5sum and cut` (`spec.md:149`); every named tool is genuinely invoked by the gate (`grep`, `sed`, `diff`, `tr`, `md5sum`, `cut`, `cmp`, `awk`, `bash` - see the gate's `grep`/`sed`/`diff`/`tr`/`md5sum`/`cut`/`cmp`/`awk` uses). The gate AC-3 and the assumptions table state `bash, awk, grep, sed, diff, coreutils` (`spec.md:98`, `:50`), and the remaining invocations (`mktemp`, `rm`, `cp`, `dirname`) are coreutils. The helper floor `bash, awk, coreutils` (`spec.md:78`) matches the helper (`awk`, `dirname`, `mkdir`, `mktemp`, `chmod`, `mv`, `cp`, `cmp`, `rm`, `cat` - all coreutils or the bash builtin `printf`). No phantom dependency and no unnamed non-coreutils dependency. |
| N4 compliant no-space comment must not be rewritten, commented non-conforming must still be forced | Resolved | Gate pair `run_commented_values` (`scripts/validate-herdr-pane-config.sh:132-144`): compliant `default_shell = "/bin/bash"# legacy` + `shell_mode = "login" # legacy` is byte-identical (`:137` md5 check), and non-conforming `default_shell = "bash" # legacy` + `shell_mode = "auto"# legacy` is forced (`:142`). Re-derived with the real helper outside the gate: the no-space compliant file's md5 is unchanged (`3afce1ffd19ea05c5d807e536aad99f4` before and after), the mixed space/no-space compliant file is unchanged, and the no-space non-conforming file is forced to `default_shell = "/bin/bash"` / `shell_mode = "login"` and re-parses via tomllib as `{'default_shell': '/bin/bash', 'shell_mode': 'login'}`. The quote-stop logic is `container/herdr-pane-config.sh:64-71` (analyze) and `:139-146` (emit). |

No hard gap (a failed acceptance criterion) and no surviving discriminating mutant were found. The single surviving sensor mutation (M3) is behaviorally equivalent to the shipped code, see the Discrimination Sensor section.

---

## Spec-Anchored Acceptance Criteria

Evidence-or-zero: every row cites `file:line` + the asserted expression. A row without a citation would count as not covered.

| Requirement (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion expression | Result |
| --------------------------- | -------------------- | ---------------------------------- | ------ |
| HPC-01 entrypoint starts server then guarantee ran first | `default_shell = "/bin/bash"` and `shell_mode = "login"` in `[terminal]` of `~/.config/herdr/config.toml`, set before the server starts | `container/entrypoint.sh:111` call vs `container/entrypoint.sh:132` server start; asserted `scripts/validate-herdr-panes.py:70` `hdp02 = (call_at >= 0 and guarded and coarse_guard_gone and (server_at < 0 or call_at < server_at))` | PASS |
| HPC-02 existing `[terminal]` | insert only missing or non-conforming keys; every other line byte-identical | `scripts/validate-herdr-pane-config.sh:93` pre-existing `[terminal]` gains `shell_mode=login` and `default_shell=/bin/bash`; `:95-96` `diff -q <(sed -n '/^\[theme\]/,$p' before) <(sed -n '/^\[theme\]/,$p' f)`; `:128` single-quoted `'non_login'` forced; `:142` commented `"auto"# legacy` forced; `:151` `"auto"` / `"bash"` forced | PASS |
| HPC-03 both keys already required | byte-identical file; no rewrite | `scripts/validate-herdr-pane-config.sh:107` `[ "$before" = "$(md5 "$f")" ]`; `:108` `[ -f "${f}.bak-pi-cloud" ]` must be false; `:116` reordered-key md5 unchanged; `:124` single-quoted compliant md5 unchanged; `:137` compliant values with trailing comments (space and no-space) md5 unchanged | PASS (G1, N4 resolved) |
| HPC-04 no `[terminal]` | append `[terminal]` with both keys (missing, empty, unrelated-only) | `scripts/validate-herdr-pane-config.sh:67` missing; `:75` empty; `:83` unrelated-only keeps `onboarding` and `[theme]` lines | PASS |
| HPC-05 root-level `terminal.*` dotted keys | file untouched, exit non-zero | `scripts/validate-herdr-pane-config.sh:176` `unchanged` in the non-zero branch; helper `container/herdr-pane-config.sh:217` `die "refusing ... terminal.* dotted keys ..."` | PASS |
| HPC-06 duplicate `[terminal]` | file untouched, exit non-zero | `scripts/validate-herdr-pane-config.sh:164` `unchanged "${f}" "${before}"`; helper `container/herdr-pane-config.sh:216` `die "refusing to edit ... ${sections} [terminal] sections declared"` | PASS |
| HPC-07 guarantee exits non-zero | entrypoint continues booting and logs the failure | `container/entrypoint.sh:111-115` `if herdr-pane-config ...; then log ... else log "WARNING: herdr config guarantee failed ..."; fi`; asserted `scripts/validate-herdr-panes.py:67` `guarded = ("if herdr-pane-config" in ep and "WARNING: herdr config guarantee failed" in ep)` | PASS |
| HPC-08 guarantee modifies file | previous content kept at `<config>.bak-pi-cloud` | `scripts/validate-herdr-pane-config.sh:97` `[ -f "${f}.bak-pi-cloud" ] && unchanged "${before}" "${f}.bak-pi-cloud"`; helper `container/herdr-pane-config.sh:247` `cp -p "${target}" "${target}.bak-pi-cloud"` | PASS |
| HPC-09 new pane login shell sources profile.d | bash login shell, `/etc/profile.d/pi-cloud.sh` sourced, `nvim` resolves as ssh login | deterministic proxy `scripts/validate-herdr-pane-config.sh:211-212` `grep -q '/opt/nvim/bin' "${PROFILE}"`; `container/profile.d/pi-cloud.sh:7` `export PATH="/opt/nvim/bin:...`; the `shell_mode = "login"` key assertions at `scripts/validate-herdr-pane-config.sh:93` | PASS (deterministic proxy); runtime half parent-reported |
| HPC-10 helper POSIX shell tooling, no python3 | no python3 dependency in the helper | `scripts/validate-herdr-pane-config.sh:55-58` greps the helper for `python3`, `python`, `node`, `npx`, `ruby` and fails if any is invoked; none found | PASS |
| HPC-11 behavioral gate all fixtures | exit 0 when all assertions pass | `scripts/validate-herdr-pane-config.sh:249` guards on `[ "${failed}" = "0" ]` then exits 1 on any failure; observed summary `validate-herdr-pane-config: 24 passed, 0 failed` with exit 0 | PASS |
| HPC-12 injected fault | gate exits non-zero | discrimination sensor below: 12 behavior-level mutations across three passes; 11 are real regressions and each made the gate exit non-zero (11/11 killed), the 12th (M3) is behaviorally equivalent to the shipped code and passes by design; no in-repo self-test exists, so this AC is sensor-backed | PASS |
| HPC-13 gate POSIX shell tooling, python3 optional | runs on the box with no python3 dependency | `scripts/validate-herdr-pane-config.sh:60-61` `grep -q 'if command -v python3' "${GATE}"`; the tomllib block at `:220-238` is guarded by `command -v python3` | PASS (G3, N2, N3 resolved) |
| HPC-14 docs section 13 | names the root cause and the remediation command | `scripts/validate-herdr-panes.py:99-100` `needed = ["herdr","shell_mode","login","herdr-pane-config","reload-config"]; not missing`; `docs/TROUBLESHOOTING.md:174` header, `:180` cause, `:203-205` remediation | PASS (see note N1) |
| HPC-15 repo gate fails if entrypoint drops the call | gate fails when the guarantee call or its order is removed | `scripts/validate-herdr-panes.py:70` `hdp02` requires `call_at >= 0 and guarded and call_at < server_at` | PASS |

**Status**: 15/15 requirements have assertion-backed evidence; G1, G2, G3 and the pass-2 residuals N2, N3, N4 resolved; 0 hard gaps, 0 surviving discriminating mutants.

---

## Discrimination Sensor

Sensor depth: P0-style targeted fault injection on the highest-risk new code (the helper). Scratch worktree only, real tree never mutated.

This pass re-ran the sensor on the changed comparison code at HEAD `1524383`: baseline `git status --porcelain` captured, `git worktree add /tmp/verify-herdr-scratch2 HEAD` (detached at `1524383`), each mutant patched the scratch copy of `container/herdr-pane-config.sh`, gate run as `bash /tmp/verify-herdr-scratch2/scripts/validate-herdr-pane-config.sh --root /tmp/verify-herdr-scratch2`, scratch copy reset to pristine after each. Worktree removed with `git worktree remove --force`; post-sensor porcelain equals the baseline. `git stash` was never used.

Pass 3 repeated the same procedure at HEAD `dd99ef8` with `git worktree add /tmp/verify-herdr-scratch3 HEAD` and gate run as `bash /tmp/verify-herdr-scratch3/scripts/validate-herdr-pane-config.sh --root /tmp/verify-herdr-scratch3`; the scratch copy was reset with `git checkout --` after each mutant, the worktree was removed with `git worktree remove --force`, and post-sensor porcelain equals the baseline. Rows `M1`/`M2`/`M3` below are from pass 3; the rows above them are the pass-1/pass-2 history.

| Mutation | Target file:line | Injected fault | Gate kill signature (exit 1) | Killed? |
| -------- | ---------------- | -------------- | ---------------------------- | ------- |
| Prior A | `container/herdr-pane-config.sh:27` | `REQ_SHELL_MODE='login'` -> `'non_login'` | 12 failing checks incl. HPC-02 and HPC-04 | Killed |
| Prior B | `container/herdr-pane-config.sh:159` | emit leaves a present-but-wrong value alone (`value_of(line) == sm` -> keep) | 2 failing incl. HPC-02 forced and TOML parse | Killed |
| Prior C | `container/herdr-pane-config.sh:210` | duplicate-`[terminal]` refusal returns 0 (`die` -> log, return 0) | 1 failing: HPC-06 duplicate `[terminal]` refused | Killed |
| Prior D | `container/herdr-pane-config.sh:241` | drop the `.bak-pi-cloud` backup `cp` | 1 failing: HPC-08 previous content kept | Killed |
| Prior E | `container/herdr-pane-config.sh:152-153` | force both header insertions unconditionally, creating duplicate keys | 6 failing incl. HPC-02, CRLF and TOML parse | Killed |
| R1 re-verify | `container/herdr-pane-config.sh:68,140` | `value_of` stops stripping surrounding quotes (the strip condition never fires, both programs) | 11 failing checks incl. HPC-03 / HPC-04 repair and TOML parse | Killed |
| R2 re-verify | `container/herdr-pane-config.sh:159,163` | emit value comparison forced always true, so a present-but-wrong value is kept | 7 failing incl. HPC-02 forced, HPC-08 and TOML parse | Killed |
| R3 re-verify | `container/herdr-pane-config.sh:159,163` | emit prints the canonical line from the bare value `ds` / `sm` instead of the TOML literal `ds_toml` / `sm_toml` | 7 failing incl. key_count quote match and TOML parse | Killed |
| R4 re-verify | `container/herdr-pane-config.sh:68,140` | break single-quote stripping only (keep double-quote stripping) | exactly 1 failing: `scripts/validate-herdr-pane-config.sh:124` HPC-03 single-quoted but compliant values are preserved | Killed |
| M1 pass 3 | `container/herdr-pane-config.sh:61-74,136-149` | revert `value_of` to the pre-`dd99ef8` form: strip a `[[:space:]]+#` comment before the closing-quote scan and trim quotes by first/last char | exactly 1 failing: `scripts/validate-herdr-pane-config.sh:137` HPC-03 compliant values with trailing comments are preserved (the no-space form is rewritten) | Killed |
| M2 pass 3 | `container/herdr-pane-config.sh:64-71,139-146` | make the quote branch return the whole trimmed value (`return v`) instead of the substring up to the closing quote | 12 failing incl. HPC-04, HPC-02 pre-existing/forced/commented, HPC-08 and the TOML parse check (the helper then refuses to write and exits 1) | Killed |
| M3 pass 3 | `container/herdr-pane-config.sh:63,138` | strip a comment only when a space precedes the hash (`sub(/[[:space:]]+#.*$/...)`) before the quote scan | 24 passed, 0 failed, exit 0 | Survived (equivalent) |

**Sensor depth**: P0/lightweight targeted fault injection
**Result**: 12 mutations injected across three passes, 11 killed, 1 survived (equivalent) - PASS

R4 is the precise G1 sensor: it is killed only by the fixture added in `cbaa2fd`, confirming that the single-quote acceptance is genuinely discriminated and not a vacuous assertion.

M1 and M2 are the pass-3 sensors for the changed value extraction. M1 reintroduces the exact pre-`dd99ef8` regression (a comment stripper running before the quote scan) and is killed by exactly the new fixture `run_commented_values` (`scripts/validate-herdr-pane-config.sh:137`), so that fixture is load-bearing. M2 is killed broadly.

M3 survived and was analyzed for equivalence rather than test weakness. The added pre-scan `[[:space:]]+#` strip is a no-op on every input that reaches the write decision: for a quoted value the closing-quote scan returns before the comment is reached, and for an unquoted value the trailing `sub(/[[:space:]]*#.*$/, ...)` still strips the comment. A differential run of the real helper against the M3 build on quoted values carrying an embedded `#` (`"a # b"`, `"#/bin/bash"`, `"/bin/ba#sh"`, `"lo#gin"`) produced byte-identical result files in every case, because neither `shell_mode` nor `default_shell` can be a compliant value that contains `#` or a space. M3 is therefore a behaviorally equivalent mutant, not a coverage gap, and no fix task is warranted.

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| No features beyond what was asked | Pass - helper owns exactly the two `[terminal]` keys; no general TOML editing |
| No abstractions for single-use code | Pass - `analyze` / `field` / `emit` / `validate` are each load-bearing |
| No unnecessary "flexibility" | Pass - required values are constants (`container/herdr-pane-config.sh:26-27`); no config surface |
| Only touched files required for the task | Pass - diff surface is 9 files, each tied to an AC |
| Didn't "improve" unrelated code | Pass - no unrelated hunks |
| Matches existing patterns / style | Pass - mirrors `sync-configs.sh` (bash, `set -euo pipefail`, `die` / `log`), gate style mirrors `validate-*.py` |
| Would senior engineer approve? | Pass - atomic write via same-dir `mktemp` + `mv -f`, validate-before-write, refusal over guessing |
| Tests map to ACs and are non-shallow | Pass - each gate check names its HPC id; 11/11 real sensor mutants killed, 1 equivalent |
| Spec-anchored outcome check (asserted values match spec) | Pass - G1, G2, G3 resolved; residuals N2, N3, N4 resolved |
| Per-layer Coverage Expectation (domain 1:1 ACs; routes/e2e happy+edge+error) | Pass - 15 ACs -> 24 behavioral checks + 6 structural checks; refusal paths and both edge branches covered |
| Every test maps to a spec requirement - no unclaimed tests | Pass - gate checks name HPC ids; edge checks map to spec edge cases; TOML-parse and dependency checks map to HPC-10/11/13 |
| Documented guidelines followed | none - strong defaults applied (no repo test/quality guideline file found) |

---

## Edge Cases

| Spec edge case | Handled? | Evidence |
| -------------- | -------- | -------- |
| config file missing | Yes | `scripts/validate-herdr-pane-config.sh:66-67`; helper `container/herdr-pane-config.sh:203-211` creates both keys |
| config file empty | Yes | `scripts/validate-herdr-pane-config.sh:75` |
| `shell_mode` in a different table | Yes | `scripts/validate-herdr-pane-config.sh:193-194`; gate `[ui] shell_mode = "widget"` untouched, `[terminal]` gains `login` |
| `[terminal]` last line, no trailing newline | Yes | `scripts/validate-herdr-pane-config.sh:185-186` |
| config cannot be written | Yes | `scripts/validate-herdr-pane-config.sh:206-207`; helper `container/herdr-pane-config.sh:199` `die "cannot create a temp file in ${dir}"`, and the existing file is left untouched |
| required key holds a same-line comment | Yes | `scripts/validate-herdr-pane-config.sh:142`; `shell_mode = "auto"# legacy` (no space) -> replaced with `shell_mode = "login"` (valid TOML). A compliant value with a comment, with or without a preceding space, is preserved byte-identical (`:137`) |
| AD1 compliant config, keys in opposite order | Yes | gate `scripts/validate-herdr-pane-config.sh:116`: byte-identical, no backup |
| AD2 `[terminal]` header with trailing comment | Yes | re-derived this pass: real helper on `[terminal] # pane config` exits 0 and the result parses as TOML with both keys |
| AD3 fully CRLF compliant config | Yes | re-derived this pass: byte-identical, exit 0; wrong CRLF value repaired with a single `[terminal]` (gate `:201-202`) |
| AD8 duplicate key inside `[terminal]` | Yes | re-derived this pass: real helper exits 1, file untouched (`validate` at `container/herdr-pane-config.sh:245` rejects duplicate assignment) |
| AD10 `[[terminal]]` array-of-tables | Yes | re-derived this pass: real helper exits 1, file untouched (`container/herdr-pane-config.sh:218`) |
| AD11 helper leaves no duplicate key / corrupt file | Yes | `container/herdr-pane-config.sh:245` runs `validate "${tmp}"` and dies on failure before `mv -f`; sensor mutants E and R1 are rejected by that guard |

---

## Runtime Evidence (read-only re-check)

The live-box repair was performed by the implementer. Re-derived read-only in pass 2 and again in pass 3 (no pane create or close, no `reload-config`, no live-path helper run, no write under `/root/.config`). Pass-3 re-check gave the same result:

- `python3 tomllib` on `/root/.config/herdr/config.toml` -> `terminal.shell_mode = 'login'`, `terminal.default_shell = '/bin/bash'`. Consistent with the guarantee.
- `/root/.config/herdr/config.toml.bak-pi-cloud` present (169 bytes, Sep 7 19:05); its `[terminal]` holds `default_shell = "bash"` with no `shell_mode`, i.e. the pre-repair shape. Consistent with HPC-08 and the reported cause.
- `herdr pane list` exits 0 and shows the previously-broken pane `w18:p4` still exists alongside `w18:p1`.
- Still unverified by this run: the reported post-`reload-config` new-pane env (`PATH` containing `/opt/nvim/bin`, `PI_CLOUD=1`, `NVIM v0.12.5`). The verifier shell is not itself a herdr pane (current probe: `PI_CLOUD` unset, `nvim` absent, non-login), and confirming the pane env needs a new pane, which this run is forbidden to create. This is the HPC-09 runtime claim and is recorded here as **parent-reported in `.specs/STATE.md`**, not re-derived.

---

## Gate Check

Build-level gate commands (from the feature spec's Success Criteria and the repo validation suite):

- `python3 scripts/validate-herdr-panes.py` - **Result**: HDP-01..HDP-06 PASS; exit 0
- `bash scripts/validate-herdr-pane-config.sh` - **Result**: 24 passed, 0 failed; exit 0
- `bash -n container/herdr-pane-config.sh container/entrypoint.sh scripts/validate-herdr-pane-config.sh` - **Result**: exit 0
- `python3 /root/.agents/skills/tlc-spec-driven/scripts/validate_spec.py herdr-pane-config-guarantee --root /root/artieeez/pi-cloud` - **Result**: 0 errors, 0 warnings; exit 0
- `python3 scripts/validate-toolchain.py` - **Result**: checks 1-8 PASS, check 9 SKIP (no `--gitops`); exit 0
- `python3 scripts/validate-man-pages.py` - **Result**: MP-01..MP-04 PASS; exit 0
- `python3 scripts/validate-c-man-pages.py` - **Result**: CMP-01..CMP-05 PASS; exit 0
- `~/.local/share/nvim/mason/bin/markdownlint-cli2 .specs/features/herdr-pane-config-guarantee/spec.md .specs/features/herdr-pane-config-guarantee/validation.md .specs/STATE.md docs/TROUBLESHOOTING.md` - **Result**: 0 issues; exit 0
- `python3 /root/.agents/skills/tlc-spec-driven/scripts/validate_state.py herdr-pane-config-guarantee --root /root/artieeez/pi-cloud` - **Result**: 0 errors; exit 0
- `python3 scripts/validate-lazyvim-on-box.py` - **Result**: exit 1; LVB-04 ("baked nvim-config in docker/base.Dockerfile") fails. Pre-existing on `main` (stale assertion; AD-004 replaced the baked config with boot-sync) and unrelated to this feature; not fixed here.

- Test/gate count before feature: `scripts/validate-herdr-panes.py` = 5 named checks (HDP-01..HDP-05); no behavioral gate existed.
- Test/gate count after feature: `scripts/validate-herdr-panes.py` = 6 named checks (HDP-01..HDP-06) + `scripts/validate-herdr-pane-config.sh` = 24 checks.
- Delta: +25 checks. No assertion was deleted without justification; the superseded HDP-04 "TOML fragment parses" assertion was replaced by "the behavioral gate runs and exits 0", a strictly stronger check. `cbaa2fd` added two checks (22 vs the prior 20); `dd99ef8` added two more (24 vs 22).
- Skipped: validate-toolchain.py check 9 (needs `--gitops`), and the gate's tomllib block is provably optional (`scripts/validate-herdr-pane-config.sh:220`).

---

## Gaps and Warnings

- **G1 (resolved)** - quote-agnostic value equality is now implemented in both `value_of` programs (`container/herdr-pane-config.sh:61-74`, `:136-149`); a single-quoted compliant config is byte-identical and a single-quoted non-conforming value is still forced. Sensor mutant R4 is killed by the new fixture (`scripts/validate-herdr-pane-config.sh:124`).
- **G2 (resolved, core)** - HPC-09's traceability cell cites real gate assertions (`scripts/validate-herdr-pane-config.sh:211-212` and `:93`); the runtime pane claim lives in the runtime column. **Residual N2**: six other traceability cells still use stale `F<n>` shorthand tokens (`F4/F7`, `F5/F6`, `F1/F2/F3`, `F9`, `F8`, `F4`) that resolve to no identifier in the gate script; the parenthetical description in each cell does map to a real, passing check, so this is citation cosmetics, not an evidence gap. **Resolved in pass 3 (`dd99ef8`)**: the six cells now name the real gate labels and no `F<n>` token remains anywhere in `spec.md`; every backticked gate identifier matches a label the gate emits (34 backtick spans, 0 unmatched).
- **G3 (resolved, core)** - the "bash and awk only" overstatement is gone. AC-10 states the helper floor (`bash, awk, coreutils`) which matches `container/herdr-pane-config.sh`; the gate AC-3 and the assumptions table state `bash, awk, grep, sed, diff, coreutils`, which matches the gate's actual command set. **Residual N3**: the HPC-13 traceability cell still abbreviates the floor as "bash + awk + coreutils", omitting grep/sed/diff; the operative gate AC carries the full list. **Resolved in pass 3 (`dd99ef8`)**: the HPC-13 cell now reads "bash, awk, grep, sed, diff, cmp, tr, md5sum and cut", all of which the gate actually invokes, and the gate AC-3 / assumptions table carry the general `bash, awk, grep, sed, diff, coreutils` floor.
- **N1 (note, not a gap)** - HDP-05 (`scripts/validate-herdr-panes.py:99-100`) checks the required tokens across the whole `docs/TROUBLESHOOTING.md`, not within section 13 specifically. Sufficient today (section 13 is the only herdr pane entry) but weaker than the spec's "section 13" framing.
- **N4 (resolved in pass 3)** - pass 2 found that a compliant value with a no-space comment (`shell_mode = "login"# legacy`, which is valid TOML) was still rewritten to the canonical bare line, while the space-before-comment form (`"login" # legacy`) was preserved. `dd99ef8` fixes this: `value_of` now stops at the closing quote (`container/herdr-pane-config.sh:64-71`, `:139-146`), so both the space and no-space forms of a compliant value are preserved byte-identical (`scripts/validate-herdr-pane-config.sh:137`), while a commented non-conforming value is still forced (`:142`). Re-derived with the real helper: compliant no-space md5 unchanged, compliant mixed unchanged, non-conforming no-space forced and tomllib-valid.

No hard gap (failed acceptance criterion) and no surviving discriminating mutant were found; the one surviving sensor mutation (M3) is behaviorally equivalent to the shipped code.

---

## Requirement Traceability Update

Spec `.specs/features/herdr-pane-config-guarantee/spec.md` already lists every HPC requirement as `Verified`; pass 3 confirms each row against a real gate assertion at HEAD `dd99ef8`, so no status change is needed.

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| HPC-01 | Verified | Verified (confirmed this pass) |
| HPC-02 | Verified | Verified (confirmed this pass; commented-value check added) |
| HPC-03 | Verified | Verified (G1 and N4 resolved) |
| HPC-04 | Verified | Verified (confirmed this pass) |
| HPC-05 | Verified | Verified (confirmed this pass) |
| HPC-06 | Verified | Verified (confirmed this pass) |
| HPC-07 | Verified | Verified (confirmed this pass) |
| HPC-08 | Verified | Verified (confirmed this pass) |
| HPC-09 | Verified | Verified (deterministic proxy; runtime half parent-reported) |
| HPC-10 | Verified | Verified (confirmed this pass) |
| HPC-11 | Verified | Verified (24 checks, exit 0) |
| HPC-12 | Verified | Verified (11/11 real sensor mutants killed, 1 equivalent) |
| HPC-13 | Verified | Verified (G3, N2, N3 resolved) |
| HPC-14 | Verified | Verified (note N1) |
| HPC-15 | Verified | Verified (confirmed this pass) |

---

## Summary

**Overall**: Ready (pass 3 final: N2, N3, N4 resolved; 0 hard gaps; runtime half of HPC-09 parent-reported)

**Spec-anchored check**: 15/15 requirements matched a spec-defined outcome; 0 spec-precision gaps open.

**Sensor**: 12 mutations injected across three passes; 11 killed, 1 survived (M3, behaviorally equivalent).

**Gate**: 10/10 feature gate commands exit as expected (24 passed, 0 failed on the behavioral gate); 1 pre-existing unrelated checkout-level failure (LVB-04) recorded, not caused by this diff.

**What works**:

- The helper forces exactly the two `[terminal]` keys for any TOML string spelling of the value, preserves unrelated lines byte for byte, treats a compliant value with a trailing comment (space or no-space) as already satisfied, is idempotent for compliant configs (single or double quoted), backs up before any change, and refuses duplicate-`[terminal]`, root-level `terminal.*`, and `[[terminal]]` layouts with the file untouched.
- The entrypoint invokes the guarantee, guarded, before `setsid herdr server`; a non-zero guarantee only logs a warning and cannot stop sshd.
- The behavioral gate is discriminating (M1 reintroduces the exact pre-`dd99ef8` regression and is killed by the new commented-value fixture) and runs with bash, awk, grep, sed, diff and coreutils; the structural gate wires the entrypoint call order, docs, and image install.
- Live config read-only re-check matches the reported repair (`default_shell = /bin/bash`, `shell_mode = login`; pre-repair backup present).

**Issues found**: none.

**Next steps**: none required for readiness. The HPC-09 runtime claim still needs a deployment (new pane) to confirm; all deterministic evidence at HEAD `dd99ef8` is green.

**Verdict**: PASS.
