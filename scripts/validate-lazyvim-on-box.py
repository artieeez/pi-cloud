#!/usr/bin/env python3
"""
validate-lazyvim-on-box.py - deterministic structural gate for the pi-cloud
LazyVim-on-box feature (.specs/features/lazyvim-on-box/).

Checks (spec-anchored, LVB-01..LVB-08):
  1. sync-configs.sh FORCED group header lists nvim-config -> /root/.config/nvim
  2. sync-configs.sh force-syncs artieeez/nvim-config into ${HOME_DIR}/.config/nvim
     via the shared sync_forced helper (LVB-01/02)
  3. failure tolerance preserved: sync still set -uo pipefail, deploy-key guard
     exits 0, nvim-config sync is non-fatal (|| true) (LVB-03)
  4. no nvim-config bake in docker/base.Dockerfile or Dockerfile (LVB-04; /root
     is the PVC mount and shadows image content)
  5. README.md describes nvim as LazyVim (nvim-config) boot-synced to
     ~/.config/nvim and states icons render client-side (LVB-05)
  6. docs/PHONE-TERMUX.md documents the Termux Nerd Font install: font.ttf +
     termux-reload-settings + JetBrainsMono + adb push route (LVB-06)
  7. docs/TROUBLESHOOTING.md records the tofu/icons symptom + doc pointer (LVB-07)
  8. .specs/STATE.md records AD-004 (LVB-08)

Pure standard library. Exit 0 = all checks pass.
"""
import argparse
import os
import re
import sys


def check(num, ok, detail=""):
    tag = "PASS" if ok else "FAIL"
    print(f"[{tag}] LVB-{num:02d}{(' — ' + detail) if detail and not ok else ''}")
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
    args = ap.parse_args()

    results = []
    sync = read(args.root, "container/sync-configs.sh")
    base_d = read(args.root, "docker/base.Dockerfile")
    app_d = read(args.root, "Dockerfile")
    readme = read(args.root, "README.md")
    phone = read(args.root, "docs/PHONE-TERMUX.md")
    trouble = read(args.root, "docs/TROUBLESHOOTING.md")
    state = read(args.root, ".specs/STATE.md")

    # 1. FORCED group header comment lists nvim-config -> /root/.config/nvim
    if sync is None:
        results.append(check(1, False, "container/sync-configs.sh missing"))
    else:
        header_ok = bool(re.search(r"FORCED[\s\S]*nvim-config\s*->\s*/root/\.config/nvim", sync))
        results.append(check(1, header_ok, "group header entry missing"))

    # 2. actual sync invocation via the shared sync_forced helper
    if sync is None:
        results.append(check(2, False, "container/sync-configs.sh missing"))
    else:
        call = re.search(
            r'sync_forced "\$\{HOME_DIR\}/\.config/nvim" "\$\{ORG\}/nvim-config\.git"',
            sync)
        helper_defined = bool(re.search(r"sync_forced\(\)", sync))
        same_helper = "sync_forced \"${AGENTS_DIR}\" \"${ORG}/dotagents.git\"" in sync
        results.append(check(2, bool(call) and helper_defined and same_helper,
                             "sync_forced nvim-config call missing"))

    # 3. failure tolerance: non-fatal sync, deploy-key guard still exits 0
    if sync is None:
        results.append(check(3, False, "container/sync-configs.sh missing"))
    else:
        tolerant = bool(re.search(
            r'sync_forced "\$\{HOME_DIR\}/\.config/nvim".*?\|{0,2} true', sync)) or \
            bool(re.search(r'nvim-config\.git" \|\| true', sync))
        guard = "deploy key missing" in sync and "exit 0" in sync
        pipefail = "set -uo pipefail" in sync
        results.append(check(3, tolerant and guard and pipefail,
                             f"non_fatal={tolerant} key_guard={guard} pipefail={pipefail}"))

    # 4. no image bake of nvim-config (config lives on the PVC via boot sync)
    baked = []
    for path, content in (("docker/base.Dockerfile", base_d),
                          ("Dockerfile", app_d)):
        if content is None:
            results.append(check(4, False, f"{path} missing"))
            continue
        if re.search(r"nvim-config|/root/\.config/nvim", content):
            baked.append(path)
    if baked:
        results.append(check(4, False, f"baked nvim-config in {', '.join(baked)}"))
    elif base_d is not None and app_d is not None:
        results.append(check(4, True, "no nvim-config bake in either Dockerfile"))

    # 5. README: LazyVim config boot-synced + client-side font statement
    if readme is None:
        results.append(check(5, False, "README.md missing"))
    else:
        synced = "nvim-config" in readme and "~/.config/nvim" in readme
        client = "client-side" in readme and "Nerd Font" in readme
        results.append(check(5, synced and client,
                             f"sync_stated={synced} client_font={client}"))

    # 6. PHONE-TERMUX.md: Nerd Font section with the working recipe
    if phone is None:
        results.append(check(6, False, "docs/PHONE-TERMUX.md missing"))
    else:
        has_heading = bool(re.search(r"## 6\. Nerd Font for icons", phone))
        has_font = "font.ttf" in phone and "JetBrainsMono" in phone
        has_reload = "termux-reload-settings" in phone
        has_adb = "/data/local/tmp" in phone and "run-as com.termux" in phone
        has_cause = "tofu" in phone or "empty boxes" in phone
        results.append(check(6, has_heading and has_font and has_reload
                             and has_adb and has_cause,
                             f"heading={has_heading} font={has_font} "
                             f"reload={has_reload} adb={has_adb} tofu={has_cause}"))

    # 7. TROUBLESHOOTING.md: tofu symptom entry with doc pointer
    if trouble is None:
        results.append(check(7, False, "docs/TROUBLESHOOTING.md missing"))
    else:
        has_sec = bool(re.search(r"## 11\. Phone: nvim / herdr icons show as empty", trouble))
        has_ptr = "PHONE-TERMUX.md" in trouble and "§6" in trouble
        results.append(check(7, has_sec and has_ptr,
                             f"section={has_sec} pointer={has_ptr}"))

    # 8. STATE.md records AD-004
    if state is None:
        results.append(check(8, False, ".specs/STATE.md missing"))
    else:
        has_ad = "### AD-004" in state and "nvim-config (LazyVim) is a FORCED config repo" in state
        has_status = "Status:" in state.split("### AD-004", 1)[1][:200]
        results.append(check(8, has_ad and has_status, "AD-004 entry missing"))

    passed = sum(1 for r in results if r)
    print(f"\n{passed}/{len(results)} PASS")
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
