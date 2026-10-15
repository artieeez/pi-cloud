#!/usr/bin/env bash
# herdr-pane-config: guarantee the herdr pane login-shell keys.
#
# Usage: herdr-pane-config [CONFIG_PATH]
#        (default: ${HOME}/.config/herdr/config.toml)
#
# herdr's shell_mode default is "auto", which spawns non-login shells on Linux.
# Those panes never source /etc/profile.d/pi-cloud.sh, so they lose the
# toolchain PATH (/opt/nvim/bin), PI_CLOUD, and the sealed-key exports.
# This script guarantees, and only guarantees:
#
#   [terminal]
#   default_shell = "/bin/bash"
#   shell_mode = "login"
#
# Every other line is preserved byte for byte, and a config that already holds
# the required values is left alone without a rewrite. A layout that cannot be
# edited safely (duplicate [terminal] sections, or root-level terminal.* dotted
# keys) is refused with exit 1 and the file untouched, so a working config is
# never corrupted by a guess. The entrypoint treats any failure as non-fatal.
#
# bash + awk only: the box image ships no python3.

set -euo pipefail

REQ_DEFAULT_SHELL='/bin/bash'
REQ_SHELL_MODE='login'
# TOML literal forms, for value comparison and canonical output.
TOML_DEFAULT_SHELL="\"${REQ_DEFAULT_SHELL}\""
TOML_SHELL_MODE="\"${REQ_SHELL_MODE}\""
SQ="'"

die() { printf 'herdr-pane-config: %s\n' "$*" >&2; exit 1; }
log() { printf 'herdr-pane-config: %s\n' "$*"; }

