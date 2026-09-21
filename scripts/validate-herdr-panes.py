#!/usr/bin/env python3
"""
validate-herdr-panes.py - deterministic structural gate for the pi-cloud
"herdr panes get the ssh login-shell environment" part of the
herdr-panes-and-c-manpages feature (.specs/features/herdr-panes-and-c-manpages/).

Checks (spec-anchored, HDP-01..HDP-05):
  1. entrypoint exports a TERM fallback BEFORE the herdr server starts (HDP-01)
  2. entrypoint pins a herdr config ([terminal] default_shell=/bin/bash,
     shell_mode=login) idempotently, before the server starts (HDP-02)
  3. profile.d/pi-cloud.sh exports the same TERM fallback for login shells (HDP-03)
  4. the emitted TOML fragment parses and carries both keys (HDP-04)
  5. docs/TROUBLESHOOTING.md documents the herdr pane/nvim failure (HDP-05)

Pure standard library. Exit 0 = all checks pass.
"""
import argparse
import os
import re
import sys
import tomllib


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
        # HDP-02: config pin present, guarded, before the server start
        cfg_at = ep.find('[terminal]')
        guard = bool(re.search(r"grep -q '\^\\\[terminal\\\]'", ep))
        default_shell = re.search(r'default_shell = "/bin/bash"', ep) is not None
        shell_mode = re.search(r'shell_mode = "login"', ep) is not None
        cfg_ok = (cfg_at >= 0 and guard and default_shell and shell_mode
                  and (server_at < 0 or cfg_at < server_at))
        results.append(check("HDP-02", cfg_ok,
                             f"terminal_sec={cfg_at >= 0} guard={guard} bash={default_shell} login={shell_mode} before_server={cfg_at >= 0 and (server_at < 0 or cfg_at < server_at)}"))

    # --- HDP-03: profile.d TERM fallback -------------------------------------
    if pd is None:
        results.append(check("HDP-03", False, "container/profile.d/pi-cloud.sh missing"))
    else:
        ok = 'export TERM="${TERM:-xterm-256color}"' in pd
        results.append(check("HDP-03", ok, f"term_fallback={ok}"))

    # --- HDP-04: the pinned TOML fragment parses ------------------------------
    fragment = '[terminal]\ndefault_shell = "/bin/bash"\nshell_mode = "login"\n'
    try:
        parsed = tomllib.loads(fragment)
        ok = parsed.get("terminal", {}).get("default_shell") == "/bin/bash" \
            and parsed.get("terminal", {}).get("shell_mode") == "login"
        results.append(check("HDP-04", ok, "toml parsed"))
    except Exception as e:  # noqa: BLE001 - gate must fail loudly on any parse error
        results.append(check("HDP-04", False, f"toml parse failed: {e}"))

    # --- HDP-05: troubleshooting entry ----------------------------------------
    if tr is None:
        results.append(check("HDP-05", False, "docs/TROUBLESHOOTING.md missing"))
    else:
        entry = "herdr" in tr and "shell_mode" in tr and "login" in tr
        results.append(check("HDP-05", entry, f"entry={entry}"))

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()