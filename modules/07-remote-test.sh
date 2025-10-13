#!/usr/bin/env bash
#===============================================================
#Script Name: 07-remote-test.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Remote test via salt-ssh
#About: Lightweight end-to-end test against roster targets using thin.
#===============================================================
#!/bin/bash
# Script Name: 07-remote-test.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Smoke remote wrapper
# About: Runs a minimal salt-ssh ping using project wrappers.
#!/bin/bash
set -euo pipefail
LC_ALL=C

# ---------- Colors (TTY + NO_COLOR aware) ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD="$(tput bold 2>/dev/null || true)"; RESET="$(tput sgr0 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"; RED="$(tput setaf 1 2>/dev/null || true)"
  CYAN="$(tput setaf 6 2>/dev/null || true)"
else
  BOLD=""; RESET=""; GREEN=""; RED=""; CYAN=""
fi

ROOT="${SALT_SHAKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
RUNTIME_DIR="${SALT_SHAKER_RUNTIME_DIR:-$ROOT/runtime}"
CONF_DIR="$RUNTIME_DIR/conf"
TMP_DIR="$ROOT/tmp"
LOG_DIR="$ROOT/logs"
mkdir -p "$TMP_DIR" "$LOG_DIR"

WRAPPER_OPT="auto"  # auto|el7|el8

usage(){ cat <<'HLP'
Usage: modules/07-remote-test.sh [--wrapper auto|el7|el8]
HLP
}
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --wrapper) WRAPPER_OPT="${2:-auto}"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

title(){ printf '──────────────────────────────────────────────────────────────\nSALT SHAKER | Module 07 · Remote Test\n──────────────────────────────────────────────────────────────\n'; }
fail(){ printf "${RED}✖ %s${RESET}\n" "$1"; exit 2; }
info(){ printf "${CYAN}• %s${RESET}\n" "$1"; }
ok(){ printf "${GREEN}✔ %s${RESET}\n" "$1"; }

# nounset-safe raw OS detector (no thin)
detect_target_os() {
  # prints: 7|8|9|unknown
  local host="${1:-}" user="${2:-root}" port="${3:-22}"
  [ -z "$host" ] && { echo "unknown"; return 0; }
  local tmp="$TMP_DIR/detect.${host//[^A-Za-z0-9._-]/_}.$$.yaml"
  {
    echo "$host:"; echo "  host: $host"; echo "  user: $user"; echo "  port: $port"
    echo "  sudo: false"; echo "  tty: false"
    echo "  ssh_options:"; echo "    - StrictHostKeyChecking=no"; echo "    - UserKnownHostsFile=/dev/null"
  } > "$tmp"
  local WR="$ROOT/bin/salt-ssh-el8" out rc
  if [ ! -x "$WR" ]; then rm -f "$tmp"; echo "unknown"; return 0; fi
  set +e
  out="$("$WR" --ignore-host-keys -c "$CONF_DIR" --roster-file "$tmp" -W -t "$host" --user "$user" --askpass -r 'cat /etc/redhat-release || cat /etc/os-release' 2>&1)"
  rc=$?
  set -e
  rm -f "$tmp"
  [ $rc -eq 0 ] || { echo "unknown"; return 0; }
  printf '%s\n' "$out" | grep -qE 'release 7|VERSION_ID="?7' && { echo "7"; return 0; }
  printf '%s\n' "$out" | grep -qE 'release 8|VERSION_ID="?8' && { echo "8"; return 0; }
  printf '%s\n' "$out" | grep -qE 'release 9|VERSION_ID="?9' && { echo "9"; return 0; }
  echo "unknown"
}

title
echo "Remote Test"
echo "  Project Root: $ROOT"

read -r -p "Load target from CSV? [y]: " load_csv; load_csv="${load_csv:-y}"
if [ "$load_csv" = "y" ] || [ "$load_csv" = "Y" ]; then
  ROSTER_FILE="$RUNTIME_DIR/roster/roster.yaml"
  [ -f "$ROSTER_FILE" ] || fail "No roster at $ROSTER_FILE. Run module 09."
  read -r -p "Target glob (default '*'): " TARGET; TARGET="${TARGET:-*}"
  USERN=""; PORT=""
  HOSTNAME="$TARGET"
else
  read -r -p "Target host/IP []: " HOST; [ -n "$HOST" ] || fail "No host provided"
  read -r -p "SSH username [root]: " USERN; USERN="${USERN:-root}"
  read -r -p "SSH port [22]: " PORT; PORT="${PORT:-22}"
  ROSTER_FILE="$TMP_DIR/remote-test.$(date +%Y%m%d-%H%M%S).$$.yaml"
  {
    echo "$HOST:"; echo "  host: $HOST"; echo "  user: $USERN"; echo "  port: $PORT"
    echo "  sudo: false"; echo "  tty: false"
    echo "  ssh_options:"; echo "    - StrictHostKeyChecking=no"; echo "    - UserKnownHostsFile=/dev/null"
  } > "$ROSTER_FILE"
  TARGET="$HOST"
  HOSTNAME="$HOST"
fi

# Auto/forced wrapper selection (nounset-safe)
OSMAJ="unknown"
PICKED="$WRAPPER_OPT"
if [ "$WRAPPER_OPT" = "auto" ]; then
  OSMAJ="$(detect_target_os "${HOSTNAME:-}" "${USERN:-root}" "${PORT:-22}")"
  case "$OSMAJ" in
    7) PICKED="el7";;
    8|9) PICKED="el8";;
    *) PICKED="el8";;
  esac
fi
case "$PICKED" in
  el7) WRAP="$ROOT/bin/salt-ssh-el7"; PYBIN="/usr/bin/python";;
  el8) WRAP="$ROOT/bin/salt-ssh-el8"; PYBIN="/usr/bin/python3";;
  *) fail "Invalid wrapper selection: $PICKED";;
esac
[ -x "$WRAP" ] || fail "Wrapper missing: $WRAP"

# Inject python_bin only for temp roster
if echo "$ROSTER_FILE" | grep -q "/tmp/"; then
  printf '  python_bin: %s\n' "$PYBIN" >> "$ROSTER_FILE"
fi

echo "  Wrapper: $(basename "$WRAP")"
echo "  Target: $TARGET"
echo "  Roster: $ROSTER_FILE"
echo "  Config: $CONF_DIR (thin_dir from master)"
echo "  OS/Wrapper: $OSMAJ/$PICKED"

set +e
"$WRAP" --ignore-host-keys -c "$CONF_DIR" --roster-file "$ROSTER_FILE" -W -t "$TARGET" --askpass test.ping; rc1=$?
"$WRAP" --ignore-host-keys -c "$CONF_DIR" --roster-file "$ROSTER_FILE" -W -t "$TARGET" --askpass grains.item osfinger pythonversion; rc2=$?
set -e

# cleanup temp roster
if echo "$ROSTER_FILE" | grep -q "/tmp/"; then rm -f "$ROSTER_FILE" || true; fi

if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]; then
  ok "Remote test PASSED"
  exit 0
fi
fail "Remote test FAILED (OS=$OSMAJ wrapper=$PICKED)"
