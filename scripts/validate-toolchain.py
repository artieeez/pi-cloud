#!/usr/bin/env python3
"""
validate-toolchain.py - deterministic structural gate for the pi-cloud
Toolchain Unification feature (.specs/features/toolchain-unification/).

Checks (spec-anchored, TCH-01..TCH-09):
  1. base.Dockerfile has no tmux/libevent/libncurses artifacts (TCH-01)
  2. build-base.yaml pins BASE_TAG ruby-4.0.5-5 (TCH-02)
  3. build-push-ocir.yaml pins BASE_TAG ruby-4.0.5-5 (TCH-03)
  4. renovate.json declares the five custom managers + policy (TCH-04)
  5. herdr-sha-sync workflow + script exist with trigger/fork guard (TCH-05)
  6. app Dockerfile keeps sha256sum herdr check; script hashes + no-ops (TCH-05/06)
  7. .specs/STATE.md records AD-001..AD-003 (TCH-07)
  8. README.md + app Dockerfile carry only the removal statement (TCH-08)
  9. artr-gitops pi app notes contain no tmux (TCH-09, needs --gitops)

Pure standard library. Exit 0 = all applicable checks pass.
"""
import argparse
import json
import os
import re
import sys


def check(name, ok, detail=""):
    tag = "PASS" if ok else "FAIL"
    print(f"[{tag}] {name}{(' — ' + detail) if detail and not ok else ''}")
    return ok


