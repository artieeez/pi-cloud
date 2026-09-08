# Toolchain Unification Specification

## Problem Statement

pi-cloud's toolchain is maintained by hand and inconsistently: tmux still
compiles into the base image although herdr replaced it years ago; every
version bump (pi, kubectl, gh, herdr, playwright-cli) is a manual Dockerfile
edit; herdr's checksum has no automation at all because upstream ships no
checksum sidecar; and docs in two repos still describe a tmux-based box. The
repo already planned to drop tmux "at the next base rebuild" — this feature
does that rebuild and makes every future bump a reviewable bot PR.

## Goals

- Remove tmux from the base image and republish the base under a new tag.
- Route all version bumps through the hosted Renovate app (single bot queue),
  keeping per-tool integrity: official checksum sidecars for kubectl/gh,
  build-enforced sha256 for herdr, npm pins for pi/playwright.
- Record the tag-based (no-digest-pinning) policy as an explicit decision.
- Clean stale tmux references in pi-cloud docs and artr-gitops pi app notes.

## Out of Scope

| Item | Reason |
| ---- | ------ |
| De-rooting the box (securityContext hardening) | Separate feature; deferred in context.md |
| Digest pinning for container images | Deliberately not chosen (AD-003) |
| mise/aqua lockfile consolidation of CLIs | Would downgrade kubectl/gh checksum verification; deferred unless no-sidecar tools multiply |
| node:24 floating-major pinning | Future bump, unrelated |
| Changes to the artr-gitops Renovate config | Out of scope; only stale-tmux doc lines are touched there |
| The standalone weekly update-herdr workflow | Superseded by Design 1 (Renovate + sha-sync helper) |

---

## Assumptions & Open Questions

Every ambiguity is resolved or recorded here - nothing is left silently unclear.

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| tmux is unused on the box | Removed entirely, no apt fallback | User: "I'm not using tmux, only pi and herdr"; herdr hosts panes | yes |
| Base tag name after removal | `ruby-4.0.5-5` (counter continues, tmux segment drops) | Repo convention: bump the counter suffix on same-version rebuilds | yes |
| Republish sequencing | Two-phase push; app workflow keeps old base until base is published | Avoids FROM failures on a not-yet-existing base (hit before, per build-base comment) | yes |
| herdr stays inside Renovate | Renovate proposes HERDR_VERSION; sha-sync helper patches HERDR_SHA256 on the PR | User: "keep herdr in renovate too"; Design 1 chosen over manual sha | yes |
| kubectl/gh install mechanism | Keep curl + official checksum sidecars | Strongest verification available; a lockfile would be ToFU downgrade | yes |
| Digest policy | Tags + Renovate; pinDigests off, recorded as AD-003 | Estate norm and homelab practice; digest churn cost | yes |
| Renovate hosting | Hosted Mend app on pi-cloud, config in renovate.json | Same as artr-gitops; no self-hosted runner | yes |
| Renovate app install scope | Confirm/install the app on artieeez/pi-cloud (may already be org-wide) | One-click GitHub install if missing; config ships regardless | n (action at execution) |
| Helper push rights | GITHUB_TOKEN (same-repo PR branches); assumes no branch protection blocks it | Renovate branches are same-repo and unprotected | yes |
| herdr asset naming stays | `herdr-linux-aarch64` per release | If upstream renames assets the helper fails loudly by design | yes |
| Renovate cadence/style | Weekly Mon 06:00 America/Sao_Paulo, `dependencies` label, semantic commits | Mirrors artr-gitops convention | yes |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Base rebuild without tmux

**User Story**: As the box operator, I want tmux gone from the base image so the
box ships only what herdr/pi need, and the base tag name reflects it.

**Why P1**: The repo already declared tmux removal for "the next base rebuild";
leaving it compiles and ships an unused terminal multiplexer forever.

**Acceptance Criteria**:

1. The base Dockerfile SHALL contain no tmux compile instructions, no `TMUX_VERSION` ARG, no `/opt/tmux` COPY, and no `/opt/tmux/bin` PATH entry.
2. The base Dockerfile SHALL install no tmux runtime libraries (`libevent-2.1-7`, `libncurses6`) and SHALL create no libevent compatibility symlinks.
3. The base image SHALL retain node, mise + Ruby (shims executable), neovim, and the sshd/runtime apt set after the tmux removal.
4. WHEN a commit touching `docker/base.Dockerfile` lands on main THEN `build-base.yaml` SHALL publish `pi-cloud-base` under the tag `ruby-4.0.5-5` and SHALL record the removal in its BASE_TAG history comment.
5. WHEN `build-push-ocir.yaml` builds against `BASE_TAG` `ruby-4.0.5-5` THEN the workflow SHALL wait for that base manifest to exist in OCIR before starting the build, up to 600 seconds, so a single merged PR cannot race the base publish.
6. The app image build SHALL complete successfully against the republished base tag `ruby-4.0.5-5` once its manifest is present.

**Independent Test**: Merge the feature PR as one commit; confirm `build-base`
publishes the new tag and the app build waits for and succeeds against it,
with no manual re-run.

---

### P1: All version bumps through one bot queue

**User Story**: As the box operator, I want every tool version in the pi-cloud
Dockerfile bumped by Renovate PRs (like artr-gitops) so nothing is updated by
hand anymore.

