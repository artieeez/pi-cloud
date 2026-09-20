#!/usr/bin/env python3
"""
validate-man-pages.py - deterministic structural gate for the pi-cloud
less + man pages feature (inline Small-scope spec, recorded in commit).

The box is built on node:bookworm-slim, which ships neither a pager nor man
pages: debuerreotype-slimify deletes man trees and writes a dpkg
path-exclude for /usr/share/man/* in /etc/dpkg/dpkg.cfg.d/docker. The base
image therefore re-enables man pages structurally, and this script pins that
structure so it cannot silently drift (MP-01..MP-04):

  1. base.Dockerfile removes the man path-exclude BEFORE the apt install (MP-01)
  2. final-stage apt install carries less, man-db, groff-base, manpages (MP-02)
  3. base image --reinstall set resurrects the slimified man trees (MP-03)
  4. README states less + man pages are present (MP-04)

Pure standard library. Exit 0 = all checks pass.
"""
import argparse
import os
import re
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


def final_stage(text):
    """Everything after the last 'FROM' line (the final base stage)."""
    idx = text.rfind("\nFROM ")
    return text if idx < 0 else text[idx + 1:]


def has_word(block, word):
    return bool(re.search(rf"\b{re.escape(word)}\b", block))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.getcwd(), help="pi-cloud repo root")
    args = ap.parse_args()

    results = []
    base_d = read(args.root, "docker/base.Dockerfile")
    readme = read(args.root, "README.md")
    tail = final_stage(base_d) if base_d else ""

    # MP-01: man path-exclude removed, and removed BEFORE the final stage's
    # apt update (the build stage has its own unrelated apt-get update)
    if base_d is None:
        results.append(check("MP-01", False, "docker/base.Dockerfile missing"))
    else:
        sed_at = tail.find("'\\#path-exclude /usr/share/man/#d'")
        apt_at = tail.find("apt-get update")
        sed_present = sed_at >= 0 and "/etc/dpkg/dpkg.cfg.d/docker" in tail[sed_at:sed_at + 200]
        results.append(check(
            "MP-01", sed_present and 0 <= sed_at < apt_at,
            f"sed_at={sed_at} apt_at={apt_at}"))

    # MP-02: pager + man toolchain in the final-stage install list
    if not tail:
        results.append(check("MP-02", False, "final stage not found"))
    else:
        want = ["less", "man-db", "groff-base", "manpages"]
        missing = [w for w in want if not has_word(tail, w)]
        results.append(check("MP-02", not missing,
                             f"missing={missing}" if missing else ""))

    # MP-03: --reinstall resurrect set covers the pre-installed base tools
    if not tail:
        results.append(check("MP-03", False, "final stage not found"))
    else:
        m = re.search(r"--reinstall -y\s+(.*?)\s*&&", tail, re.S)
        block = m.group(1) if m else ""
        want = ["bash", "coreutils", "util-linux", "grep", "sed", "tar",
                "gzip", "findutils", "diffutils", "dpkg", "passwd", "login"]
        missing = [w for w in want if not has_word(block, w)]
        results.append(check("MP-03", bool(m) and not missing,
                             f"missing={missing}" if (not m or missing)
                             else f"pkgs={len(want)}"))

    # MP-04: README advertises the tools
    if readme is None:
        results.append(check("MP-04", False, "README.md missing"))
    else:
        ok = re.search(r"(?i)\bless\b", readme) and "man pages" in readme
        results.append(check("MP-04", ok,
                             "less/man missing from README" if not ok else ""))

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()