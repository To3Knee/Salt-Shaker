#!/bin/bash
#===============================================================
#Script Name: test-thin-el7.sh
#Date: 09/28/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.1
#Short: Validate EL7 thin imports with Python 2.7
#About: Auto-detects PROJECT_ROOT from script path (or --root / SALT_SHAKER_ROOT), then
#About: unpacks vendor/el7/thin/salt-thin.tgz, sets PYTHONPATH, and imports salt,yaml,msgpack,tornado,six.
#===============================================================
set -euo pipefail

# Root detection
RESOLVE_ABS(){ if command -v readlink >/dev/null 2>&1; then readlink -f "$1" 2>/dev/null || (cd "$(dirname "$1")" && pwd)/"$(basename "$1")"; else (cd "$(dirname "$1")" && pwd)/"$(basename "$1")"; fi; }
SCRIPT_PATH="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
DETECT_ROOT(){ local d="$SCRIPT_DIR"; local max=6; while [ "$max" -gt 0 ]; do
  if [ -d "$d/modules" ] || [ -d "$d/vendor" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then echo "$d"; return 0; fi
  d="$(dirname "$d")"; max=$((max-1)); done; echo "$(pwd)"; }
PROJECT_ROOT_DEFAULT="$(DETECT_ROOT)"
PROJECT_ROOT="${SALT_SHAKER_ROOT:-$PROJECT_ROOT_DEFAULT}"

# Defaults derived from root; override via CLI
THIN_DEFAULT="$PROJECT_ROOT/vendor/el7/thin/salt-thin.tgz"
PYTHON_DEFAULT="/usr/bin/python2"
LOG1="$PROJECT_ROOT/tmp/srv.log"
LOG2="$PROJECT_ROOT/logs/salt-shaker.log"
mkdir -p "$PROJECT_ROOT/logs" "$PROJECT_ROOT/tmp" || true

ICON_OK="✓"; ICON_ERR="✖"
CLR_RESET='\033[0m'; CLR_OK='\033[1;32m'; CLR_ERR='\033[1;31m'
_ts(){ date +"%Y-%m-%d %H:%M:%S"; }
_log(){ local L="$1"; shift; local M="$*"; local line="[$(_ts)] [$L] $M"; printf "%s\n" "$line" >> "$LOG1"; printf "%s\n" "$line" >> "$LOG2"; }
ok(){ _log "OK" "$*"; printf "%b%s %s%b\n" "$CLR_OK" "$ICON_OK" "$*" "$CLR_RESET"; }
err(){ _log "ERROR" "$*"; printf "%b%s %s%b\n" "$CLR_ERR" "$ICON_ERR" "$*" "$CLR_RESET"; }

usage(){
  cat <<EOF
Usage: $(basename "$0") [--root <dir>] [--thin <path>] [--python <path>] [--keep] [--dry-run] [-h|-a]
  --root <dir>     Project root override (or set SALT_SHAKER_ROOT)
  --thin <path>    Path to salt-thin.tgz (default: <root>/vendor/el7/thin/salt-thin.tgz)
  --python <path>  Python 2.7 interpreter (default: $PYTHON_DEFAULT)
  --keep           Keep unpacked temp dir
  --dry-run        Validate archive & interpreter only; no import
  -h, --help       Help
  -a, --about      About
EOF
}
about(){ cat <<'EOF'
Validates an EL7 Python 2 thin by importing core modules under Python 2.7:
salt, yaml, msgpack, tornado, six. No network, no installs. Works from any working directory.
EOF
}

THIN="$THIN_DEFAULT"
PY="$PYTHON_DEFAULT"
KEEP=0
DRYRUN=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --root) PROJECT_ROOT="$(RESOLVE_ABS "${2:-}")"; THIN="$PROJECT_ROOT/vendor/el7/thin/salt-thin.tgz"; shift 2;;
    --thin) THIN="${2:-}"; shift 2;;
    --python) PY="${2:-}"; shift 2;;
    --keep) KEEP=1; shift;;
    --dry-run) DRYRUN=1; shift;;
    -h|--help) usage; exit 0;;
    -a|--about) about; exit 0;;
    *) err "Unknown option: $1"; usage; exit 2;;
  esac
done

cleanup(){ local ec=$?; [ "$KEEP" -eq 1 ] || { [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"; }; [ $ec -ne 0 ] && err "Thin validation aborted (exit $ec)"; }
trap cleanup EXIT

[ -r "$THIN" ] || { err "Thin not readable: $THIN"; exit 1; }
command -v "$PY" >/dev/null 2>&1 || { err "Python not found: $PY"; exit 1; }
"$PY" -V 2>&1 | grep -q "Python 2" || { err "Interpreter is not Python 2.x: $("$PY" -V 2>&1)"; exit 1; }

tar -tzf "$THIN" >/dev/null 2>&1 || { err "Thin archive appears corrupt: $(basename "$THIN")"; exit 1; }
ok "Thin archive OK: $(basename "$THIN")"

[ "$DRYRUN" -eq 1 ] && { ok "Dry-run complete (no import test)"; exit 0; }

TMPDIR="$(mktemp -d "$PROJECT_ROOT/tmp/thincheck.XXXXXX")"
tar -xzf "$THIN" -C "$TMPDIR"
ok "Unpacked to: $TMPDIR"
export PYTHONPATH="$TMPDIR${PYTHONPATH:+:$PYTHONPATH}"

PYCODE='
import sys
mods = ["salt","yaml","msgpack","tornado","six"]
rc=0
for m in mods:
    try:
        __import__(m)
        print("OK:"+m)
    except Exception as e:
        sys.stderr.write("ERR:%s:%s\n" % (m, e))
        rc=1
sys.exit(rc)
'
OUT="$("$PY" -c "$PYCODE" 2>&1 || true)"

ALL_OK=1
IFS=$'\n'
for line in $OUT; do
  case "$line" in
    OK:*) ok "Import ${line#OK:}";;
    ERR:*)
      mod="$(echo "$line" | cut -d: -f2)"
      msg="$(echo "$line" | cut -d: -f3-)"
      err "Import ${mod} failed: ${msg}"
      ALL_OK=0
      ;;
  esac
done

if [ "$ALL_OK" -eq 1 ]; then
  ok "All required imports succeeded (salt, yaml, msgpack, tornado, six)"
  exit 0
else
  err "Thin validation failed"
  exit 1
fi

