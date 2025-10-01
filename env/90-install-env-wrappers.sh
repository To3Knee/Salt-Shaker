#!/bin/bash
#===============================================================
#Script Name: 90-install-env-wrappers.sh
#Date: 09/28/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.2
#Short: Install/Uninstall env wrapper scripts into bin/ (no deletions in env/)
#About: Copies wrapper executables from env/ into bin/ (salt-ssh-el7, salt-ssh-el8, salt-call-el8, etc.),
#About: sets permissions, validates syntax, and keeps backups. Can uninstall from bin/ and clean .bak in bin/.
#About: Never removes files from env/ (golden sources for redeployment). EL7-safe; supports --dry-run, --root, --self-test.
#===============================================================
set -euo pipefail

#---------------------------
# Config (editable)
#---------------------------
WRAPPERS_DEFAULT="salt-ssh-el7 salt-ssh-el8 salt-call-el8"
DIR_MODE=700
FILE_MODE=755

#---------------------------
# UI
#---------------------------
ICON_OK="✓"; ICON_WARN="⚠"; ICON_ERR="✖"
if [ -t 1 ]; then
  COK='\033[1;32m'; CWARN='\033[1;33m'; CERR='\033[1;31m'; CHEAD='\033[0;36m'; CRESET='\033[0m'
else
  COK=""; CWARN=""; CERR=""; CHEAD=""; CRESET=""
fi
_ts(){ date +"%Y-%m-%d %H:%M:%S"; }
ok(){   printf "%b%s %s%b\n" "$COK"   "$ICON_OK"  "$*" "$CRESET"; }
warn(){ printf "%b%s %s%b\n" "$CWARN" "$ICON_WARN" "$*" "$CRESET" >&2; }
err(){  printf "%b%s %s%b\n" "$CERR"  "$ICON_ERR" "$*" "$CRESET" >&2; }

#---------------------------
# Root detection
#---------------------------
RESOLVE_ABS(){
  local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || echo "$p"
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" )
  fi
}
SCRIPT_PATH="$(RESOLVE_ABS "$0")"
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"     # expected: .../env
DETECT_ROOT(){
  local d="$SCRIPT_DIR" i=6
  while [ "$i" -gt 0 ]; do
    if [ -d "$d/modules" ] || [ -d "$d/vendor" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then
      echo "$d"; return 0
    fi
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  echo "$(pwd)"
}
PROJECT_ROOT="${SALT_SHAKER_ROOT:-$(DETECT_ROOT)}"
ENV_DIR="$PROJECT_ROOT/env"
BIN_DIR="$PROJECT_ROOT/bin"
LOG_DIR="$PROJECT_ROOT/logs"
MAIN_LOG="$LOG_DIR/salt-shaker.log"
mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
log(){ printf "[%s] [WRAP-INSTALL] %s\n" "$(_ts)" "$*" >> "$MAIN_LOG" 2>/dev/null || true; }

#---------------------------
# CLI
#---------------------------
DRY_RUN=0
FORCE=0
ROOT_OVERRIDE=""
WRAPPERS="$WRAPPERS_DEFAULT"
MODE="install"         # install|uninstall
CLEAN_BACKUPS=0        # delete *.bak in bin/
SELF_TEST=0            # run support/test-wrappers.sh after actions

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]

Install or uninstall wrapper scripts between env/ and bin/:
  Default wrappers: $WRAPPERS_DEFAULT

Modes:
  (default) install      Copy env/<name> -> bin/<name> (backup existing as .bak)
  --uninstall            Remove bin/<name> (optionally remove its .bak with --clean-backups)

Options:
  -n, --dry-run          Show actions only
  -f, --force            Overwrite without prompt (install mode)
  -r, --root DIR         Override project root
  -w, --wrappers LIST    Space-separated names (default: "$WRAPPERS_DEFAULT")
  --clean-backups        Delete *.bak in bin/ (never touches env/)
  --self-test            Run support/test-wrappers.sh after actions
  -h, --help             Show this help

Examples:
  ./env/90-install-env-wrappers.sh
  ./env/90-install-env-wrappers.sh --uninstall --clean-backups
  ./env/90-install-env-wrappers.sh -w "salt-ssh-el7 salt-ssh-el8" --self-test
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift;;
    -f|--force)   FORCE=1; shift;;
    -r|--root)    ROOT_OVERRIDE="${2:-}"; shift 2;;
    -w|--wrappers) WRAPPERS="${2:-}"; shift 2;;
    --uninstall)  MODE="uninstall"; shift;;
    --clean-backups) CLEAN_BACKUPS=1; shift;;
    --self-test)  SELF_TEST=1; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 2;;
  esac
