#!/bin/bash
#===============================================================
#Script Name: diag-thin.sh
#Date: 10/02/2025
#Created By: Salt-Shaker
#Version: 1.0
#Short: Diagnose EL7 thin archive contents (and optional rebuild)
#About: Prints SALT_THIN_ARCHIVE path from salt-ssh-el7, shows sample listing,
#About: and can force a rebuild via Module 05.
#===============================================================
set -euo pipefail
OK="✓"; WARN="⚠"; ERR="✖"
ok(){   printf "%s %s\n" "$OK"  "$*"; }
warn(){ printf "%s %s\n" "$WARN" "$*" >&2; }
err(){  printf "%s %s\n" "$ERR" "$*" >&2; }

resolve_abs(){ p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || echo "$p"; else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" ); fi; }
detect_root(){
  d="$(pwd)"; i=6
  while [ "$i" -gt 0 ]; do
    [ -d "$d/modules" ] && { echo "$d"; return; }
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  pwd
}
ROOT="${SALT_SHAKER_ROOT:-$(detect_root)}"
BIN="$ROOT/bin"
WR="$BIN/salt-ssh-el7"

REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

[ -x "$WR" ] || { err "Wrapper not found: $WR"; exit 2; }

dump="$("$WR" --print-env 2>/dev/null || true)"
arch="$(printf "%s" "$dump" | awk -F= '/^SALT_THIN_ARCHIVE=/{print $2; exit}')"
if [ -z "${arch:-}" ]; then err "SALT_THIN_ARCHIVE not set by wrapper"; exit 2; fi
ok "SALT_THIN_ARCHIVE: $arch"
if [ ! -s "$arch" ]; then err "Archive missing: $arch"; [ $REBUILD -eq 1 ] || exit 2; fi

if tar -tzf "$arch" 2>/dev/null | sed 's#^\./##' | grep -E -q '^(salt(/|$)|salt/__init__\.py)'; then
  ok "Archive contains salt/"
else
  err "Archive does not contain salt/ — showing first 60 entries:"
  tar -tzf "$arch" 2>/dev/null | sed 's#^\./##' | head -60 || true
fi

if [ $REBUILD -eq 1 ]; then
  echo
  ok "Rebuilding thin via Module 05 --force…"
  "$ROOT/modules/05-build-thin-el7.sh" --force
  echo
  ok "Re-checking archive…"
  if tar -tzf "$arch" 2>/dev/null | sed 's#^\./##' | grep -E -q '^(salt(/|$)|salt/__init__\.py)'; then
    ok "Archive contains salt/ after rebuild"
  else
    err "Still missing salt/ after rebuild"
    exit 3
  fi
fi
