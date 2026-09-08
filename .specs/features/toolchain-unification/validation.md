# Validation — toolchain-unification

**Verifier:** independent fresh-eyes pass (author != implementer)
**Date:** 2026-09-08
**Verdict:** PASS
**Result:** PASS
**Diff range reviewed:** pi-cloud `fa90af8..590c10c` (8 commits on
`chore/toolchain-unification`); artr-gitops `c00b138` on `main`.

## Spec-anchored outcome check (evidence-or-zero)

| Req | Verdict | Evidence (file:line) |
| --- | ------- | -------------------- |
| TCH-01 | PASS | `docker/base.Dockerfile`: zero matches for `tmux|libevent|libncurses|/opt/tmux` (grep NONE); no `TMUX_VERSION` ARG or `/opt/tmux` COPY/PATH; retention: `FROM node:${NODE_VERSION}-bookworm-slim` (build L16/final L40), ruby shim guard `test -x /opt/mise/shims/ruby` + readlink assert (L101-103), `NEOVIM_VERSION` ARG + nvim tarball RUN (L20, L108), `openssh-server` + `build-essential` still in final apt (L66-72). AC1/AC2/AC3 covered. Image-build outcome is runtime-pending at merge. |
| TCH-02 | PASS | `.github/workflows/build-base.yaml:26` `BASE_TAG: ruby-4.0.5-5`; history comment documents the -5 tmux removal (L19-26, incl. "-5: base drops tmux…"); trigger paths include `docker/base.Dockerfile` (L7-10). |
| TCH-03 | PASS (structural; runtime pending merge) | `.github/workflows/build-push-ocir.yaml:15` `BASE_TAG: ruby-4.0.5-5`; OCIR login step (L30) precedes manifest-wait step (L50); wait loops `seq 1 60` × `sleep 10` with `docker manifest inspect` (L51-60, 600s cap, fail-loud exit 1); wait precedes Build and push (L62+); explanatory comment L45-49. YAML parses. Runtime race-avoidance verifiable only at merge. |
| TCH-04 | PASS | `renovate.json`: five custom managers — HERDR_VERSION→github-releases/herdrdev/herdr, KUBECTL_VERSION→github-releases/kubernetes/kubernetes, GH_VERSION→github-releases/cli/cli (all with `extractVersionTemplate ^v(?<version>…)$`); PI_VERSION→npm/@earendil-works/pi-coding-agent, PLAYWRIGHT_CLI_VERSION→npm/@playwright/cli; `timezone: America/Sao_Paulo`, `schedule: ["before 6am on Monday"]`, `labels: ["dependencies"]`; packageRule disables `/^vcp\.ocir\.io\//` (enabled:false); no `pinDigests` key (Renovate default off). Kubectl constrained to cluster minor 1.36 via allowedVersions (documented in description). Minor note: the github-actions manager is enabled via Renovate defaults (not an explicit key) — acceptable. |
| TCH-05 | PASS (script logic verified statically + by sensor; GH runtime pending merge) | `.github/workflows/herdr-sha-sync.yaml`: `on.pull_request` with types opened/synchronize/reopened (L14-15), `paths: - Dockerfile` (L16-17), `permissions.contents: write` (L20), job-level fork guard `head.repo.full_name == github.repository` (L25), calls `scripts/herdr-sha-sync.sh` (L34), commits only when `git diff` non-empty (L35-40). `scripts/herdr-sha-sync.sh`: reads ARG HERDR_VERSION/HERDR_SHA256; downloads official asset `v${version}/herdr-linux-aarch64`; `sha256sum`; idempotent no-op when sha matches (exit 0, no edit); `set -euo pipefail` + `curl -fsSL` fail-loud (exit 1, no edit) on fetch failure. Fork PRs are skipped entirely (stronger than "no push"). |
| TCH-06 | PASS | App `Dockerfile:47` `echo "${HERDR_SHA256}  herdr-linux-aarch64" | sha256sum -c -`; ARG at L26. Build-time check retained. |
| TCH-07 | PASS | `.specs/STATE.md:5` AD-001 (tmux removal + ruby-4.0.5-5), `:19` AD-002 (Renovate + sha-sync helper), `:36` AD-003 (tag-based policy), each with Status/Decision/Rationale. |
| TCH-08 | PASS | `README.md:26` and `:39` state removal ("removed in the ruby-4.0.5-5 base rebuild"); no "still carries"/"pending removal"; app `Dockerfile`: zero tmux matches; `docs/TROUBLESHOOTING.md` headings contiguous 1-10 (L6..L122) with no tmux sections and zero tmux mentions; base-tag references updated (no `ruby-4.0.5_tmux-3.7c-4` anywhere in repo). |
| TCH-09 | PASS | `artr-gitops/apps/pi/deployment.yaml:2` header: "Attach: … -> herdr"; `apps/pi/README.md:63`: "AUTO_PI=1 env starts a pi agent pane inside the boot herdr server"; zero tmux matches in either file. |

## Deterministic gate

`python3 scripts/validate-toolchain.py --root /root/artieeez/pi-cloud --gitops /root/artieeez/artr-gitops`
→ exit 0, 9/9 PASS.

## Discrimination sensor (isolated scratch, /tmp, deleted after)

| Mutant | Expected flip | Result |
| ------ | ------------- | ------ |
| (a) Resurrect `ARG TMUX_VERSION` in scratch base.Dockerfile | check 1 → FAIL | KILLED (FAIL, leftover=['TMUX']) |
| (b) Revert scratch build-base BASE_TAG to ruby-4.0.5_tmux-3.7c-4 | check 2 → FAIL | KILLED (FAIL, new_tag=False old_gone=False) |
| (c) Delete HERDR_VERSION custom manager from scratch renovate.json | check 4 → FAIL | KILLED (FAIL, "HERDR_VERSION->github-releases missing/mismatched") |
| (d) Remove idempotency guard block from scratch herdr-sha-sync.sh | check 5 → FAIL | KILLED (FAIL, idempotent=False) |

No survivors. Scratch removed; real-tree porcelain clean in both repos (only this validation.md is new in pi-cloud, uncommitted by design).

## Ranked gaps (none blocking)

1. **Renovate app install is external** (spec assumption marked `n`): the hosted app must be confirmed/installed on `artieeez/pi-cloud` after merge, and the Dependency Dashboard checked for the five deps. Cannot be verified from the repo.
2. **Runtime CI outcomes pending merge**: TCH-01.3 base-image build, TCH-02/03 publish + manifest-wait race behavior, TCH-05/06 workflow behavior on a real herdr PR all exercise only at merge on main (both workflows are main-triggered; PR branches do not build).
3. **github-actions manager implicit** in renovate.json (default-enabled, not explicit) — cosmetic; add an explicit key if explicitness is preferred.
4. **Observation (not a defect):** the sha-sync workflow executes PR-head script content with a `contents: write` token, mitigated for this single-maintainer repo by the fork-PR job guard. If the repo ever accepts outside contributors, revisit (pinned script + pull_request_target pattern).
5. **kubectl allowedVersions hardcodes 1.36** — intentional and documented; must be widened when the OKE cluster is upgraded.

## Verifier notes

- Implementer's claim "9 requirements, all mapped" confirmed: traceability table shows 9/9 Implemented, 0 unmapped.
- Doc surgery verified: TROUBLESHOOTING numbering is contiguous 1-10 after removing the two obsolete tmux sections; section 4 retitled to the still-real PATH lesson (no tmux).
- App Dockerfile diff vs main is comment-only (tmux dropped from header list) — confirmed earlier via diff; sha256sum herdr check untouched.
