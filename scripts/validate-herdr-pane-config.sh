#!/usr/bin/env bash
# Behavioral gate for container/herdr-pane-config.sh
# (.specs/features/herdr-pane-config-guarantee/, HPC-02..HPC-13).
#
# Runs the shipped helper against fixture configs and asserts the spec-defined
# outcome for each: the two required [terminal] keys, byte-preservation of
# unrelated config, idempotence, and both refusal paths. bash + awk only, so it
# runs on the box (the image ships no python3). When python3 is available it
# additionally parses every repaired fixture with tomllib.
#
# Usage: bash scripts/validate-herdr-pane-config.sh [--root DIR]
# Exit 0 = all checks pass.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    *) printf 'usage: %s [--root DIR]\n' "$0" >&2; exit 2 ;;
  esac
done

HELPER="${ROOT}/container/herdr-pane-config.sh"
PROFILE="${ROOT}/container/profile.d/pi-cloud.sh"
GATE="${ROOT}/scripts/validate-herdr-pane-config.sh"

passed=0
failed=0
check() { # check CODE OK [DETAIL]
  if [ "$2" = "1" ]; then
    passed=$((passed + 1))
    printf '[PASS] %s\n' "$1"
  else
    failed=$((failed + 1))
    printf '[FAIL] %s%s\n' "$1" "${3:+: $3}"
  fi
}

if [ ! -f "${HELPER}" ]; then
  printf '[FAIL] HPC-10: helper missing at %s\n' "${HELPER}"
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

norm() { tr -d '\r' < "$1"; }
sections() { norm "$1" | grep -cE '^[[:space:]]*\[terminal\][[:space:]]*$'; }
key_count() { norm "$1" | grep -cE "^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"$3\"[[:space:]]*$"; }
unchanged() { cmp -s "$1" "$2"; }
md5() { md5sum < "$1" | cut -d' ' -f1; }

# --- HPC-10: pure bash + awk, no interpreter dependency ---------------------
if grep -nE '^[^#]*\b(python3?|node|npx|ruby)\b' "${HELPER}" >/dev/null; then
  check "HPC-10 helper has no python/node/ruby dependency" 0 "interpreter call found"
else
  check "HPC-10 helper has no python/node/ruby dependency" 1
fi
check "HPC-13 the python3 TOML check is optional" \
  "$(grep -q 'if command -v python3' "${GATE}" && printf 1 || printf 0)"

# --- HPC-04: missing, empty, and unrelated-only configs --------------------
run_missing() {
  local f="${work}/missing.toml"
  bash "${HELPER}" "${f}" >/dev/null 2>&1 || { check "HPC-04 missing config created" 0 "helper exit $?"; return; }
  check "HPC-04 missing config created with both keys" \
    "$([ "$(sections "${f}")" = "1" ] && [ "$(key_count "${f}" default_shell /bin/bash)" = "1" ] && [ "$(key_count "${f}" shell_mode login)" = "1" ] && printf 1 || printf 0)"
}

run_empty() {
  local f="${work}/empty.toml"
  : > "${f}"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "HPC-04 empty config gains [terminal] with both keys" \
    "$([ "$(sections "${f}")" = "1" ] && [ "$(key_count "${f}" default_shell /bin/bash)" = "1" ] && [ "$(key_count "${f}" shell_mode login)" = "1" ] && printf 1 || printf 0)"
}

run_unrelated() {
  local f="${work}/unrelated.toml"
  printf 'onboarding = false\n\n[theme]\nname = "catppuccin"\n' > "${f}"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "HPC-04 unrelated-only config appends [terminal] and keeps its lines" \
    "$([ "$(sections "${f}")" = "1" ] && [ "$(key_count "${f}" shell_mode login)" = "1" ] && grep -q '^onboarding = false$' "${f}" && grep -q '^name = "catppuccin"$' "${f}" && printf 1 || printf 0)"
}

