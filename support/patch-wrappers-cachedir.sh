#!/bin/bash
#===============================================================
#Script Name: patch-wrappers-cachedir.sh
#Date: 09/29/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.2
#Short: Force cachedir in project, auto-roster, and EL7 ssh_ext_alternatives
#About: Dry-run by default. With --apply, patches:
#About:   bin/salt-ssh-el7, bin/salt-ssh-el8, bin/salt-call-el8
#About: Adds a pre-exec block that, when caller did NOT pass -c/--config-dir:
#About:  • If roster missing, auto-creates roster/hosts.yml (template)
#About:  • Writes ${PROJECT_ROOT}/.cache/_wrappers/<name>/master:
#About:       cachedir: ${PROJECT_ROOT}/.cache
#About:       log_file: ${PROJECT_ROOT}/logs/salt-ssh.log
#About:       roster_file: ${PROJECT_ROOT}/roster/hosts.yml
#About:    For salt-ssh-el7 only: adds ssh_ext_alternatives: [2019.2.3]
#About:  • Appends -c <that dir> to final exec
#===============================================================
set -euo pipefail

APPLY=0; VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help)
      cat <<'EOF'
Usage: support/patch-wrappers-cachedir.sh [--apply] [-v]
Dry-run by default; with --apply actually patches wrappers.

Behavior (only when caller did NOT pass -c/--config-dir):
  • Ensures roster/hosts.yml exists (creates a tiny template if missing)
  • Writes .cache/_wrappers/<wrapper>/master with cachedir/log/roster_file
  • For salt-ssh-el7 only: adds ssh_ext_alternatives: [2019.2.3]
  • Appends -c <that dir> to the wrapper's final exec
EOF
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

# Resolve PROJECT_ROOT (EL7-safe)
RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); fi; }
FIND_ROOT_UP(){ local d="$1" i=8; while [ "$i" -gt 0 ] && [ "$d" != "/" ] && [ -n "$d" ]; do if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then echo "$d"; return 0; fi; d="$(dirname -- "$d")"; i=$((i-1)); done; return 1; }
SCRIPT_ABS="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_ABS")"
if [ -n "${SALT_SHAKER_ROOT:-}" ] && [ -d "${SALT_SHAKER_ROOT}" ]; then PROJECT_ROOT="$(RESOLVE_ABS "$SALT_SHAKER_ROOT")"
else PROJECT_ROOT="$(FIND_ROOT_UP "$SCRIPT_DIR" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(FIND_ROOT_UP "$(pwd)" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(RESOLVE_ABS "$(pwd)")"; fi

if [ -t 1 ]; then G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; C='\033[0;36m'; N='\033[0m'; else G=""; Y=""; R=""; C=""; N=""; fi
OK="✓"; WRN="⚠"; ERR="✖"; bar(){ printf "%b%s%b\n" "$C" "══════════════════════════════════════════════════════════════════════" "$N"; }

# Targets
WRAPPERS=()
[ -f "${PROJECT_ROOT}/bin/salt-ssh-el7" ] && WRAPPERS+=( "${PROJECT_ROOT}/bin/salt-ssh-el7" )
[ -f "${PROJECT_ROOT}/bin/salt-ssh-el8" ] && WRAPPERS+=( "${PROJECT_ROOT}/bin/salt-ssh-el8" )
[ -f "${PROJECT_ROOT}/bin/salt-call-el8" ] && WRAPPERS+=( "${PROJECT_ROOT}/bin/salt-call-el8" )
[ ${#WRAPPERS[@]} -eq 0 ] && { echo -e "${R}${ERR} No wrappers under bin/.${N}"; exit 1; }

read -r -d '' PATCH_BLOCK <<'EOS'
# === CACHEDIR_PATCH_v2 (auto-added) ===
ensure_cachedir_patch() {
  # Skip if caller already set -c/--config-dir
  local need_conf=1 a
  for a in "$@"; do case "$a" in -c|--config-dir) need_conf=0;; esac; done
  [ $need_conf -eq 0 ] && return 0

  # Resolve PROJECT_ROOT relative to wrapper
  RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); fi; }
  local SCRIPT_ABS; SCRIPT_ABS="$(RESOLVE_ABS "$0")"
  local WRAP_DIR; WRAP_DIR="$(dirname -- "$SCRIPT_ABS")"
  local ROOT_CAND; ROOT_CAND="$(dirname -- "$WRAP_DIR")"  # project root (bin/ sits here)
  local PROJECT_ROOT_LOCAL="$ROOT_CAND"

  # Ensure roster exists: create minimal template if none found
  mkdir -p "${PROJECT_ROOT_LOCAL}/roster" 2>/dev/null || true
  local RFILE=""
  if [ -f "${PROJECT_ROOT_LOCAL}/roster/hosts.yml" ]; then
    RFILE="${PROJECT_ROOT_LOCAL}/roster/hosts.yml"
  elif [ -f "${PROJECT_ROOT_LOCAL}/roster" ]; then
    RFILE="${PROJECT_ROOT_LOCAL}/roster"
  else
    RFILE="${PROJECT_ROOT_LOCAL}/roster/hosts.yml"
  fi
  if [ ! -f "$RFILE" ]; then
    cat >"$RFILE" <<'YML'
