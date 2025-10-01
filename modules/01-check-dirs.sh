#!/bin/bash
#===============================================================
#Script Name: 01-check-dirs.sh
#Date: 09/30/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.3
#Short: Verify project directory skeleton
#About: Verifies the Salt-Shaker directory structure laid down by setup.sh.
#       Default: read-only verification (no changes). Optional --fix will
#       create missing required *core* directories; --fix-perms will chmod +x
#       on common scripts if present. Vendor subtrees are DEFERRED by default
#       (created by modules 04/05). Use --strict to enforce vendor subtrees now.
#       EL7/EL8/EL9 compatible; logs to logs/salt-shaker*.log.
#===============================================================

set -euo pipefail

#------------------------------- Config -------------------------------#
DEFAULT_DIR_MODE="755"
DEFAULT_EXE_MODE="755"
#---------------------------------------------------------------------#

# Colors (TTY only)
if [ -t 1 ]; then
  C_G="\033[0;32m"; C_Y="\033[1;33m"; C_R="\033[0;31m"; C_B="\033[0;34m"; C_W="\033[1;37m"; C_N="\033[0m"
else
  C_G=""; C_Y=""; C_R=""; C_B=""; C_W=""; C_N=""
fi

# EL7-safe absolute path resolver
RESOLVE_ABS() {
  local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || echo "$p"
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" )
  fi
}

SCRIPT_PATH="$(RESOLVE_ABS "$0")"
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"

# Project root: SALT_SHAKER_ROOT > script's parent
if [ -n "${SALT_SHAKER_ROOT:-}" ]; then
  PROJECT_ROOT="$(RESOLVE_ABS "$SALT_SHAKER_ROOT")"
else
  case "$SCRIPT_DIR" in
    */modules) PROJECT_ROOT="$(RESOLVE_ABS "$SCRIPT_DIR/..")" ;;
    *)         PROJECT_ROOT="$(RESOLVE_ABS "$SCRIPT_DIR/..")" ;;
  esac
fi

# Ensure logs dir exists early
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
MAIN_LOG="$LOG_DIR/salt-shaker.log"
ERROR_LOG="$LOG_DIR/salt-shaker-errors.log"

log()  { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"  >>"$MAIN_LOG" 2>/dev/null || true; }
err()  { echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >>"$ERROR_LOG" 2>/dev/null || true; echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >>"$MAIN_LOG" 2>/dev/null || true; }
warn() { echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*"  >>"$MAIN_LOG" 2>/dev/null || true; }
bar()  { printf "%b%s%b\n" "$C_B" "══════════════════════════════════════════════════════════════════════════" "$C_N"; }

show_about() {
  sed -n '/^#About:/,/^#===============================================================/p' "$0" \
    | sed '1d;$d' | sed 's/^#About: //; s/^# //'
}

show_help() {
cat <<EOF
${C_W}Usage:${C_N} ${0##*/} [OPTIONS]

Verifies the Salt-Shaker directory skeleton created by setup.sh.
Default is read-only. Use --fix/--fix-perms to apply changes.
Use --dry-run to simulate fixes without modifying disk.

Vendor subtrees are treated as ${C_Y}DEFERRED${C_N} (created by modules 04/05).
Use ${C_W}--strict${C_N} to enforce vendor subtrees now.

${C_W}Options:${C_N}
  -h, --help         Show help
  -a, --about        Show description
  --root PATH        Explicit project root (override auto-detect)
  --fix              Create missing required *core* directories (mode ${DEFAULT_DIR_MODE})
  --fix-perms        chmod ${DEFAULT_EXE_MODE} on common scripts (if present)
  --dry-run          Simulate --fix/--fix-perms (no changes), mark actions with [DRY]
  --strict           Treat vendor subtrees as required (fail if missing)

${C_W}Logs:${C_N}
  $MAIN_LOG
  $ERROR_LOG
EOF
}

FIX="no"
FIX_PERMS="no"
DRY_RUN="no"
STRICT="no"

# Args
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  show_help; exit 0 ;;
    -a|--about) show_about; exit 0 ;;
    --root) shift; PROJECT_ROOT="$(RESOLVE_ABS "${1:-$PROJECT_ROOT}")" ;;
    --fix) FIX="yes" ;;
    --fix-perms) FIX_PERMS="yes" ;;
    --dry-run) DRY_RUN="yes" ;;
    --strict) STRICT="yes" ;;
    *) echo -e "${C_R}Unknown option: $1${C_N}" >&2; show_help >&2; exit 1 ;;
  esac
  shift