# --- HPC-02 + HPC-08: the live-box shape ([terminal] present, no shell_mode)-
run_live_shape() {
  local f="${work}/live-shape.toml" before="${work}/live-shape.before"
  printf '[terminal]\ndefault_shell = "bash"\n\n[theme]\nname = "catppuccin"\nauto_switch = false\n' > "${f}"
  cp "${f}" "${before}"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "HPC-02 pre-existing [terminal] gains shell_mode=login and default_shell=/bin/bash" \
    "$([ "$(sections "${f}")" = "1" ] && [ "$(key_count "${f}" default_shell /bin/bash)" = "1" ] && [ "$(key_count "${f}" shell_mode login)" = "1" ] && printf 1 || printf 0)"
  check "HPC-02 unrelated sections stay byte-identical" \
    "$(diff -q <(sed -n '/^\[theme\]/,$p' "${before}") <(sed -n '/^\[theme\]/,$p' "${f}") >/dev/null && printf 1 || printf 0)"
  check "HPC-08 previous content kept at <config>.bak-pi-cloud" \
    "$([ -f "${f}.bak-pi-cloud" ] && unchanged "${before}" "${f}.bak-pi-cloud" && printf 1 || printf 0)"
}

# --- HPC-03: idempotence, including a non-canonical but compliant ordering --
run_idempotent() {
  local f="${work}/idempotent.toml" before
  printf '[terminal]\ndefault_shell = "/bin/bash"\nshell_mode = "login"\n\n[theme]\nname = "catppuccin"\n' > "${f}"
  before="$(md5 "${f}")"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "HPC-03 compliant config is not rewritten" "$([ "${before}" = "$(md5 "${f}")" ] && printf 1 || printf 0)"
  [ -f "${f}.bak-pi-cloud" ] && check "HPC-03 compliant config writes no backup" 0 "backup created" || check "HPC-03 compliant config writes no backup" 1
}

run_reordered() {
  local f="${work}/reordered.toml" before
  printf '[terminal]\nshell_mode = "login"\ndefault_shell = "/bin/bash"\n' > "${f}"
  before="$(md5 "${f}")"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "HPC-03 key order of a compliant config is preserved" "$([ "${before}" = "$(md5 "${f}")" ] && printf 1 || printf 0)"
}

run_single_quoted() {
  local f="${work}/single-quoted.toml" before
  printf "[terminal]\ndefault_shell = '/bin/bash'\nshell_mode = 'login'\n" > "${f}"
  before="$(md5 "${f}")"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "HPC-03 single-quoted but compliant values are preserved" "$([ "${before}" = "$(md5 "${f}")" ] && printf 1 || printf 0)"
  local g="${work}/single-quoted-wrong.toml"
  printf "[terminal]\ndefault_shell = '/bin/bash'\nshell_mode = 'non_login'\n" > "${g}"
  bash "${HELPER}" "${g}" >/dev/null 2>&1
  check "HPC-02 single-quoted non-conforming value is forced to login" \
    "$([ "$(key_count "${g}" shell_mode login)" = "1" ] && printf 1 || printf 0)"
}

# --- HPC-02: non-conforming values are forced, other keys survive ----------
run_forced() {
  local f="${work}/forced.toml"
  printf '[terminal]\ndefault_shell = "bash"\nshell_mode = "auto"\nkitty_graphics = true\n' > "${f}"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "HPC-02 auto/non-login values forced to login, sibling keys kept" \
    "$([ "$(key_count "${f}" shell_mode login)" = "1" ] && [ "$(key_count "${f}" default_shell /bin/bash)" = "1" ] && grep -q '^kitty_graphics = true$' "${f}" && printf 1 || printf 0)"
}

# --- HPC-05 + HPC-06: refusal paths leave the file untouched ---------------
run_duplicate() {
  local f="${work}/duplicate.toml"
  local before="${work}/duplicate.before"
  printf '[terminal]\nshell_mode = "login"\n\n[terminal]\ndefault_shell = "/bin/bash"\n' > "${f}"
  cp "${f}" "${before}"
  if bash "${HELPER}" "${f}" >/dev/null 2>&1; then
    check "HPC-06 duplicate [terminal] refused" 0 "helper exited 0"
  else
    check "HPC-06 duplicate [terminal] refused untouched" "$(unchanged "${f}" "${before}" && printf 1 || printf 0)"
  fi
}