**Why P1**: Uniform proposal source; herdr must stay in the same queue even
though Renovate cannot compute its checksum.

**Acceptance Criteria**:

1. pi-cloud SHALL contain a `renovate.json` declaring github-releases custom managers for `HERDR_VERSION` (herdrdev/herdr), `KUBECTL_VERSION` (kubernetes/kubernetes), and `GH_VERSION` (cli/cli), each stripping a leading `v` from release tags.
2. pi-cloud SHALL contain a `renovate.json` declaring npm custom managers for `PI_VERSION` (@earendil-works/pi-coding-agent) and `PLAYWRIGHT_CLI_VERSION` (@playwright/cli).
3. `renovate.json` SHALL enable the github-actions manager and SHALL schedule runs weekly on Monday before 06:00 America/Sao_Paulo with the `dependencies` label.
4. `renovate.json` SHALL disable updates for images under `vcp.ocir.io` and SHALL leave digest pinning disabled, expressing the tag-based policy (AD-003).
5. The app Dockerfile SHALL retain `sha256sum -c` verification of the herdr download against `HERDR_SHA256` at image build time.
6. WHEN any PR modifies `Dockerfile` and is opened or synchronized THEN the `herdr-sha-sync` workflow SHALL run and compute the sha256 of the `herdr-linux-aarch64` release asset for the version declared by the PR head's `HERDR_VERSION`.
7. IF the PR head's `HERDR_SHA256` differs from the computed sha256 THEN the helper SHALL push a commit to the PR branch updating `HERDR_SHA256` to the computed value.
8. IF the PR head's `HERDR_SHA256` already equals the computed sha256 THEN the helper SHALL exit successfully without creating or pushing any commit.
9. IF the release asset for the declared version cannot be fetched THEN the helper SHALL fail with an explanatory message and SHALL NOT modify the PR branch.
10. IF the pull request originates from a fork THEN the helper SHALL exit without attempting to push.

**Independent Test**: Trigger a synthetic herdr version-bump PR and observe the
helper patch the sha (and no-op on re-run); open the Renovate Dependency
Dashboard on pi-cloud and see herdr/kubectl/gh/pi/playwright listed.

---

### P2: Policy recorded and docs consistent

**User Story**: As the box operator, I want the pinning policy written down and
no doc claiming tmux still runs, so future-me and the agents read the truth.

**Why P2**: Decisions that are only implicit get silently reversed; stale docs
mislead agents and humans alike.

**Acceptance Criteria**:

1. `.specs/STATE.md` SHALL record decisions AD-001 (tmux removal + base tag), AD-002 (Renovate + herdr sha-sync helper), and AD-003 (tag-based digest policy) with rationale.
2. pi-cloud `README.md` SHALL state that tmux was removed from the base image and SHALL NOT describe tmux as present or "pending removal".
3. pi-cloud docs and the app Dockerfile header SHALL NOT describe tmux as currently installed content of the base.
4. artr-gitops `apps/pi/deployment.yaml` header comment SHALL describe attaching to the box via herdr, with no tmux instruction.
5. artr-gitops `apps/pi/README.md` SHALL describe `AUTO_PI=1` as booting a pi agent in a herdr pane, with no tmux reference.

**Independent Test**: Grep both repos: no surviving present-tense tmux claim in
the touched files; STATE.md contains the three AD entries.

---

## Edge Cases

- IF a herdr release asset disappears or is renamed THEN the sha-sync helper fails loudly with a message and never mangles the PR (TCH-05.9).
- IF the helper's own push re-triggers the workflow THEN the idempotency check (sha already matches) exits clean with no loop.
- IF a human PR (not Renovate) bumps herdr THEN the helper still patches the sha — coverage is by version change, not by author.
- IF base publish and app build run concurrently against the same new tag (single-PR merge) THEN the app workflow's manifest-wait step blocks until the base exists, up to 600s, then builds.

---

## Requirement Traceability

| Requirement ID | Story       | Phase | Status  |
| -------------- | ----------- | ----- | ------- |
| TCH-01         | P1: Base rebuild without tmux | Tasks | Pending |
| TCH-02         | P1: Base rebuild without tmux | Tasks | Pending |
| TCH-03         | P1: Base rebuild without tmux | Tasks | Pending |
| TCH-04         | P1: All version bumps through one bot queue | Tasks | Pending |
| TCH-05         | P1: All version bumps through one bot queue | Tasks | Pending |
| TCH-06         | P1: All version bumps through one bot queue | Tasks | Pending |
| TCH-07         | P2: Policy recorded and docs consistent | Tasks | Pending |
| TCH-08         | P2: Policy recorded and docs consistent | Tasks | Pending |
| TCH-09         | P2: Policy recorded and docs consistent | Tasks | Pending |

**Coverage:** 9 total, 9 mapped to tasks, 0 unmapped

---

## Success Criteria

- Base and app CI builds are green across both phases, ending on base tag `ruby-4.0.5-5`.
- A merged herdr Renovate PR produces an image build that passes `sha256sum -c` without a human touching the sha (helper did it).
- `grep -ri tmux` in the touched pi-cloud files and artr-gitops pi app notes returns only historical/removal statements.
- The Renovate Dependency Dashboard on pi-cloud lists all five tool versions.
