# Toolchain Unification — Tasks

## Test Coverage Matrix

| Task | TCH-01 | TCH-02 | TCH-03 | TCH-04 | TCH-05 | TCH-06 | TCH-07 | TCH-08 | TCH-09 |
| ---- | ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ |
| T1   |        |        |        |        |        |        |        |        |        |
| T2   |  x     |        |        |        |        |        |        |        |        |
| T3   |        |  x     |        |        |        |        |        |        |        |
| T4   |        |        |  x     |        |        |        |        |        |        |
| T5   |        |        |        |  x     |        |        |        |        |        |
| T6   |        |        |        |        |  x     |  x     |        |        |        |
| T7   |        |        |        |        |        |        |        |  x     |        |
| T8   |        |        |        |        |        |        |  x     |        |  x     |

## Gate Check Commands

```bash
# Spec + tasks structural gates (run from the skill dir):
python3 /root/.agents/skills/tlc-spec-driven/scripts/validate_spec.py toolchain-unification --root /root/artieeez/pi-cloud
python3 /root/.agents/skills/tlc-spec-driven/scripts/validate_tasks.py toolchain-unification --root /root/artieeez/pi-cloud
# Feature gate (deterministic, repo-local) — must exit 0 after T8:
python3 /root/artieeez/pi-cloud/scripts/validate-toolchain.py --gitops /root/artieeez/artr-gitops
# Per-commit convention check:
python3 /root/.agents/skills/tlc-spec-driven/scripts/check_commit.py --message "<msg>"
# Helper script sanity:
bash -n /root/artieeez/pi-cloud/scripts/herdr-sha-sync.sh
shellcheck /root/artieeez/pi-cloud/scripts/herdr-sha-sync.sh
```

## Execution Plan

Single batch of 8 tasks on branch `chore/toolchain-unification`, executed
inline in order (no sub-agents needed). One PR opened at the end.

- **Commits:** all 8 tasks are local atomic commits; each task ends with one
  atomic Conventional Commit and this tasks.md status updated in the same commit.
- **Push + PR:** after T8 and the full gate, push the branch and open one PR
  (user approved). No workflow builds on PR branches (both workflows are
  main-triggered), so CI is exercised at merge time on main.
- **Merge ordering:** build-push-ocir.yaml carries a manifest-wait step, so a
  single merge cannot race the base publish (build-base publishes the new tag;
  the app build waits up to 600s for the manifest, then builds).
- **Promote (user, explicit):** after merge and green app build, run the pi-cloud
  promote workflow with the sha tag; Argo CD rolls the box. Not part of this batch.
- **Verifier:** after T8, a fresh-eyes Verifier runs the spec-anchored outcome
  check + discrimination sensor and writes validation.md (author != verifier).

## Task Breakdown

### T1: Scaffold feature artifacts + deterministic gate

**Depends on:** none
**Where:** `.specs/features/toolchain-unification/` (spec.md, context.md, tasks.md, STATE.md) + `scripts/validate-toolchain.py`
**Tests:** `validate_spec.py` and `validate_tasks.py` exit 0; `validate-toolchain.py` runs and reports FAIL on the not-yet-implemented checks (proves it is a real gate).
**Gate:** both skill validators exit 0.
**Status:** done

### T2: Remove tmux from the base image

**Depends on:** T1
**Where:** `docker/base.Dockerfile`
**Tests:** grep asserts zero `tmux`/`TMUX_VERSION`/`libevent`/`libncurses` and no `/opt/tmux` in `docker/base.Dockerfile`; ruby shim block retained (`/opt/mise/shims/ruby` test line still present).
**Gate:** `validate-toolchain.py` check 1 green.

### T3: Republish the base under ruby-4.0.5-5

**Depends on:** T2
**Where:** `.github/workflows/build-base.yaml`
**Tests:** grep asserts `BASE_TAG: ruby-4.0.5-5` and a history comment noting the tmux removal (-5).
**Gate:** `validate-toolchain.py` check 2 green. PUSH GATE A (user approval) — then base CI build goes green.

### T4: Sync the app workflow to the new base tag

**Depends on:** T3
**Where:** `.github/workflows/build-push-ocir.yaml`
**Tests:** grep asserts `BASE_TAG: ruby-4.0.5-5` identical to build-base.yaml AND a manifest-wait step (`docker manifest inspect`, up to 600s) present after the OCIR login step.
**Gate:** `validate-toolchain.py` check 3 green. (Pushed with gate B.)

### T5: Add renovate.json for pi-cloud

**Depends on:** T4
**Where:** `renovate.json`
**Tests:** python json parse + assertions: five custom managers with the right datasource/packageName pairs (herdr/kubectl/gh = github-releases; pi/playwright = npm), github-actions manager, weekly Mon 06:00 schedule in America/Sao_Paulo, `dependencies` label, own-image (vcp.ocir.io) packageRule present.
**Gate:** `validate-toolchain.py` check 4 green.

### T6: herdr sha-sync helper (script + workflow)

**Depends on:** T5
**Where:** `scripts/herdr-sha-sync.sh` + `.github/workflows/herdr-sha-sync.yaml`
**Tests:** `bash -n` + `shellcheck` clean; no-op simulation (sha already matches) exits 0 with no commit; fork guard present in workflow; pull_request trigger with `Dockerfile` path filter.
**Gate:** `validate-toolchain.py` checks 5–6 green.

### T7: Clean pi-cloud tmux docs and comments

**Depends on:** T2, T3
**Where:** `README.md`, `Dockerfile`, `docs/` (present-tense tmux statements only)
**Tests:** README states tmux was removed; no touched file describes tmux as installed or "pending removal"; historical notes untouched where they are clearly past-tense.
**Gate:** `validate-toolchain.py` check 8 green.

### T8: gitops companion cleanup + close-out gate

**Depends on:** T1, T7
**Where:** artr-gitops `apps/pi/deployment.yaml` + `apps/pi/README.md`; `.specs/STATE.md` + this `tasks.md`
**Tests:** grep in artr-gitops: deployment.yaml header and apps/pi/README.md contain no tmux mention and describe herdr; STATE.md records AD-001..AD-003; traceability statuses updated to Verified in spec.md.
**Gate:** `validate-toolchain.py` exit 0 (all checks, `--gitops` path), `git status --porcelain` clean in both repos. PUSH GATE B (user approval) — then app CI build goes green; Verifier runs.