run_dotted() {
  local f="${work}/dotted.toml"
  local before="${work}/dotted.before"
  printf 'terminal.shell_mode = "auto"\nonboarding = false\n' > "${f}"
  cp "${f}" "${before}"
  if bash "${HELPER}" "${f}" >/dev/null 2>&1; then
    check "HPC-05 root-level terminal.* dotted keys refused" 0 "helper exited 0"
  else
    check "HPC-05 root-level terminal.* dotted keys refused untouched" "$(unchanged "${f}" "${before}" && printf 1 || printf 0)"
  fi
}

# --- Edge cases: no trailing newline, foreign table key, CRLF, unwritable ---
run_no_newline() {
  local f="${work}/no-newline.toml"
  printf '[terminal]\ndefault_shell = "/bin/bash"' > "${f}"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "edge: [terminal] without trailing newline is repaired" \
    "$([ "$(key_count "${f}" shell_mode login)" = "1" ] && printf 1 || printf 0)"
}

run_foreign_key() {
  local f="${work}/foreign.toml"
  printf '[ui]\nshell_mode = "widget"\n' > "${f}"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "edge: same key name in another table is left untouched" \
    "$(grep -q '^shell_mode = "widget"$' "${f}" && [ "$(key_count "${f}" shell_mode login)" = "1" ] && printf 1 || printf 0)"
}

run_crlf() {
  local f="${work}/crlf.toml"
  printf '[terminal]\r\ndefault_shell = "bash"\r\n' > "${f}"
  bash "${HELPER}" "${f}" >/dev/null 2>&1
  check "edge: CRLF config is repaired without a second [terminal]" \
    "$([ "$(sections "${f}")" = "1" ] && [ "$(key_count "${f}" shell_mode login)" = "1" ] && printf 1 || printf 0)"
}

run_unwritable() {
  bash "${HELPER}" /proc/herdr-pane-config-gate/config.toml >/dev/null 2>&1 && check "edge: unwritable path fails loudly" 0 "helper exited 0" \
    || check "edge: unwritable path fails loudly" 1
}

# --- HPC-09: PATH provenance of the login shell the keys enable ------------
check "HPC-09 profile.d puts /opt/nvim/bin on the login-shell PATH" \
  "$(grep -q '/opt/nvim/bin' "${PROFILE}" && printf 1 || printf 0)"

for fn in run_missing run_empty run_unrelated run_live_shape run_idempotent run_reordered run_single_quoted \
          run_forced run_duplicate run_dotted run_no_newline run_foreign_key run_crlf run_unwritable; do
  "${fn}"
done

# --- Optional: TOML validity of every repaired fixture ---------------------
if command -v python3 >/dev/null 2>&1; then
  if python3 - "${work}" <<'PY'
import pathlib, sys, tomllib
bad = []
for path in sorted(pathlib.Path(sys.argv[1]).glob("*.toml")):
    if path.name in ("duplicate.toml", "dotted.toml"):
        continue  # refusal fixtures keep their original, unparsable-by-design layout
    try:
        doc = tomllib.loads(path.read_text())
    except Exception as exc:  # noqa: BLE001 - gate must fail loudly
        bad.append(f"{path.name}: {exc}")
        continue
    terminal = doc.get("terminal", {})
    if terminal.get("default_shell") != "/bin/bash" or terminal.get("shell_mode") != "login":
        bad.append(f"{path.name}: terminal={terminal}")
if bad:
    print("\n".join(bad))
    sys.exit(1)
PY
  then
    check "edge: every repaired fixture parses as TOML with the required keys" 1
  else
    check "edge: every repaired fixture parses as TOML with the required keys" 0 "see details above"
  fi
else
  printf '[SKIP] TOML parse check (no python3 on this host)\n'
fi

printf '\nvalidate-herdr-pane-config: %d passed, %d failed\n' "${passed}" "${failed}"
[ "${failed}" = "0" ] || exit 1
exit 0
