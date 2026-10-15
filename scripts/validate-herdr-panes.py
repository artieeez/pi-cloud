#!/usr/bin/env python3
"""
validate-herdr-panes.py - deterministic structural gate for the pi-cloud
"herdr panes get the ssh login-shell environment" work. Owns the repo-wiring
and documentation checks; the behavioral half lives in
scripts/validate-herdr-pane-config.sh, which this gate runs.

Checks (spec-anchored, HDP-01..HDP-06):
  1. entrypoint exports a TERM fallback BEFORE the herdr server starts (HDP-01)
  2. entrypoint runs the herdr-pane-config guarantee, guarded so a failure still
     lets sshd start, BEFORE the server starts, and the superseded
     "skip when [terminal] exists" guard is gone (HDP-02)
  3. profile.d/pi-cloud.sh exports the same TERM fallback for login shells (HDP-03)
  4. scripts/validate-herdr-pane-config.sh exits 0 (HDP-04)
  5. docs/TROUBLESHOOTING.md documents the failure, the cause, and the
     on-box remediation (HDP-05)
  6. the app image installs the helper as /usr/local/bin/herdr-pane-config,
     executable (HDP-06)

Pure standard library. Exit 0 = all checks pass.
"""
import argparse
import os
import re
import subprocess
import sys


def check(code, ok, detail=""):
    tag = "PASS" if ok else "FAIL"
    print(f"[{tag}] {code}{(' — ' + detail) if detail and not ok else ''}")
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
    ep = read(args.root, "container/entrypoint.sh")
    pd = read(args.root, "container/profile.d/pi-cloud.sh")
    tr = read(args.root, "docs/TROUBLESHOOTING.md")

    # --- HDP-01 + HDP-02 share the entrypoint scan ---------------------------
    if ep is None:
        results.append(check("HDP-01", False, "container/entrypoint.sh missing"))
        results.append(check("HDP-02", False, "container/entrypoint.sh missing"))
    else:
        server_at = ep.find("setsid herdr server")
        # HDP-01: TERM export present, before the server start
        m = re.search(r"export TERM=\"\$\{TERM:-xterm-256color\}\"", ep)
        term_ok = bool(m) and (server_at < 0 or m.start() < server_at)
        results.append(check("HDP-01", term_ok,
                             f"term_fallback={bool(m)} before_server={server_at < 0 or (m and m.start() < server_at)}"))
        # HDP-02: the config guarantee runs before the server start, and its
        # failure path only warns (sshd must still come up).
        call_at = ep.find("herdr-pane-config")
        guarded = ("if herdr-pane-config" in ep
                   and "WARNING: herdr config guarantee failed" in ep)
        coarse_guard_gone = "grep -q '^\\[terminal\\]'" not in ep
        hdp02 = (call_at >= 0 and guarded and coarse_guard_gone
                 and (server_at < 0 or call_at < server_at))
        results.append(check("HDP-02", hdp02,
                             f"call={call_at >= 0} guarded={guarded} "
                             f"old_guard_gone={coarse_guard_gone} "
                             f"before_server={call_at >= 0 and (server_at < 0 or call_at < server_at)}"))

    # --- HDP-03: profile.d TERM fallback -------------------------------------
    if pd is None:
        results.append(check("HDP-03", False, "container/profile.d/pi-cloud.sh missing"))
    else:
        ok = 'export TERM="${TERM:-xterm-256color}"' in pd
        results.append(check("HDP-03", ok, f"term_fallback={ok}"))

    # --- HDP-04: the behavioral gate runs and passes --------------------------
    behavioral = os.path.join(args.root, "scripts", "validate-herdr-pane-config.sh")
    if not os.path.isfile(behavioral):
        results.append(check("HDP-04", False, "scripts/validate-herdr-pane-config.sh missing"))
    else:
        proc = subprocess.run(["bash", behavioral, "--root", args.root],
                              capture_output=True, text=True)
        summary = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else "no output"
        results.append(check("HDP-04", proc.returncode == 0,
                             f"exit={proc.returncode} {summary}"))

    # --- HDP-05: troubleshooting entry ----------------------------------------
    if tr is None:
        results.append(check("HDP-05", False, "docs/TROUBLESHOOTING.md missing"))
    else:
        needed = ["herdr", "shell_mode", "login", "herdr-pane-config", "reload-config"]
        missing = [n for n in needed if n not in tr]
        results.append(check("HDP-05", not missing, f"missing={missing}"))

    # --- HDP-06: the image installs the helper --------------------------------
    dockerfile = read(args.root, "Dockerfile")
    if dockerfile is None:
        results.append(check("HDP-06", False, "Dockerfile missing"))
    else:
        copied = "container/herdr-pane-config.sh /usr/local/bin/herdr-pane-config" in dockerfile
        executable = re.search(r'chmod \+x[^\n]*/usr/local/bin/herdr-pane-config', dockerfile) is not None
        results.append(check("HDP-06", copied and executable,
                             f"copied={copied} executable={executable}"))

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()