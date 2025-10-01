#!/bin/bash
#===============================================================
#Script Name: support/test-wrappers.sh
#Date: 09/28/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.2
#Short: Smoke-test wrapper envs & paths (✓/✖ summary)
#About: Runs bin/salt-ssh-el7|salt-ssh-el8|salt-call-el8 with --print-env, validates ONEDIR/THIN_TGZ,
#About: key executables, and prints a compact summary table. EL7-safe bash. Supports --root/--dry-run.
#===============================================================
set -e -o pipefail

WRAPPERS_DEFAULT="salt-ssh-el7 salt-ssh-el8 salt-call-el8"
ICON_OK="✓"; ICON_ERR="✖"; ICON_WARN="⚠"
if [ -t 1 ]; then
  COK='\033[1;32m'; CERR='\033[1;31m'; CWARN='\033[1;33m'; CHEAD='\033[0;36m'; CRESET='\033[0m'
else
  COK=""; CERR=""; CWARN=""; CHEAD=""; CRESET=""
fi
bar(){ printf "%b%s%b\n" "$CHEAD" "══════════════════════════════════════════════════════════════════════" "$CRESET"; }

RESOLVE_ABS(){
  local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || echo "$p"
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" )
  fi
}
SCRIPT_PATH="$(RESOLVE_ABS "$0")"
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"
DETECT_ROOT(){
  local d="$SCRIPT_DIR" i=6
  while [ "$i" -gt 0 ]; do
    if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then
      echo "$d"; return 0
    fi
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  echo "$(pwd)"
}
PROJECT_ROOT="${SALT_SHAKER_ROOT:-$(DETECT_ROOT)}"
ROOT_OVERRIDE=""
DRY_RUN=0
WRAPPERS="$WRAPPERS_DEFAULT"

usage(){ echo "Usage: $(basename "$0") [--root DIR] [--wrappers \"w1 w2 ...\"] [--dry-run] [-h]"; }

# CLI
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --root) ROOT_OVERRIDE="${2:-}"; shift 2;;
    --wrappers) WRAPPERS="${2:-}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo -e "$CERR$ICON_ERR Unknown option: $1$CRESET" >&2; usage; exit 2;;
  esac
done
[ -n "$ROOT_OVERRIDE" ] && PROJECT_ROOT="$(RESOLVE_ABS "$ROOT_OVERRIDE")"

BIN_DIR="$PROJECT_ROOT/bin"
LOG_DIR="$PROJECT_ROOT/logs"; mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
MAIN_LOG="$LOG_DIR/salt-shaker.log"
_ts(){ date +"%Y-%m-%d %H:%M:%S"; }
log(){ printf "[%s] [TEST-WRAPPERS] %s\n" "$(_ts)" "$*" >> "$MAIN_LOG" 2>/dev/null || true; }

bar
echo -e "$CHEAD▶ Wrapper smoke test$CRESET"
echo "Project Root: $PROJECT_ROOT"
echo "Bin Dir     : $BIN_DIR"
bar

[ -d "$BIN_DIR" ] || { echo -e "$CERR$ICON_ERR bin/ not found at $BIN_DIR$CRESET"; exit 2; }

SUMMARY=""
HARD_FAIL=0

