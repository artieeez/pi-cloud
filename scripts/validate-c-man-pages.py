#!/usr/bin/env python3
"""
validate-c-man-pages.py - deterministic structural gate for the pi-cloud
"base ships C programmer man pages" part of the
herdr-panes-and-c-manpages feature (.specs/features/herdr-panes-and-c-manpages/).

Checks (spec-anchored, CMP-01..CMP-05):
  1. base.Dockerfile removes the man path-exclude BEFORE the final-stage apt install (CMP-01)
  2. final-stage apt install carries manpages-dev (the Linux section 2/3 pages:
     printf(3), pthread_create(3)) (CMP-02)
  3. both build workflows pin BASE_TAG ruby-4.0.5-7 (CMP-03)
  4. README advertises C man pages and the new base tag (CMP-04)
  5. docs/TROUBLESHOOTING.md documents the C-library-docs symptom->cause->fix (CMP-05)

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
    bb = read(args.root, ".github/workflows/build-base.yaml")
    bp = read(args.root, ".github/workflows/build-push-ocir.yaml")
    tr = read(args.root, "docs/TROUBLESHOOTING.md")
    tail = final_stage(base_d) if base_d else ""

    # CMP-01: man path-exclude removed, and removed BEFORE the final stage's
    # apt update (the build stage has its own unrelated apt-get update)
    if base_d is None:
        results.append(check("CMP-01", False, "docker/base.Dockerfile missing"))
    else:
        sed_at = tail.find("'\\#path-exclude /usr/share/man/#d'")
        apt_at = tail.find("apt-get update")
        sed_present = sed_at >= 0 and "/etc/dpkg/dpkg.cfg.d/docker" in tail[sed_at:sed_at + 200]
        results.append(check(
            "CMP-01", sed_present and 0 <= sed_at < apt_at,
            f"sed_at={sed_at} apt_at={apt_at}"))

    # CMP-02: C library man pages in the final-stage install list
    if not tail:
        results.append(check("CMP-02", False, "final stage not found"))
    else:
        want = ["manpages-dev"]
        missing = [w for w in want if not has_word(tail, w)]
        results.append(check("CMP-02", not missing,
                             f"missing={missing}" if missing else ""))

    # CMP-03: base re-published as ruby-4.0.5-7, synced across both workflows
    for name, content in (("build-base.yaml", bb), ("build-push-ocir.yaml", bp)):
        if content is None:
            results.append(check("CMP-03", False, f"{name} missing"))
        else:
            new = bool(re.search(r"BASE_TAG:\s*ruby-4\.0\.5-7", content))
            old = "ruby-4.0.5-6" in re.sub(r"#.*", "", content)
            results.append(check("CMP-03", new and not old,
                                 f"{name}: new={new} old_still_pinned={old}"))

    # CMP-04: README advertises C docs + new tag
    if readme is None:
        results.append(check("CMP-04", False, "README.md missing"))
    else:
        docs = "manpages-dev" in readme
        tag = "ruby-4.0.5-7" in readme
        results.append(check("CMP-04", docs and tag,
                             f"c_docs={docs} tag={tag}"))

    # CMP-05: troubleshooting entry documents the failure mode
    if tr is None:
        results.append(check("CMP-05", False, "docs/TROUBLESHOOTING.md missing"))
    else:
        entry = "man 3 printf" in tr and "3 pthread_create" in tr
        results.append(check("CMP-05", entry, f"entry={entry}"))

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()