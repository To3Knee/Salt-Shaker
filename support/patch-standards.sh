#!/bin/bash
#===============================================================
#Script Name: patch-wrappers-cachedir.sh
#Date: 09/29/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Auto-patch wrappers to use cachedir=${PROJECT_ROOT}/.cache
#About: Injects a small pre-exec block into bin/salt-{ssh,call}-el{7,8}
#About: If user did NOT pass -c/--config-dir and a roster file exists,
#About: create ${PROJECT_ROOT}/.cache/_wrappers/<name>/master with:
#About:   cachedir: ${PROJECT_ROOT}/.cache
#About:   log_file: ${PROJECT_ROOT}/logs/salt-ssh.log
#About:   roster_file: <detected roster>
#About: Then add -c <that conf> to the exec line. EL7-safe. Idempotent.
#===============================================================
set -euo pipefail

APPLY=0
VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help)
      cat <<'EOF'
Usage: support/patch-wrappers-cachedir.sh [--apply] [-v]

Dry-run by default. With --apply:
  * Patches bin/salt-ssh-el7, bin/salt-ssh-el8, bin/salt-call-el8
  * Adds a pre-exec block that:
      - Detects if -c/--config-dir is present in user args; if yes, does nothing.
      - Else, if a roster file exists (roster/hosts.yml or roster), writes
        ${PROJECT_ROOT}/.cache/_wrappers/<name>/master with cachedir & roster
        and appends -c <that dir> to the exec.

Never touches logic outside of this, keeps .bak of original files.
EOF
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

# --- Resolve PROJECT_ROOT (EL7-safe) ---
RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); fi; }
FIND_ROOT_UP(){ local d="$1" i=8; while [ "$i" -gt 0 ] && [ -n "$d" ] && [ "$d" != "/" ]; do if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then echo "$d"; return 0; fi; d="$(dirname -- "$d")"; i=$((i-1)); done; return 1; }
SCRIPT_ABS="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_ABS")"
if [ -n "${SALT_SHAKER_ROOT:-}" ] && [ -d "${SALT_SHAKER_ROOT}" ]; then PROJECT_ROOT="$(RESOLVE_ABS "$SALT_SHAKER_ROOT")"
else PROJECT_ROOT="$(FIND_ROOT_UP "$SCRIPT_DIR" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(FIND_ROOT_UP "$(pwd)" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(RESOLVE_ABS "$(pwd)")"; fi

# --- Colors ---
if [ -t 1 ]; then G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'; else G=""; Y=""; R=""; C=""; B=""; N=""; fi
OK="✓"; WRN="⚠"; ERR="✖"
bar(){ printf "%b%s%b\n" "$C" "══════════════════════════════════════════════════════════════════════" "$N"; }

# --- Targets ---
WRAPPERS=()
[ -f "${PROJECT_ROOT}/bin/salt-ssh-el7" ] && WRAPPERS+=( "${PROJECT_ROOT}/bin/salt-ssh-el7" )
[ -f "${PROJECT_ROOT}/bin/salt-ssh-el8" ] && WRAPPERS+=( "${PROJECT_ROOT}/bin/salt-ssh-el8" )
[ -f "${PROJECT_ROOT}/bin/salt-call-el8" ] && WRAPPERS+=( "${PROJECT_ROOT}/bin/salt-call-el8" )

[ ${#WRAPPERS[@]} -eq 0 ] && { echo -e "${R}${ERR} No wrappers found under bin/.${N}"; exit 1; }

# --- Patch snippet (marker ensures idempotency) ---
read -r -d '' PATCH_BLOCK <<'EOS'
# === CACHEDIR_PATCH_v1 (auto-added) ===
# Ensure cachedir stays inside project without forcing -c if the caller already set it.
# If no -c/--config-dir provided and a roster file exists, create a tiny master under .cache/_wrappers/<name>
# with cachedir + roster_file, then pass -c <that dir> to salt-*.
ensure_cachedir_patch() {
  # Detect if user already passed -c/--config-dir
  local want_conf=1 a
  for a in "$@"; do
    case "$a" in
      -c|--config-dir) want_conf=0; break;;
    esac
  done
  [ $want_conf -eq 0 ] && return 0

  # Resolve PROJECT_ROOT like wrappers do
  RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); fi; }
  local SCRIPT_ABS; SCRIPT_ABS="$(RESOLVE_ABS "$0")"
  local WRAP_DIR; WRAP_DIR="$(dirname -- "$SCRIPT_ABS")"
  local CAND   # walk up a few levels to find project root (bin/ is at root)
  CAND="$(dirname -- "$WRAP_DIR")"
  [ -d "${CAND}/modules" ] || CAND="$(pwd)"
  local PROJECT_ROOT_LOCAL="$CAND"

  # Find roster (if none, skip adding -c)
  local ROST1="${PROJECT_ROOT_LOCAL}/roster/hosts.yml"
  local ROST2="${PROJECT_ROOT_LOCAL}/roster"
  local RFILE=""
  [ -f "$ROST1" ] && RFILE="$ROST1"
  [ -z "$RFILE" ] && [ -f "$ROST2" ] && RFILE="$ROST2"
  [ -z "$RFILE" ] && return 0

  # Prepare wrapper conf
  local NAME; NAME="$(basename -- "$0")"
  local CONF_DIR="${PROJECT_ROOT_LOCAL}/.cache/_wrappers/${NAME}"
  mkdir -p "$CONF_DIR" 2>/dev/null || true
  {
    echo "cachedir: ${PROJECT_ROOT_LOCAL}/.cache"
    echo "log_file: ${PROJECT_ROOT_LOCAL}/logs/salt-ssh.log"
    echo "roster_file: ${RFILE}"
  } > "${CONF_DIR}/master"
  # Export an extra var the wrapper launcher can read (not required)
  export SALT_SHAKER_CONF_DIR="$CONF_DIR"

  # Return the new args with -c appended
  echo "-c" "$CONF_DIR"
}
EOS

