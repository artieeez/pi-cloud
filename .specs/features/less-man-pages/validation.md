# Validation — less-man-pages

**Verifier:** inline Small-scope verification per tlc-spec-driven auto-sizing
(author == implementer; the deterministic gates are structural + build-based,
fresh-eyes pass performed as the standalone fallback — the structural gate's
own predicates failed on first run and were corrected, which is the closest
this feature gets to a discrimination check)
**Date:** 2026-09-20
**Verdict:** PASS
**Result:** PASS
**Diff range reviewed:** pi-cloud `d9ecd96..9420978` on `feat/less-man-pages`
(1 commit: `9420978`). Review against full feature state at HEAD `9420978`.

## Spec-anchored outcome check (evidence-or-zero)

Inline spec (Small scope): the box must ship a working `less` pager, working
`man` for the tools already on the box, delivered through the base image
(re-published under a new tag so the app inherits it), with no regression of
the existing toolchain gates.

| Req | Verdict | Evidence (file:line) |
| --- | ------- | -------------------- |
| RQ-01 | PASS | `docker/base.Dockerfile:89-93` final-stage apt list: `less man-db groff-base manpages`. `man-db` = the `man` binary; `groff-base` = the roff renderer `man` shells out to (absent in slim, `man` would fail rendering). Pager verified at runtime: `less --version` → `less 590 (GNU regular expressions)`. |
| RQ-02 | PASS | `docker/base.Dockerfile:85-87` removes the slim base's `path-exclude /usr/share/man/*` (in `/etc/dpkg/dpkg.cfg.d/docker`) BEFORE the apt install — dpkg filters apply at unpack, so ordering is the mechanism. `:94-97` `--reinstall` of 22 pre-baked base packages (bash, coreutils, util-linux, grep, sed, tar, gzip, findutils, diffutils, dpkg, passwd, login, …) — slimify deleted their man trees from disk, a filter change alone cannot restore files; `--reinstall` re-unpacks them now that man is un-excluded. Runtime proof (full base image, `pi-cloud-base:man-gate`): `man -w` resolves and `MANPAGER=cat man <x>` renders for less, ls, git, sed, bash, grep, man, jq, rg, curl, sqlite3. `/usr/share/doc` + `/usr/share/locale` stay excluded on purpose (`:88` comment) — only man pages restored. |
| RQ-03 | PASS | Base re-published under a new tag per AD-001 counter convention: `.github/workflows/build-base.yaml:34-35` `BASE_TAG: ruby-4.0.5-6` (+ `-6` history note `:31-33`, path-triggered on `docker/base.Dockerfile`); `.github/workflows/build-push-ocir.yaml:15` `BASE_TAG: ruby-4.0.5-6` synced in the same PR so the merged push rebuilds FROM the new base (existing manifest-wait step `:46-60` prevents the race). |
| RQ-04 | PASS | `scripts/validate-man-pages.py` pins the structure (MP-01 sed-before-apt, MP-02 package set, MP-03 reinstall set, MP-04 README) — all PASS on HEAD. `scripts/validate-toolchain.py` (TCH-02/03 updated to `ruby-4.0.5-6` at `:108`) — checks 1-8 PASS on HEAD, no regression. `README.md:28-31` advertises the tools; markdownlint clean. |

## Deterministic gates (from repo root, real tree)

`python3 scripts/validate-man-pages.py`:

```text
[PASS] MP-01  man path-exclude removed before apt update
[PASS] MP-02  less/man-db/groff-base/manpages in final-stage install
[PASS] MP-03  --reinstall resurrect set present
[PASS] MP-04  README advertises the tools
```

`python3 scripts/validate-toolchain.py`:

```text
[PASS] 1 .. 8 (tmux-free base, BASE_TAG sync, renovate managers, herdr sha,
Dockerfile checksum, AD-001..003, README claims)   [SKIP] 9 (needs --gitops)
```

## Build gates (runtime evidence, not just structure)

1. Focused gate — `node:24-bookworm-slim` + the exact final-stage RUN block
   (no Ruby compile): image build PASS; inside it `man -w` + rendered output
   verified for all 11 target tools; `dpkg -L less` shows 6 man files;
   `dpkg -L coreutils` man restored; `/run/sshd` present; zero baked ssh
   host keys.
2. Full gate — `docker build -f docker/base.Dockerfile -t pi-cloud-base:man-gate`
   from the real tree: build PASS (including the mise/Ruby and nvim stages);
   in-image assertions `man -w less/git/ls` + rendered `LESS(1)`/`GIT(1)` PASS.

## Notes

- No AD added: routine package restore, not an architectural decision
  (contrast AD-001 tmux removal).
- STATE handoff refreshed (was stale: pointed at the lazyvim feature that
  merged as PR #4).