done

if [ -n "$ROOT_OVERRIDE" ]; then
  PROJECT_ROOT="$(RESOLVE_ABS "$ROOT_OVERRIDE")"
  ENV_DIR="$PROJECT_ROOT/env"
  BIN_DIR="$PROJECT_ROOT/bin"
  LOG_DIR="$PROJECT_ROOT/logs"
  MAIN_LOG="$LOG_DIR/salt-shaker.log"
  mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
fi

#---------------------------
# Helpers
#---------------------------
ensure_bin_dir(){
  if [ $DRY_RUN -eq 0 ]; then
    mkdir -p "$BIN_DIR"
    chmod "$DIR_MODE" "$BIN_DIR" || true
  fi
}

install_one(){
  local name="$1" SRC="$ENV_DIR/$name" DST="$BIN_DIR/$name"
  if [ ! -f "$SRC" ]; then
    warn "$name: not found in env/ (skipping)"
    return 0
  fi
  local TMP="$PROJECT_ROOT/tmp/.instwrap.$name.$$.tmp"
  mkdir -p "$PROJECT_ROOT/tmp" >/dev/null 2>&1 || true
  if head -n1 "$SRC" | grep -q '^#!'; then
    sed 's/\r$//' "$SRC" > "$TMP"
  else
    { echo "#!/bin/bash"; sed 's/\r$//' "$SRC"; } > "$TMP"
  fi
  if ! bash -n "$TMP" 2>/dev/null; then
    rm -f "$TMP"; err "$name: syntax check failed"; return 1
  fi
  if [ -f "$DST" ] && [ $DRY_RUN -eq 0 ]; then
    cp -pf "$DST" "$DST.bak" || true
    ok "$name: existing backed up to $(basename "$DST").bak"
  fi
  if [ $DRY_RUN -eq 1 ]; then
    ok "[DRY] install $name → $BIN_DIR (mode $FILE_MODE)"
    rm -f "$TMP"
  else
    install -m "$FILE_MODE" "$TMP" "$DST"
    rm -f "$TMP"
    ok "Installed $name → $DST"
  fi
  return 0
}

uninstall_one(){
  local name="$1" DST="$BIN_DIR/$name" BAK="$BIN_DIR/$name.bak"
  if [ ! -e "$DST" ] && [ ! -e "$BAK" ]; then
    warn "$name: nothing to remove in bin/"; return 0
  fi
  if [ -e "$DST" ]; then
    if [ $DRY_RUN -eq 1 ]; then ok "[DRY] remove $DST"; else rm -f "$DST"; ok "Removed $DST"; fi
  fi
  if [ $CLEAN_BACKUPS -eq 1 ] && [ -e "$BAK" ]; then
    if [ $DRY_RUN -eq 1 ]; then ok "[DRY] remove $BAK"; else rm -f "$BAK"; ok "Removed $BAK"; fi
  fi
  return 0
}

self_test(){
  local t="$PROJECT_ROOT/support/test-wrappers.sh"
  if [ ! -x "$t" ]; then
    warn "support/test-wrappers.sh not found or not executable; skipping self-test"
    return 0
  fi
  if [ $DRY_RUN -eq 1 ]; then
    ok "[DRY] would run: $t"
    return 0
  fi
  echo
  ok "Running wrapper smoke test..."
  if "$t"; then
    ok "Wrapper smoke test passed"
  else
    err "Wrapper smoke test reported failures (see $MAIN_LOG)"
    return 1
  fi
}

#---------------------------
# Execute
#---------------------------
printf "%b%s%b\n" "$CHEAD" "════════════════ ENV WRAPPERS (${MODE^^}) ════════════════" "$CRESET"
ok "Project Root: $PROJECT_ROOT"
ok "Source (env): $ENV_DIR"
ok "Target (bin): $BIN_DIR"

FAILED=0

case "$MODE" in
  install)
    ensure_bin_dir
    for name in $WRAPPERS; do
      install_one "$name" || FAILED=1
    done
    ;;
  uninstall)
    for name in $WRAPPERS; do
      uninstall_one "$name" || FAILED=1
    done
    ;;
  *) err "Unknown mode: $MODE"; exit 2;;
esac

# Optional self-test
if [ $SELF_TEST -eq 1 ]; then
  self_test || FAILED=1
fi

printf "%b%s%b\n" "$CHEAD" "════════════════ ENV WRAPPERS COMPLETE ════════════════" "$CRESET"
if [ $FAILED -eq 0 ]; then
  ok "Wrappers processed."
  exit 0
else
  err "One or more operations failed."
  exit 1
fi