done

# Lists (as plain strings to stay EL7-safe)
REQUIRED_DIRS_CORE='
archive
bin
env
file-roots
info
logs
modules
offline
offline/deps
offline/salt
offline/salt/el7
offline/salt/el8
offline/salt/el9
offline/salt/tarballs
offline/salt/thin
pillar
roster
rpm
scripts
support
tmp
tools
vendor
'

DEFERRED_DIRS_VENDOR='
vendor/el7
vendor/el7/salt
vendor/el7/thin
vendor/el8
vendor/el8/salt
vendor/el9
vendor/el9/salt
'

OPTIONAL_DIRS='
.cache
'

KNOWN_EXEC='
salt-shaker.sh
salt-shaker-el7.sh
clean-house.sh
'

create_dir() {
  # create only when explicitly requested; simulate with --dry-run
  local rel="$1"
  local abs="$PROJECT_ROOT/$rel"
  if [ "$FIX" != "yes" ]; then return 0; fi
  if [ -d "$abs" ]; then return 0; fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo -e "✓ [DRY] create: $rel"
    log "[DRY] create: $rel"
    return 0
  fi
  if mkdir -p "$abs" 2>/dev/null; then
    chmod "$DEFAULT_DIR_MODE" "$abs" 2>/dev/null || true
    echo -e "✓ created: $rel"
    log "created: $rel"
    return 0
  else
    echo -e "✖ ${C_R}$rel${C_N} (mkdir failed)"
    err "mkdir failed: $rel"
    return 1
  fi
}

maybe_fix_exec() {
  local p="$1"
  if [ "$FIX_PERMS" != "yes" ]; then return 0; fi
  if [ ! -f "$p" ] || [ -x "$p" ]; then return 0; fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo -e "✓ [DRY] +x: $(basename "$p")"
    log "[DRY] chmod +x $(basename "$p")"
    return 0
  fi
  chmod "$DEFAULT_EXE_MODE" "$p" 2>/dev/null || true
  echo -e "✓ FIXED (+x): $(basename "$p")"
  log "chmod +x $(basename "$p")"
}

# Start
bar
echo -e "${C_W}▶ Verify Project Skeleton${C_N}"
echo "Project Root: $PROJECT_ROOT"
[ "$DRY_RUN" = "yes" ] && echo -e "${C_Y}[DRY-RUN] No changes will be made.${C_N}"
[ "$STRICT"  = "yes" ] && echo -e "${C_Y}[STRICT] Vendor subtrees required now.${C_N}"
bar

core_present=0; core_missing=0; core_fixed=0
defer_present=0; defer_missing=0; defer_fixed=0
opt_present=0; opt_missing=0
perm_fixed=0; failed=0

echo -e "${C_W}Required directories:${C_N}\n"
echo "Path                                   | Status"
echo "-------------------------------------- | ------"
echo "$REQUIRED_DIRS_CORE" | while IFS= read -r d; do
  [ -z "$d" ] && continue
  if [ -d "$PROJECT_ROOT/$d" ]; then
    printf "%-38s | %bOK%b\n" "$d" "$C_G" "$C_N"
    core_present=$((core_present+1))
  else
    printf "%-38s | %bMISSING%b\n" "$d" "$C_R" "$C_N"
    if create_dir "$d"; then
      [ "$FIX" = "yes" ] && core_fixed=$((core_fixed+1))
    else
      failed=$((failed+1))
    fi
    core_missing=$((core_missing+1))
  fi
done
echo