def read(root, rel):
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8") as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.getcwd(), help="pi-cloud repo root")
    ap.add_argument("--gitops", default=None, help="artr-gitops repo root (check 9)")
    args = ap.parse_args()

    results = []
    base_d = read(args.root, "docker/base.Dockerfile")
    app_d = read(args.root, "Dockerfile")
    bb = read(args.root, ".github/workflows/build-base.yaml")
    bp = read(args.root, ".github/workflows/build-push-ocir.yaml")
    rj = read(args.root, "renovate.json")
    wf = read(args.root, ".github/workflows/herdr-sha-sync.yaml")
    sh = read(args.root, "scripts/herdr-sha-sync.sh")
    st = read(args.root, ".specs/STATE.md")
    readme = read(args.root, "README.md")

    # 1. base.Dockerfile free of tmux (and its runtime libs) but keeps mise/nvim
    if base_d is None:
        results.append(check(1, False, "docker/base.Dockerfile missing"))
    else:
        bad = re.findall(r"(?i)tmux|libevent|libncurses|/opt/tmux", base_d)
        keep = re.search(r"mise/shims|NEOVIM_VERSION", base_d)
        results.append(check(1, not bad and bool(keep),
                             f"leftover={bad[:3]} keep={bool(keep)}"))

    # 2 + 3. base tag renamed in both workflows; 3 also needs the manifest-wait
    for num, path, content, extra_wait in ((2, "build-base.yaml", bb, False),
                                            (3, "build-push-ocir.yaml", bp, True)):
        if content is None:
            results.append(check(num, False, f"{path} missing"))
            continue
        new_ok = re.search(r"BASE_TAG:\s*ruby-4\.0\.5-5", content)
        old_gone = "ruby-4.0.5_tmux-3.7c-4" not in content
        wait_ok = (not extra_wait) or ("docker manifest inspect" in content
                                       and "seq 1 60" in content)
        results.append(check(num, bool(new_ok) and old_gone and wait_ok,
                             f"new_tag={bool(new_ok)} old_gone={old_gone} wait_step={wait_ok}"))

    # 4. renovate.json: five custom managers + schedule/label + own-image rule
    if rj is None:
        results.append(check(4, False, "renovate.json missing"))
    else:
        try:
            cfg = json.loads(rj)
            cms = {c.get("packageNameTemplate"): c for c in cfg.get("customManagers", [])}
            want = {
                "herdrdev/herdr": ("github-releases", "HERDR_VERSION"),
                "kubernetes/kubernetes": ("github-releases", "KUBECTL_VERSION"),
                "cli/cli": ("github-releases", "GH_VERSION"),
                "@earendil-works/pi-coding-agent": ("npm", "PI_VERSION"),
                "@playwright/cli": ("npm", "PLAYWRIGHT_CLI_VERSION"),
            }
            ok = True
            detail = []
            for pkg, (ds, arg) in want.items():
                cm = cms.get(pkg)
                good = bool(cm and cm.get("datasourceTemplate") == ds
                            and re.search(arg + r"=", " ".join(cm.get("matchStrings", []))))
                ok = ok and good
                if not good:
                    detail.append(f"{arg}->{ds} missing/mismatched")
            sched = json.dumps(cfg.get("schedule", ""))
            tz = cfg.get("timezone", "")
            labels = cfg.get("labels", [])
            rules = cfg.get("packageRules", [])
            own_off = any(
                r.get("enabled") is False
                and any(str(p).startswith("/^vcp") for p in r.get("matchPackageNames", []))
                for r in rules
            )
            digests_on = bool(cfg.get("pinDigests"))
            ok = ok and ("before 6am on Monday" in sched) and tz == "America/Sao_Paulo"
            ok = ok and labels == ["dependencies"] and own_off and not digests_on
            results.append(check(4, ok, "; ".join(detail) or
                                 f"sched={tz} labels={labels} own_off={own_off} pinDigests={digests_on}"))
        except json.JSONDecodeError as e:
            results.append(check(4, False, f"invalid json: {e}"))

    # 5. sha-sync workflow + script exist with trigger, path filter, fork guard
    if wf is None:
        results.append(check(5, False, "herdr-sha-sync.yaml missing"))
    else:
        trig = "pull_request" in wf and re.search(r"paths:[\s\S]*Dockerfile", wf)
        fork_guard = ("head.repo.full_name" in wf or "fork" in wf.lower())
        calls_script = "herdr-sha-sync.sh" in wf
        results.append(check(5, bool(trig and fork_guard and calls_script),
                             f"trigger={bool(trig)} fork_guard={fork_guard} script_ref={calls_script}"))
    if sh is None:
        results.append(check(5, False, "scripts/herdr-sha-sync.sh missing"))
    else:
        hashes = "sha256sum" in sh and "HERDR_SHA256" in sh and "HERDR_VERSION" in sh
        loud = "set -euo pipefail" in sh
        noop = re.search(r"if.*==.*then|if.*=.*then", sh)
        results.append(check(5, bool(hashes and loud and noop),
                             f"hashes={hashes} fail_loud={loud} idempotent={bool(noop)}"))

    # 6. app Dockerfile keeps build-time sha256sum herdr verification
    if app_d is None:
        results.append(check(6, False, "Dockerfile missing"))
    else:
        ver = re.search(r"HERDR_SHA256[\s\S]{0,400}?sha256sum -c", app_d)
        results.append(check(6, bool(ver), "sha256sum herdr check retained"))

    # 7. decisions recorded
    if st is None:
        results.append(check(7, False, ".specs/STATE.md missing"))
    else:
        ads = all(f"AD-00{i}" in st for i in (1, 2, 3))
        results.append(check(7, ads, f"AD entries={ads}"))

    # 8. pi-cloud docs: removal stated, nothing claims tmux still installed
    if readme is None:
        results.append(check(8, False, "README.md missing"))
    else:
        removed = re.search(r"(?i)tmux.*(removed|dropped)|(removed|dropped).*tmux", readme)
        still = re.search(r"(?i)tmux.*(still carries|pending removal|present)", readme)
        app_clean = app_d is not None and "tmux" not in app_d.lower()
        results.append(check(8, bool(removed) and not still and app_clean,
                             f"removal_stated={bool(removed)} stale_claim={bool(still)} app_dockerfile_clean={app_clean}"))

    # 9. artr-gitops companion (optional path)
    if args.gitops is None:
        print("[SKIP] 9 — pass --gitops to check artr-gitops tmux cleanup")
    else:
        dep = read(args.gitops, "apps/pi/deployment.yaml") or ""
        app_readme = read(args.gitops, "apps/pi/README.md") or ""
        ok = "tmux" not in dep.lower() and "tmux" not in app_readme.lower()
        results.append(check(9, ok, "deployment.yaml + apps/pi/README.md tmux-free"))

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
