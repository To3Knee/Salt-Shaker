#!/usr/bin/env bash
#===============================================================
#Script Name: 01-check-dirs.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Validate project directories
#About: Ensures required directories exist and are writable.
#===============================================================
#!/bin/bash
# Script Name: 01-check-dirs.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Verify required directories
# About: Checks and (optionally) creates all required directories with proper perms.
#!/bin/bash

# NOTE: We intentionally do NOT use `set -u` here to avoid
# aborts on unset vars when run from various menus/wrappers.
set -e -o pipefail
LC_ALL=C

# ---------- UI ----------
if [ -t 1 ]; then
  G='\033[1;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'
else
  G=""; Y=""; R=""; C=""; N=""
fi
say(){ echo -e "$*"; }
ok(){ printf "%b✓ %s%b\n" "$G" "$*" "$N"; }
warn(){ printf "%b⚠ %s%b\n" "$Y" "$*" "$N" >&2; }
err(){ printf "%b✖ %s%b\n" "$R" "$*" "$N" >&2; }
bar(){ printf "%b%s%b\n" "$C" "══════════════════════════════════════════════════════════════════════════" "$N"; }

# ---------- Root detection ----------
RESOLVE_ABS(){ local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  fi
}
PRJ="$(RESOLVE_ABS "$(pwd)")"

print_table_header(){ printf "%-38s | %s\n" "Path" "Status"; printf "%-38s | %s\n" "--------------------------------------" "------"; }
status_dir(){ [ -d "$PRJ/$1" ] && echo "OK" || echo "MISSING"; }
legacy_note(){ [ -d "$PRJ/$1" ] && echo "LEGACY-PRESENT" || echo "-"; }

# ---------- Header ----------
bar; say "▶ Verify Project Skeleton"; say "Project Root: $PRJ"; bar

# ---------- Required (runtime-first) ----------
say "Required directories (runtime-first):"; echo
print_table_header

core_missing=0
req=(
  runtime
  runtime/bin
  runtime/conf
  runtime/file-roots
  runtime/pillar
  runtime/roster
  runtime/roster/data
  runtime/.cache
  runtime/logs
  runtime/etc
  runtime/etc/salt
  runtime/etc/salt/pki
  offline
  offline/salt
  offline/salt/tarballs
  offline/salt/thin
  vendor
  modules
  logs
  tmp
)
for p in "${req[@]}"; do
  s="$(status_dir "$p")"
  printf "%-38s | %s\n" "$p" "$s"
  [ "$s" = "MISSING" ] && core_missing=$((core_missing+1))
done
echo

# ---------- Vendor subtrees (populated by 04/05) ----------
say "Vendor subtrees (populated later by modules 04/05):"; echo
print_table_header
for p in vendor/el7 vendor/el7/salt vendor/el7/thin vendor/el8 vendor/el8/salt vendor/el9 vendor/el9/salt; do
  printf "%-38s | %s\n" "$p" "$(status_dir "$p")"
done
echo

# ---------- Optional / Legacy (informational only) ----------
say "Optional / Legacy (informational only):"; echo
print_table_header
for p in archive bin env file-roots pillar roster rpm scripts support; do
  printf "%-38s | %s\n" "$p" "$(legacy_note "$p")"
done
echo

# ---------- Master hint ----------
MASTER="$PRJ/runtime/conf/master"
[ -s "$MASTER" ] || warn "runtime/conf/master missing or empty. Run: ./modules/00-setup.sh --force-master"

# ---------- Executables presence (if present) ----------
say "Executable scripts (if present):"; echo
print_table_header
for f in salt-shaker.sh salt-shaker-el7.sh tools/clean-house.sh; do
  if [ -e "$PRJ/$f" ]; then
    if [ -x "$PRJ/$f" ]; then printf "%-38s | OK\n" "$f"; else printf "%-38s | NOT-EXEC\n" "$f"; fi
  fi
done
echo

# ---------- Summary ----------
bar; say "Summary"; bar
printf "Core missing     : %d\n" "$core_missing"; echo

if [ "$core_missing" -gt 0 ]; then
  err "Directory skeleton has missing core paths."
  say "Hint: run ./modules/00-setup.sh (idempotent) and re-check."
  exit 2
fi

ok "Directory skeleton looks good."
say "✓ Vendor subtrees are created later by modules 04/05 (expected)."
exit 0
