# Toolchain Unification Context

**Gathered:** 2026-09-08
**Spec:** `.specs/features/toolchain-unification/spec.md`
**Status:** Ready for tasks

---

## Feature Boundary

Make pi-cloud's toolchain boring and uniform: drop the unused tmux from the
base image (republish), route every version bump through reviewable bot PRs
(Renovate on pi-cloud, with a small helper that keeps herdr's checksum strict),
record the tag-based digest policy, and clean stale tmux references in docs
(pi-cloud + the artr-gitops pi app notes).

---

## Implementation Decisions

### Base rebuild contents (GA-4)

- tmux removed entirely — no apt fallback (user does not use tmux; herdr is the
  pane host). Nothing else in the base changes (nvim, mise + Ruby stay).
- Base republished as `ruby-4.0.5-5` (counter convention continues, tmux
  segment drops). User opted for one branch + one PR, so deterministic ordering
  comes from a manifest-wait step in `build-push-ocir.yaml` (`docker manifest
  inspect`, up to 600s): after merge, build-base publishes the new tag and the
  app build waits for it instead of racing. The live box is untouched until the
  user promotes the merged image.

### Version-bump automation (GA-2 + follow-up "keep herdr in renovate too")

- Renovate (hosted app, same as artr-gitops) is the single proposer for every
  version ARG in the app Dockerfile: npm datasource for PI_VERSION and
  PLAYWRIGHT_CLI_VERSION; github-releases datasource for KUBECTL_VERSION
  (kubernetes/kubernetes, `^v` strip), GH_VERSION (cli/cli, `^v` strip),
  HERDR_VERSION (herdrdev/herdr, `^v` strip). github-actions manager enabled.
- kubectl and gh keep curl + official upstream checksum verification (sidecars
  exist; a lockfile would be an integrity downgrade).
- herdr keeps the hand-pinned HERDR_SHA256, build-enforced via sha256sum -c.
  Renovate cannot compute release-asset hashes, so Design 1 was chosen: a
  `herdr-sha-sync` helper (workflow + `scripts/herdr-sha-sync.sh`) that runs on
  PRs touching Dockerfile and pushes the correct HERDR_SHA256 onto the PR
  branch when the version changed. Idempotent: no commit when the sha already
  matches. The standalone weekly "update-herdr" robot from the earlier plan is
  NOT built (two proposers on the same lines would collide).
- Helper logic lives in a shell script (testable: bash -n, shellcheck,
  no-op simulation), the workflow only triggers + checks out + runs it.

### Digest policy (GA-3)

- Tags + Renovate freshness; `pinDigests` stays off. Recorded as AD-003 in
  STATE.md and expressed as an own-image packageRule in renovate.json.

### Docs cleanup

- pi-cloud: README tmux bullet now states removal; app Dockerfile header comment
  no longer lists tmux as base content; TROUBLESHOOTING/BOOT-SYNC swept for
  present-tense "tmux is installed" statements (historical notes stay).
- artr-gitops companion: `apps/pi/deployment.yaml` header and `apps/pi/README.md`
  describe herdr, not tmux. (docs/PHONE-TERMUX.md = Android Termux app; kept.)

### Agent's Discretion

- Exact wording of docs edits; exact comment text in workflows/base headers.
- Helper workflow trigger details (pull_request types opened/synchronize,
  paths: Dockerfile) and exact YAML structure.

### Declined / Undiscussed Gray Areas → Assumptions

- Renovate install scope (org-wide vs per-repo): assumed the hosted app must be
  confirmed/installed on pi-cloud; one-click GitHub action if missing. Logged in
  spec assumptions.
- Branch protection: assumed main is not protected against the helper pushing to
  renovate PR branches (GITHUB_TOKEN, same-repo). Logged in spec assumptions.

---

## Specific References

No specific external references — user chose the recommended standard patterns
throughout.

---

## Deferred Ideas

- De-rooting pi-cloud (Tier-1 securityContext: drop caps, readOnlyRootFilesystem,
  allowPrivilegeEscalation false) — separate feature.
- `node:24-bookworm-slim` is a floating major tag in the base — pinning a minor
  is a future bump.
- Full aqua/mise consolidation of release-file CLIs, only if the no-sidecar tool
  list ever grows past herdr.
- Digest pinning (pinDigests) if a stricter posture is ever wanted (see AD-003).