# Minimal roster (created by wrapper). Replace "myhost" with your target(s).
# Example usage:
#   bin/salt-ssh-el8 myhost test.ping
myhost:
  host: 127.0.0.1
  user: root
  port: 22
  passwd: ""
  sudo: false
  tty: true
YML
  fi

  # Prepare tiny master in .cache/_wrappers/<name>
  local NAME; NAME="$(basename -- "$0")"
  local CONF_DIR="${PROJECT_ROOT_LOCAL}/.cache/_wrappers/${NAME}"
  mkdir -p "$CONF_DIR" 2>/dev/null || true

  {
    echo "cachedir: ${PROJECT_ROOT_LOCAL}/.cache"
    echo "log_file: ${PROJECT_ROOT_LOCAL}/logs/salt-ssh.log"
    echo "roster_file: ${RFILE}"
  } > "${CONF_DIR}/master"

  # If this is the EL7 wrapper, hint Salt to use legacy thin compatibility
  case "$NAME" in
    salt-ssh-el7)
      printf "%s\n" "ssh_ext_alternatives:" >> "${CONF_DIR}/master"
      printf "  - %s\n" "2019.2.3" >> "${CONF_DIR}/master"
      ;;
  esac

  export SALT_SHAKER_CONF_DIR="$CONF_DIR"
  echo "-c" "$CONF_DIR"
}
EOS

apply_patch_to_file() {
  local f="$1"
  file "$f" 2>/dev/null | grep -qi 'text' || return 2
  grep -q 'CACHEDIR_PATCH_v2' "$f" && { [ $VERBOSE -eq 1 ] && echo -e "${Y}${WRN} already patched: ${f#$PROJECT_ROOT/}${N}"; return 0; }

  local tmp="${f}.new"; local bak="${f}.bak.cache"
  cp -p "$f" "$bak"

  local first; first="$(head -n1 "$f" || true)"
  if echo "$first" | grep -q '^#!'; then
    { head -n1 "$f"; echo "$PATCH_BLOCK"; tail -n +2 "$f"; } > "$tmp"
  else
    { echo "$PATCH_BLOCK"; echo; cat "$f"; } > "$tmp"
  fi

  # Rewrite last exec line to append -c produced by ensure_cachedir_patch
  if grep -q 'exec .*"\$@"' "$tmp"; then
    tac "$tmp" | sed -e '0,/exec /s//__PATCH_LAST_EXEC__ /' | tac > "${tmp}.m"
    sed -e 's#__PATCH_LAST_EXEC__ #EXTRA_C_ARGS=$(ensure_cachedir_patch "$@"); &#' \
        -e 's#exec \(.*\) "\$@"#exec \1 ${EXTRA_C_ARGS} "$@"#' \
        "${tmp}.m" > "${tmp}.p"
    mv "${tmp}.p" "$tmp"; rm -f "${tmp}.m"
  elif grep -q 'exec ' "$tmp"; then
    tac "$tmp" | sed -e '0,/exec /s//__PATCH_LAST_EXEC__ /' | tac > "${tmp}.m"
    sed -e 's#__PATCH_LAST_EXEC__ #EXTRA_C_ARGS=$(ensure_cachedir_patch "$@"); &#' \
        -e 's#exec \(.*\)#exec \1 ${EXTRA_C_ARGS}#' \
        "${tmp}.m" > "${tmp}.p"
    mv "${tmp}.p" "$tmp"; rm -f "${tmp}.m"
  fi

  mv "$tmp" "$f"
  chmod +x "$f" 2>/dev/null || true
  [ $VERBOSE -eq 1 ] && echo -e "${G}${OK} patched: ${f#$PROJECT_ROOT/} (bak: $(basename "$bak"))${N}"
  return 0
}

bar
echo "▶ Patch wrappers cachedir (dry-run=$([ $APPLY -eq 1 ] && echo no || echo yes))"
echo "Project Root: ${PROJECT_ROOT}"
bar

FAILED=0; COUNT=0
for w in "${WRAPPERS[@]}"; do
  if [ $APPLY -eq 1 ]; then apply_patch_to_file "$w" || FAILED=1
  else echo " - would patch: ${w#$PROJECT_ROOT/}"; fi
  COUNT=$((COUNT+1))
done

bar
if [ $APPLY -eq 1 ]; then
  [ $FAILED -eq 0 ] && echo -e "${G}${OK} Wrappers patched (${COUNT} file(s)).${N}" || echo -e "${R}${ERR} Patch completed with errors.${N}"
else
  echo -e "${OK} Dry-run only. Use --apply to modify."
fi
bar
exit $FAILED

