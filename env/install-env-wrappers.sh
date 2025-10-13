#!/bin/bash
#===============================================================
#Script Name: install-env-wrappers.sh (canonical)
#Date: 10/03/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 2.4
#Short: Install env/ executables to bin/ and runtime/bin/ (ignore-aware)
#About: Skips installer/backups and patterns in env/.wrapper-ignore or --exclude.
#       EL7-safe; includes project-root guard.
#===============================================================
set -euo pipefail
LC_ALL=C

SELF="${BASH_SOURCE[0]:-$0}"
ENV_DIR="$(cd "$(dirname "$SELF")" && pwd)"
ROOT="${SALT_SHAKER_ROOT:-$(cd "$ENV_DIR/.." && pwd)}"
BIN_DIR="$ROOT/bin"
RT_BIN_DIR="$ROOT/runtime/bin"
LOG="$ROOT/logs/salt-shaker.log"
IGNORE_FILE="$ENV_DIR/.wrapper-ignore"
EXTRA_EXCLUDES=""

usage(){ cat <<'HLP'
Usage: env/install-env-wrappers.sh [--exclude "glob1,glob2,..."]
HLP
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --exclude) EXTRA_EXCLUDES="${2:-}"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

# Guard
[ -d "$ROOT/env" ] || { echo "ERROR: bad ROOT ($ROOT). cd /sto/salt-shaker or set SALT_SHAKER_ROOT."; exit 2; }
mkdir -p "$BIN_DIR" "$RT_BIN_DIR" "$(dirname "$LOG")"

title(){ printf '\n════════════════ ENV WRAPPERS (INSTALL) ════════════════\n'; }
ok(){ printf "✓ %s\n" "$1"; }
skip(){ printf "• Skipping: %s\n" "$1"; }

# Build ignore patterns
IGNORES=( "install-env-wrappers.sh" "*.bak" "*.orig" )
if [ -f "$IGNORE_FILE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$line" ] || IGNORES+=( "$line" )
  done < "$IGNORE_FILE"
fi
if [ -n "$EXTRA_EXCLUDES" ]; then
  IFS=',' read -r -a extra <<< "$EXTRA_EXCLUDES"
  for g in "${extra[@]}"; do
    g="$(echo "$g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$g" ] || IGNORES+=( "$g" )
  done
fi

should_skip(){ # $1=basename
  local f="$1" pat
  for pat in "${IGNORES[@]}"; do case "$f" in $pat) return 0;; esac; done
  return 1
}

title
ok "Project Root: $ROOT"
ok "Source (env): $ENV_DIR"
ok "Target (bin): $BIN_DIR"
ok "Target (rt ): $RT_BIN_DIR"

WRAPPERS=()
while IFS= read -r -d '' f; do
  b="$(basename "$f")"
  if should_skip "$b"; then skip "$b"; continue; fi
  WRAPPERS+=( "$b" )
done < <(find "$ENV_DIR" -maxdepth 1 -type f -perm -111 -print0)

[ ${#WRAPPERS[@]} -gt 0 ] || { echo "No wrappers to install (all ignored?)"; exit 0; }

install_one(){ local src="$1" dst="$2" base; base="$(basename "$src")"
  [ -f "$dst" ] && cp -p "$dst" "$dst.bak" 2>/dev/null || true
  install -m 0755 "$src" "$dst"
  ok "Installed $base → $dst"
}

for b in "${WRAPPERS[@]}"; do
  src="$ENV_DIR/$b"
  install_one "$src" "$BIN_DIR/$b"
  install_one "$src" "$RT_BIN_DIR/$b"
done

printf '════════════════ ENV WRAPPERS COMPLETE ════════════════\n'
ok "Wrappers processed."