apply_patch_to_file() {
  local f="$1"
  # skip if not a text file
  file "$f" 2>/dev/null | grep -qi 'text' || return 2
  # idempotency
  if grep -q 'CACHEDIR_PATCH_v1' "$f"; then
    [ $VERBOSE -eq 1 ] && echo -e "${Y}${WRN} already patched:${N} ${f#$PROJECT_ROOT/}"
    return 0
  fi

  # We need to: (1) insert function above main body; (2) wrap the final exec to append returned -c args
  # Strategy: after the shebang line, insert PATCH_BLOCK; then replace the last 'exec ' line.
  local tmp="${f}.new"; local bak="${f}.bak.cache"

  # Find shebang
  local first
  first="$(head -n1 "$f")"
  cp -p "$f" "$bak"

  # 1) insert block after shebang (or prepend if none)
  if echo "$first" | grep -q '^#!'; then
    { head -n1 "$f"; echo "$PATCH_BLOCK"; tail -n +2 "$f"; } > "$tmp"
  else
    { echo "$PATCH_BLOCK"; echo; cat "$f"; } > "$tmp"
  fi

  # 2) modify exec line: capture params and append ensure_cachedir_patch "$@"
  #    We only rewrite the *last* exec line to keep semantics.
  #    Replace: exec "..." "$@"
  #    With   : EXTRA_C_ARGS=$(ensure_cachedir_patch "$@"); exec "..." ${EXTRA_C_ARGS} "$@"
  if grep -q 'exec .*"\$@"' "$tmp"; then
    # Use sed to replace ONLY the last occurrence
    # Create a marker on the last exec line first
    awk '{print} END{print ""}' "$tmp" >/dev/null
    # Mark last exec line
    tac "$tmp" | sed -e '0,/exec /s//__PATCH_LAST_EXEC__ /' | tac > "${tmp}.m"
    # Now replace the marked line
    sed -e 's#__PATCH_LAST_EXEC__ #EXTRA_C_ARGS=$(ensure_cachedir_patch "$@"); &#' \
        -e 's#exec \(.*\) "\$@"#exec \1 ${EXTRA_C_ARGS} "$@"#' \
        "${tmp}.m" > "${tmp}.p"
    mv "${tmp}.p" "$tmp"
    rm -f "${tmp}.m"
  else
    # If pattern not found, try a more generic "$@" exec
    if grep -q 'exec ' "$tmp"; then
      # same tactic: last 'exec '
      tac "$tmp" | sed -e '0,/exec /s//__PATCH_LAST_EXEC__ /' | tac > "${tmp}.m"
      sed -e 's#__PATCH_LAST_EXEC__ #EXTRA_C_ARGS=$(ensure_cachedir_patch "$@"); &#' \
          -e 's#exec \(.*\)#exec \1 ${EXTRA_C_ARGS}#' \
          "${tmp}.m" > "${tmp}.p"
      mv "${tmp}.p" "$tmp"
      rm -f "${tmp}.m"
    else
      # no exec? leave file as is but keep backup
      mv "$tmp" "$f"
      [ $VERBOSE -eq 1 ] && echo -e "${Y}${WRN} no exec line found, patch skipped:${N} ${f#$PROJECT_ROOT/}"
      return 0
    fi
  fi

  mv "$tmp" "$f"
  chmod +x "$f" 2>/dev/null || true
  [ $VERBOSE -eq 1 ] && echo -e "${G}${OK} patched:${N} ${f#$PROJECT_ROOT/} (bak: $(basename "$bak"))"
  return 0
}

bar
echo "▶ Patch wrappers cachedir (dry-run=$([ $APPLY -eq 1 ] && echo no || echo yes))"
echo "Project Root: ${PROJECT_ROOT}"
bar

FAILED=0; COUNT=0
for w in "${WRAPPERS[@]}"; do
  if [ $APPLY -eq 1 ]; then
    apply_patch_to_file "$w" || FAILED=1
  else
    echo " - would patch: ${w#$PROJECT_ROOT/}"
  fi
  COUNT=$((COUNT+1))
done

bar
if [ $APPLY -eq 1 ]; then
  [ $FAILED -eq 0 ] && echo -e "${G}${OK} Wrappers patched (${COUNT} file(s)).${N}" || echo -e "${R}${ERR} Patch completed with errors.${N}"
else
  echo -e "${B}Dry-run only.${N} Use --apply to modify the wrappers."
fi
bar
exit $FAILED