echo -e "${C_W}Vendor subtrees (created later by modules 04/05):${C_N}\n"
echo "Path                                   | Status"
echo "-------------------------------------- | ------"
echo "$DEFERRED_DIRS_VENDOR" | while IFS= read -r d; do
  [ -z "$d" ] && continue
  if [ -d "$PROJECT_ROOT/$d" ]; then
    printf "%-38s | %bOK%b\n" "$d" "$C_G" "$C_N"
    defer_present=$((defer_present+1))
  else
    if [ "$STRICT" = "yes" ]; then
      printf "%-38s | %bMISSING (strict)%b\n" "$d" "$C_R" "$C_N"
      if create_dir "$d"; then
        [ "$FIX" = "yes" ] && defer_fixed=$((defer_fixed+1))
      else
        failed=$((failed+1))
      fi
      defer_missing=$((defer_missing+1))
    else
      printf "%-38s | %bDEFERRED (by 04/05)%b\n" "$d" "$C_Y" "$C_N"
    fi
  fi
done
echo

echo -e "${C_W}Optional directories:${C_N}\n"
echo "Path                                   | Status"
echo "-------------------------------------- | ------"
echo "$OPTIONAL_DIRS" | while IFS= read -r d; do
  [ -z "$d" ] && continue
  if [ -d "$PROJECT_ROOT/$d" ]; then
    printf "%-38s | %bOK%b\n" "$d" "$C_G" "$C_N"
    opt_present=$((opt_present+1))
  else
    printf "%-38s | %bOK (missing, optional)%b\n" "$d" "$C_Y" "$C_N"
    opt_missing=$((opt_missing+1))
  fi
done
echo

echo -e "${C_W}Executable scripts (if present):${C_N}\n"
echo "File                                   | Status"
echo "-------------------------------------- | ------"
echo "$KNOWN_EXEC" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  local_p="$PROJECT_ROOT/$f"
  if [ -f "$local_p" ]; then
    if [ -x "$local_p" ]; then
      printf "%-38s | %bOK%b\n" "$f" "$C_G" "$C_N"
    else
      if [ "$FIX_PERMS" = "yes" ]; then
        maybe_fix_exec "$local_p" && perm_fixed=$((perm_fixed+1)) || true
      else
        printf "%-38s | %bNOT EXEC (+x recommended)%b\n" "$f" "$C_Y" "$C_N"
        warn "script not executable: $f"
      fi
    fi
  else
    printf "%-38s | %bN/A (not present)%b\n" "$f" "$C_Y" "$C_N"
  fi
done
echo

bar
echo -e "${C_W}Summary${C_N}"
bar
printf "Core present     : %d\n" "$core_present"
printf "Core missing     : %d\n" "$core_missing"
[ "$FIX" = "yes" ] && printf "Core created     : %d%s\n" "$core_fixed" "$( [ "$DRY_RUN" = "yes" ] && echo " [DRY]" || echo "" )"
printf "Vendor present   : %d\n" "$defer_present"
[ "$STRICT" = "yes" ] && printf "Vendor missing   : %d\n" "$defer_missing"
[ "$FIX" = "yes" ] && [ "$STRICT" = "yes" ] && printf "Vendor created   : %d%s\n" "$defer_fixed" "$( [ "$DRY_RUN" = "yes" ] && echo " [DRY]" || echo "" )"
printf "Optional present : %d\n" "$opt_present"
printf "Optional missing : %d\n" "$opt_missing"
echo

# Exit policy:
# - Fail only if core missing (or vendor missing under --strict), or mkdir failed.
if [ "$failed" -ne 0 ]; then
  echo -e "${C_R}✖ Errors occurred (see logs).${C_N}"
  err "01-check-dirs encountered errors"
  exit 2
fi

if [ "$core_missing" -eq 0 ] && { [ "$STRICT" = "no" ] || [ "$defer_missing" -eq 0 ]; }; then
  echo -e "${C_G}✓ Directory skeleton looks good.${C_N}"
  [ "$STRICT" = "no" ] && echo -e "${C_G}✓ Vendor subtrees are deferred to modules 04/05 (this is expected).${C_N}"
  log "01-check-dirs OK (strict=$STRICT)"
  exit 0
fi

if [ "$STRICT" = "no" ] && [ "$core_missing" -eq 0 ]; then
  echo -e "${C_G}✓ Core OK.${C_N} ${C_Y}Vendor subtrees will be created by 04/05.${C_N}"
  log "01-check-dirs OK (core-only)"
  exit 0
fi

echo -e "${C_R}✖ Missing required directories. Re-run with --fix or run setup.sh.${C_N}"
err "01-check-dirs found missing dirs"
exit 1