# analyze FILE: print the layout as key=value lines.
#   sections                  [terminal] header count
#   in_section_default_shell  default_shell assignments inside [terminal]
#   in_section_shell_mode     shell_mode assignments inside [terminal]
#   default_shell_ok          the in-section value equals the required value
#   shell_mode_ok             the in-section value equals the required value
#   root_dotted               a terminal.default_shell / terminal.shell_mode
#                             dotted key outside every table
#   array_terminal            an [[terminal]] array-of-tables header
analyze() {
  awk -v ds="${TOML_DEFAULT_SHELL}" -v sm="${TOML_SHELL_MODE}" -v q="${SQ}" '
    function strip(v) { gsub(/^[[:space:]]+/, "", v); gsub(/[[:space:]]+$/, "", v); return v }
    function strip_comment(line) { sub(/[[:space:]]*#.*$/, "", line); return strip(line) }
    function header_name(line,   inner) {
      inner = strip(substr(line, 2, length(line) - 2))
      gsub(/"/, "", inner); gsub(q, "", inner)
      return inner
    }
    function key_name(line,   i, k) {
      i = index(line, "=")
      if (i <= 1) return ""
      k = strip(substr(line, 1, i - 1))
      gsub(/"/, "", k); gsub(q, "", k)
      return k
    }
    function value_of(line,   i, v) {
      i = index(line, "=")
      v = substr(line, i + 1)
      sub(/[[:space:]]+#.*$/, "", v)
      return strip(v)
    }
    BEGIN { sec = 0; any_sec = 0; secs = 0; ds_n = 0; sm_n = 0; ds_ok = 0; sm_ok = 0; dotted = 0; array = 0 }
    {
      line = $0
      header = strip_comment(line)
      if (header ~ /^\[.*\]$/) {
        any_sec = 1
        name = header_name(header)
        if (name == "terminal") { sec = 1; secs++ } else { sec = 0 }
        if (name == "[terminal]") array = 1
        next
      }
      key = key_name(line)
      if (key == "default_shell") {
        if (sec) { ds_n++; if (value_of(line) == ds) ds_ok = 1 }
        next
      }
      if (key == "shell_mode") {
        if (sec) { sm_n++; if (value_of(line) == sm) sm_ok = 1 }
        next
      }
      if (!any_sec && (key == "terminal.default_shell" || key == "terminal.shell_mode")) dotted = 1
    }
    END {
      printf "sections=%d\n", secs
      printf "in_section_default_shell=%d\n", ds_n
      printf "in_section_shell_mode=%d\n", sm_n
      printf "default_shell_ok=%d\n", ds_ok
      printf "shell_mode_ok=%d\n", sm_ok
      printf "root_dotted=%d\n", dotted
      printf "array_terminal=%d\n", array
    }
  ' "$1"
}

# field FILE KEY: read one analyze field.
field() {
  analyze "$1" | awk -F= -v k="$2" '$1 == k { print $2; exit }'
}

# emit FILE INS_DS INS_SM: print FILE with the [terminal] keys guaranteed.
# INS_* = 1 inserts the key just after the [terminal] header (it is absent from
# that section); a key that is present is normalised in place only when its
# value differs, so a compliant key keeps its exact original line.
emit() {
  awk -v ds="${TOML_DEFAULT_SHELL}" -v sm="${TOML_SHELL_MODE}" -v q="${SQ}" \
      -v ins_ds="$2" -v ins_sm="$3" '
    function strip(v) { gsub(/^[[:space:]]+/, "", v); gsub(/[[:space:]]+$/, "", v); return v }
    function strip_comment(line) { sub(/[[:space:]]*#.*$/, "", line); return strip(line) }
    function header_name(line,   inner) {
      inner = strip(substr(line, 2, length(line) - 2))
      gsub(/"/, "", inner); gsub(q, "", inner)
      return inner
    }
    function key_name(line,   i, k) {
      i = index(line, "=")
      if (i <= 1) return ""
      k = strip(substr(line, 1, i - 1))
      gsub(/"/, "", k); gsub(q, "", k)
      return k
    }
    function value_of(line,   i, v) {
      i = index(line, "=")
      v = substr(line, i + 1)
      sub(/[[:space:]]+#.*$/, "", v)
      return strip(v)
    }
    BEGIN { sec = 0 }
    {
      line = $0
      cr = (line ~ /\r$/) ? "\r" : ""
      header = strip_comment(line)
      if (header ~ /^\[.*\]$/) {
        sec = (header_name(header) == "terminal") ? 1 : 0
        print line
        if (sec && ins_ds) print "default_shell = " ds cr
        if (sec && ins_sm) print "shell_mode = " sm cr
        next
      }
      if (sec) {
        key = key_name(line)
        if (key == "default_shell") {
          if (value_of(line) == ds) print line; else print "default_shell = " ds cr
          next
        }
        if (key == "shell_mode") {
          if (value_of(line) == sm) print line; else print "shell_mode = " sm cr
          next
        }
      }
      print line
    }
  ' "$1"
}

# validate FILE: exit 0 only when FILE carries exactly one [terminal] section
# with both required keys at their required values and no refused layout.
validate() {
  local file=$1
  [ "$(field "${file}" sections)" = "1" ] || return 1
  [ "$(field "${file}" in_section_default_shell)" = "1" ] || return 1
  [ "$(field "${file}" in_section_shell_mode)" = "1" ] || return 1
  [ "$(field "${file}" default_shell_ok)" = "1" ] || return 1
  [ "$(field "${file}" shell_mode_ok)" = "1" ] || return 1
  [ "$(field "${file}" root_dotted)" = "0" ] || return 1
  return 0
}

main() {
  local target="${1:-${HOME:-/root}/.config/herdr/config.toml}"
  local dir tmp sections
  [ -n "${target}" ] || die "empty config path"
  if [ -d "${target}" ]; then die "config path is a directory: ${target}"; fi
  dir="$(dirname "${target}")"

  mkdir -p "${dir}" || die "cannot create ${dir}"
  tmp="$(mktemp "${dir}/.herdr-pane-config.XXXXXX")" || die "cannot create a temp file in ${dir}"
  trap "rm -f '${tmp}'" EXIT

  if [ ! -f "${target}" ]; then
    {
      printf '[terminal]\n'
      printf 'default_shell = "%s"\n' "${REQ_DEFAULT_SHELL}"
      printf 'shell_mode = "%s"\n' "${REQ_SHELL_MODE}"
    } > "${tmp}"
    validate "${tmp}" || die "the generated config for a missing file did not validate"
    chmod 0644 "${tmp}"
    mv -f "${tmp}" "${target}" || die "cannot write ${target}"
    log "created ${target} with the [terminal] login-shell keys"
    return 0
  fi

  sections="$(field "${target}" sections)"
  [ "${sections}" -le 1 ] || die "refusing to edit ${target}: ${sections} [terminal] sections declared (repair by hand)"
  [ "$(field "${target}" root_dotted)" = "0" ] || die "refusing to edit ${target}: terminal.* dotted keys outside [terminal] (repair by hand)"
  [ "$(field "${target}" array_terminal)" = "0" ] || die "refusing to edit ${target}: [[terminal]] array-of-tables cannot take a [terminal] table (repair by hand)"

  if [ "${sections}" = "0" ]; then
    {
      cat "${target}"
      printf '\n[terminal]\n'
      printf 'default_shell = "%s"\n' "${REQ_DEFAULT_SHELL}"
      printf 'shell_mode = "%s"\n' "${REQ_SHELL_MODE}"
    } > "${tmp}"
  else
    local ds_n sm_n ds_ok sm_ok
    ds_n="$(field "${target}" in_section_default_shell)"
    sm_n="$(field "${target}" in_section_shell_mode)"
    ds_ok="$(field "${target}" default_shell_ok)"
    sm_ok="$(field "${target}" shell_mode_ok)"
    if [ "${ds_n}" = "1" ] && [ "${ds_ok}" = "1" ] && [ "${sm_n}" = "1" ] && [ "${sm_ok}" = "1" ]; then
      log "already guaranteed: ${target} (no change)"
      return 0
    fi
    emit "${target}" "$([ "${ds_n}" = "0" ] && printf 1 || printf 0)" "$([ "${sm_n}" = "0" ] && printf 1 || printf 0)" > "${tmp}"
  fi

  if cmp -s "${target}" "${tmp}"; then
    log "already guaranteed: ${target} (no change)"
    return 0
  fi

  validate "${tmp}" || die "refusing to write ${target}: the edited config did not validate"

  cp -p "${target}" "${target}.bak-pi-cloud" || die "cannot back up ${target}"
  chmod --reference="${target}" "${tmp}"
  mv -f "${tmp}" "${target}" || die "cannot write ${target}"
  log "guaranteed the [terminal] login-shell keys in ${target} (previous content at ${target}.bak-pi-cloud)"
  return 0
}

main "$@"
