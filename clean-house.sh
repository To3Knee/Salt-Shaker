#!/bin/bash
#===============================================================
#Script Name: clean-house.sh
#Date: 09/29/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 2.1
#Short: Empty vendor,tmp,.cache,logs (keep dirs) or purge with --purge
#About: Default behavior removes CONTENTS ONLY of the four directories,
#About: preserving the directories themselves. Use --purge to remove dirs.
#About: EL7-safe; operates strictly inside the project root.
#===============================================================
set -euo pipefail

# --- Colors/UI ---
if [ -t 1 ]; then G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'; else G=""; Y=""; R=""; C=""; B=""; N=""; fi
OK="✓"; WRN="⚠"; ERR="✖"
bar(){ printf "%b%s%b\n" "$C" "══════════════════════════════════════════════════════════════════════" "$N"; }

# --- Root detect (EL7-safe) ---
RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" ); fi; }
FIND_ROOT_UP(){ local d="$1" i=8; while [ "$i" -gt 0 ] && [ -n "$d" ] && [ "$d" != "/" ]; do if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then echo "$d"; return 0; fi; d="$(dirname -- "$d")"; i=$((i-1)); done; return 1; }

SCRIPT_ABS="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_ABS")"
if [ -n "${SALT_SHAKER_ROOT:-}" ] && [ -d "${SALT_SHAKER_ROOT}" ]; then PROJECT_ROOT="$(RESOLVE_ABS "$SALT_SHAKER_ROOT")"
else PROJECT_ROOT="$(FIND_ROOT_UP "$SCRIPT_DIR" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(FIND_ROOT_UP "$(pwd)" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(RESOLVE_ABS "$(pwd)")"; fi

# --- Logging to project logs only ---
LOG_DIR="${PROJECT_ROOT}/logs"; mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
MAIN_LOG="${LOG_DIR}/salt-shaker.log"; ERR_LOG="${LOG_DIR}/salt-shaker-errors.log"
logi(){ printf "[%s] [INFO] %s\n"  "$(date +'%F %T')" "$1" | tee -a "$MAIN_LOG" >/dev/null 2>&1 || true; }
loge(){ printf "[%s] [ERROR] %s\n" "$(date +'%F %T')" "$1" | tee -a "$ERR_LOG" "$MAIN_LOG" >/dev/null 2>&1 || true; }

# --- CLI ---
DRY_RUN=0; ASSUME_YES=0; PURGE=0
show_help(){ cat <<EOF
Usage: ${0##*/} [--dry-run] [--yes] [--purge]
  --dry-run   Show what would be removed
  --yes       Do not prompt
  --purge     Remove the four directories themselves (dangerous)
Default: remove CONTENTS ONLY of:
  vendor/  tmp/  .cache/  logs/
Keeps the directories present.
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --yes) ASSUME_YES=1; shift;;
    --purge) PURGE=1; shift;;
    -h|--help) show_help; exit 0;;
    *) echo "Unknown option: $1" >&2; show_help >&2; exit 2;;
  esac
done

# --- Helpers ---
startswith(){ case "$2" in "$1"*) return 0;; *) return 1;; esac }
size_h(){ du -sh "$1" 2>/dev/null | awk '{print $1}'; }
confirm(){ [ $ASSUME_YES -eq 1 ] && return 0; printf "%bProceed with cleanup?%b [Y/n]: " "$B" "$N"; read -r a; a="${a:-Y}"; case "$a" in Y|y) return 0;; *) return 1;; esac; }

# Remove contents inside a dir (keep the dir)
empty_dir(){
  local d="$1"
  [ -d "$d" ] || { [ $DRY_RUN -eq 1 ] && echo -e "${Y}${WRN} [DRY] mkdir -p ${d}${N}"; mkdir -p "$d" >/dev/null 2>&1 || true; }
  startswith "$PROJECT_ROOT" "$d" || { echo -e "${R}${ERR} skip (outside project):${N} $d"; return 1; }
  if [ $DRY_RUN -eq 1 ]; then
    echo -e "${Y}${WRN} [DRY] find ${d} -mindepth 1 -maxdepth 1 -exec rm -rf {} +${N}"
    return 0
  fi
  # Remove everything under d (including hidden entries) but keep d itself
  find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
  echo -e "${G}${OK} emptied:${N} $d"
}

# Remove the directory itself (purge)
purge_dir(){
  local d="$1"
  [ -e "$d" ] || return 0
  startswith "$PROJECT_ROOT" "$d" || { echo -e "${R}${ERR} skip (outside project):${N} $d"; return 1; }
  if [ $DRY_RUN -eq 1 ]; then
    echo -e "${Y}${WRN} [DRY] rm -rf ${d}${N}"
    return 0
  fi
  rm -rf -- "$d" && echo -e "${G}${OK} removed:${N} $d" || { echo -e "${R}${ERR} failed:${N} $d"; return 1; }
}

# --- Targets ---
TARGETS=(
  "${PROJECT_ROOT}/vendor"
  "${PROJECT_ROOT}/tmp"
  "${PROJECT_ROOT}/.cache"
  "${PROJECT_ROOT}/logs"
)

# --- Report ---
bar
echo "▶ Clean House"
echo "Project Root: ${PROJECT_ROOT}"
bar
for p in "${TARGETS[@]}"; do
  if [ -e "$p" ]; then
    echo " - $(printf '%-24s' "${p#$PROJECT_ROOT/}")  [$(size_h "$p")]"
  else
    echo " - $(printf '%-24s' "${p#$PROJECT_ROOT/}")  [absent]"
  fi
done
bar
confirm || { echo "Aborted."; exit 1; }

# --- Execute ---
FAILED=0
for d in "${TARGETS[@]}"; do
  if [ $PURGE -eq 1 ]; then
    purge_dir "$d" || FAILED=1
  else
    empty_dir "$d" || FAILED=1
  fi
done

# Recreate dirs if they were purged or missing
for d in "${TARGETS[@]}"; do
  if [ ! -d "$d" ]; then
    if [ $DRY_RUN -eq 1 ]; then
      echo -e "${Y}${WRN} [DRY] mkdir -p ${d}${N}"
    else
      mkdir -p "$d" >/dev/null 2>&1 || FAILED=1
    fi
  fi
done

# Final
if [ $FAILED -eq 0 ]; then
  echo -e "${G}${OK} Cleanup complete.${N}"
  logi "Clean house complete. purge=${PURGE} dry=${DRY_RUN}"
else
  echo -e "${Y}${WRN} Cleanup finished with some errors (see logs).${N}"
  loge "Clean house had errors. purge=${PURGE} dry=${DRY_RUN}"
fi
exit $FAILED