test_wrapper(){
  local wname="$1" path="$BIN_DIR/$wname"
  local ok=1 onedir="" thin="" conf="" ver="" tool="" need_thin=0 note="-"
  [ "$wname" = "salt-ssh-el7" ] && need_thin=1

  if [ ! -x "$path" ]; then
    echo -e "$CWARN$ICON_WARN $wname: missing (skipping)$CRESET"
    SUMMARY="${SUMMARY}\n$(printf '%-14s | MISSING   | -    | -    | -' "$wname")"
    return 0
  fi

  if [ $DRY_RUN -eq 1 ]; then
    echo -e "$COK$ICON_OK [DRY] $wname --print-env$CRESET"
    SUMMARY="${SUMMARY}\n$(printf '%-14s | DRY-RUN   | -    | -    | no exec' "$wname")"
    return 0
  fi

  # Capture env
  local out ec
  out="$("$path" --print-env 2>&1 || true)"; ec=$?
  log "--- $wname --print-env output begin ---"
  log "$out"
  log "--- $wname --print-env output end ---"

  # If wrapper failed OR did not emit ONEDIR=, treat as FAIL-ENV (likely older wrapper or wrong script)
  if [ $ec -ne 0 ] || ! printf '%s\n' "$out" | grep -q '^ONEDIR='; then
    echo -e "$CERR$ICON_ERR $wname: --print-env failed or missing fields$CRESET"
    SUMMARY="${SUMMARY}\n$(printf '%-14s | FAIL-ENV  | -    | -    | %s' "$wname" "no ONEDIR")"
    HARD_FAIL=1
    return 0
  fi

  # Parse fields
  onedir="$(printf '%s\n' "$out" | awk -F= '/^ONEDIR=/{print $2; exit}')"
  thin="$(printf '%s\n' "$out" | awk -F= '/^THIN_TGZ=/{print $2; exit}')"
  conf="$(printf '%s\n' "$out" | awk -F= '/^CONF_DIR=/{print $2; exit}')"
  tool="$(printf '%s\n' "$out" | awk -F= '/^salt-(ssh|call)=/{print $2; exit}')"
  ver="$(printf '%s\n' "$out" | awk '/^salt-(ssh|call) /{print; exit}')"
  [ -n "$ver" ] || ver="-"

  # Checks
  if [ -z "$onedir" ] || [ ! -d "$onedir" ]; then
    echo -e "$CERR$ICON_ERR $wname: ONEDIR invalid: '${onedir:-}'$CRESET"; ok=0
  elif [ ! -x "$onedir/bin/python3.10" ]; then
    echo -e "$CERR$ICON_ERR $wname: python3.10 missing in ONEDIR$CRESET"; ok=0
  fi
  if [ $need_thin -eq 1 ]; then
    if [ -z "$thin" ] || [ ! -r "$thin" ]; then
      echo -e "$CERR$ICON_ERR $wname: THIN_TGZ missing (run module 05)$CRESET"; ok=0
    fi
  fi
  if [ -z "$tool" ] || [ ! -x "$tool" ]; then
    echo -e "$CERR$ICON_ERR $wname: tool not executable: '${tool:-}'$CRESET"; ok=0
  fi

  # Result
  if [ $ok -eq 1 ]; then
    echo -e "$COK$ICON_OK $wname: OK ($ver)$CRESET"
    note="$ver"
    local vend="-"; [ -n "$onedir" ] && vend="$(basename "$(dirname "$onedir")")"
    local thincol="-"; [ $need_thin -eq 1 ] && thincol="thin"
    SUMMARY="${SUMMARY}\n$(printf '%-14s | OK        | %4s | %4s | %s' "$wname" "$vend" "$thincol" "$note")"
  else
    echo -e "$CERR$ICON_ERR $wname: FAILED$CRESET"
    local vend="-"; [ -n "$onedir" ] && vend="$(basename "$(dirname "$onedir")")"
    local thincol="-"; [ $need_thin -eq 1 ] && thincol="thin"
    SUMMARY="${SUMMARY}\n$(printf '%-14s | FAIL      | %4s | %4s | %s' "$wname" "$vend" "$thincol" "see logs")"
    HARD_FAIL=1
  fi
}

for w in $WRAPPERS; do
  test_wrapper "$w"
done

bar
printf "%s\n" "Wrapper           | Status    | Vend | Thin | Note"
printf "%s\n" "----------------- | --------- | ---- | ---- | --------------------------------------"
printf "%b%s%b\n" "" "$(echo -e "$SUMMARY" | sed '/^$/d')" ""
bar

if [ $HARD_FAIL -eq 0 ]; then
  echo -e "$COK$ICON_OK All wrappers passed smoke tests.$CRESET"
  exit 0
else
  echo -e "$CERR$ICON_ERR One or more wrappers failed. See $MAIN_LOG.$CRESET"
  exit 1
fi

