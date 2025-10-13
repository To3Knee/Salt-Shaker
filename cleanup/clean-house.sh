#!/usr/bin/env bash
# cleanup/clean-house.sh
# One interactive cleaner for Standard / Full / Factory Reset
# RHEL/CentOS 7.9 compatible (bash 4.2), no symlinks, no external deps.

set -o pipefail

### ─────────── UI (colors) ───────────
if [ -t 1 ]; then
  tput_colors=$(tput colors 2>/dev/null || echo 0)
else
  tput_colors=0
fi
if [ "$tput_colors" -ge 8 ]; then
  BOLD="$(tput bold)"; DIM="$(tput dim)"; RESET="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"; CYAN="$(tput setaf 6)"
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""
fi

### ─────────── Paths & guards ───────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$ROOT" || { echo "cannot cd to project root"; exit 1; }

PRESERVE_ITEMS=(
  "salt-shaker.sh" "salt-shaker-el7.sh"
  "offline" "env" "info" "modules" "tools" "cleanup" "rpm" "archive" "support"
)

PURGE_TOPS=( "vendor" "logs" "deployables" "tmp" ".cache" "roster" "runtime" )

SNAP_DIR="${ROOT}/archive/snapshots"
mkdir -p "$SNAP_DIR" 2>/dev/null

# Backspace echo noise off (best effort) and restore on exit
stty -echoctl 2>/dev/null
cleanup_stty() { stty echoctl 2>/dev/null; }
trap cleanup_stty EXIT

### ─────────── Helpers ───────────
ts() { date +"%Y%m%d-%H%M%S"; }

say()   { printf "%b\n" "$*"; }
info()  { say "${CYAN}•${RESET} $*"; }
ok()    { say "${GREEN}✓${RESET} $*"; }
warn()  { say "${YELLOW}!${RESET} $*"; }
err()   { say "${RED}✗${RESET} $*"; }

exists_dir() { [ -d "$1" ]; }

# never delete these paths
is_preserved() {
  local rel="$1" base="${1%%/*}"
  for p in "${PRESERVE_ITEMS[@]}"; do
    [ "$rel" = "$p" ] && return 0
    [ "$base" = "$p" ] && return 0
  done
  return 1
}

# remove contents under a directory but keep the directory itself
purge_dir_contents() {
  local dir="$1" dry="$2"
  [ -z "$dir" ] && return 0
  mkdir -p "$dir" 2>/dev/null
  if [ "$dry" = "1" ]; then
    info "DRY purge → ${dir}/"
    return 0
  fi
  # robust rm of everything inside dir, while keeping dir
  # handles hidden files/dirs as well
  if [ -d "$dir" ]; then
    # shellcheck disable=SC2035
    rm -rf "${dir}/"* "${dir}"/.[!.]* "${dir}"/..?* 2>/dev/null || true
  fi
}

# rotate logs into a timestamped folder (keeps top-level logs/)
rotate_logs() {
  local dry="$1" src="logs" stamp logdst
  [ ! -d "$src" ] && return 0
  stamp="$(ts)"
  logdst="${SNAP_DIR}/logs.${stamp}"
  if [ "$dry" = "1" ]; then
    info "DRY rotate logs → ${logdst}/"
    return 0
  fi
  mkdir -p "$logdst"
  # move *contents* of logs into snapshot folder
  find "$src" -mindepth 1 -maxdepth 1 -exec mv {} "$logdst"/ \; 2>/dev/null || true
  ok "logs rotated → ${logdst}/"
}

# snapshot project (without huge/off-limits bits)
do_snapshot() {
  local level="$1" dry="$2"
  local stamp tarball
  stamp="$(echo "$level"-"$(ts)")"
  tarball="${SNAP_DIR}/${stamp}.tar.gz"
  info "Creating snapshot → ${tarball}"
  if [ "$dry" = "1" ]; then
    info "DRY tar czf ${tarball} . (with excludes)"
    ok "Snapshot created"
    return 0
  fi
  # Exclude common heavy/volatile areas & the snapshot itself
  tar --exclude="./archive/snapshots/*.tar.gz" \
      --exclude="./tmp/*" \
      --exclude="./.cache/*" \
      --exclude="./logs/*" \
      --exclude="./vendor/thin/*" \
      --exclude="./deployables/*" \
      -czf "$tarball" .
  ok "Snapshot created"
}

# secrets scrub for FULL/FACTORY (common patterns)
scrub_secrets() {
  local dry="$1"
  warn "Scrubbing secrets (keys/certs/SSH)…"
  local -a patterns=(
    "*.pem" "*.key" "*.pfx" "*.p12" "*.crt" "*.cer" "*.csr" "*.der"
    "id_rsa*" "id_dsa*" "id_ed25519*" "known_hosts"
    "*.kube/config" ".env" ".env.*" "*.vault" "*.pass" "*.secret*"
  )
  local find_cmd=(find . -type f)
  # exclude preserved areas where we never delete the directory itself,
  # but still allow secret files in them to be scrubbed EXCEPT offline/ and archive/
  # to avoid wrecking your offline cache and snapshots.
  find_cmd+=( -path "./offline/*" -prune -o -path "./archive/*" -prune -o )
  local first=1
  for pat in "${patterns[@]}"; do
    if [ $first -eq 1 ]; then first=0; else find_cmd+=( -o ); fi
    find_cmd+=( -name "$pat" )
  done
  # execute
  if [ "$dry" = "1" ]; then
    "${find_cmd[@]}" -print 2>/dev/null | sed 's/^/DRY rm /' || true
    ok "Secrets scrub simulated"
  else
    "${find_cmd[@]}" -print -delete 2>/dev/null || true
    ok "Secrets scrub complete"
  fi
}

# tiny prompt helpers (safe for bash 4.2)
ask() { # $1 prompt, sets REPLY
  printf "%b" "$1"
  read -r REPLY
}

pause_enter() { ask "${DIM}(press Enter to continue)${RESET} "; }

print_banner() {
  say "${MAGENTA}══════════════════════════════════════════════════════════════════════${RESET}"
  say "▶ ${BOLD}Clean House${RESET} ${DIM}· ${1}${RESET}"
  say "Project Root: ${CYAN}${ROOT}${RESET}"
  say "${MAGENTA}══════════════════════════════════════════════════════════════════════${RESET}"
}

print_levels_help() {
  say "This tool purges contents (not the directories themselves) of:"
  say "  ${BOLD}vendor/ logs/ deployables/ tmp/ .cache/ roster/ runtime/${RESET}"
  say
  say "${BOLD}Standard${RESET}:"
  say "  - Rotate logs/, clear tmp/ .cache/, purge vendor/thin, remove roster/runtime CSVs"
  say "  - Remove stray *.bak in bin/env/modules/runtime"
  say
  say "${BOLD}Full${RESET}:"
  say "  - Everything in Standard, plus purge vendor/el{7,8,9}/salt"
  say "  - Scrub common secrets (keys/certs/SSH) across tree (excludes offline/ & archive/)"
  say
  say "${BOLD}Factory Reset${RESET}:"
  say "  - Everything in Full, plus clear deployables/, roster/ (data), runtime/ (all data)"
  say "  - Leaves source & required scaffolding so the menu can rebuild"
  say
  say "${DIM}Never removed:${RESET} salt-shaker.sh  salt-shaker-el7.sh  offline/ env/ info/ modules/ tools/ cleanup/ rpm/ archive/ support/"
}

### ─────────── Arg parsing (only --dry-run supported) ───────────
DRY=0
case "$1" in
  --dry-run) DRY=1 ;;
  ""|*) : ;;
esac

### ─────────── Interactive flow ───────────
print_banner "Interactive"

print_levels_help
say

# Pick level
say "${BOLD}Choose level:${RESET}  [1] Standard   [2] Full   [3] Factory Reset"
ask "> "
case "$REPLY" in
  1) LEVEL="Standard" ;;
  2) LEVEL="Full" ;;
  3) LEVEL="Factory" ;;
  *) err "Invalid choice."; exit 1 ;;
esac

# DRY-RUN prompt if not forced by flag
if [ "$DRY" -eq 0 ]; then
  ask "Run as DRY-RUN first? [Y/n]: "
  case "$REPLY" in
    [Nn]*) DRY=0 ;;
    *) DRY=1 ;;
  esac
fi

# Snapshot prompt
ask "Create snapshot in ${SNAP_DIR}/ before changes? [Y/n]: "
case "$REPLY" in
  [Nn]*) MAKE_SNAPSHOT=0 ;;
  *) MAKE_SNAPSHOT=1 ;;
esac

say
warn "Type ${BOLD}${RED}PURGE${RESET} to proceed with ${BOLD}${LEVEL}${RESET}. Anything else cancels."
ask "> "
[ "$REPLY" = "PURGE" ] || { err "Aborted."; exit 1; }

say
print_banner "$LEVEL"
[ "$DRY" -eq 1 ] && warn "DRY-RUN (no changes will be made)."

# Safety check: ensure preserved items exist or are created as dirs
for p in "${PRESERVE_ITEMS[@]}"; do
  case "$p" in
    *.sh) : ;; # files
    *) mkdir -p "${ROOT}/${p}" 2>/dev/null ;;
  esac
done

# Snapshot
if [ "$MAKE_SNAPSHOT" -eq 1 ]; then
  do_snapshot "$(echo "$LEVEL" | tr '[:upper:]' '[:lower:]')" "$DRY"
fi

# Rotate logs for all levels
rotate_logs "$DRY"

# Common to Standard/Full/Factory:
# - tmp, .cache
purge_dir_contents "${ROOT}/tmp" "$DRY"
purge_dir_contents "${ROOT}/.cache" "$DRY"

# - vendor/thin always
purge_dir_contents "${ROOT}/vendor/thin" "$DRY"

# - roster/runtime CSVs (names we know you generate)
csvs=(
  "${ROOT}/roster/data/hosts_all_pods.csv"
  "${ROOT}/roster/data/hosts_all_pods.csv.bak"
  "${ROOT}/runtime/roster/data/hosts-all-pods.csv"
  "${ROOT}/runtime/roster/data/hosts-all-pods-example.csv"
)
for f in "${csvs[@]}"; do
  if [ "$DRY" -eq 1 ]; then
    [ -e "$f" ] && info "DRY rm $f"
  else
    [ -e "$f" ] && rm -f "$f" 2>/dev/null || true
  fi
done

# - *.bak in common spots
for d in "${ROOT}/bin" "${ROOT}/env" "${ROOT}/modules" "${ROOT}/runtime/bin"; do
  [ -d "$d" ] || continue
  if [ "$DRY" -eq 1 ]; then
    find "$d" -maxdepth 1 -type f -name "*.bak" -print 2>/dev/null | sed 's/^/DRY rm /'
  else
    find "$d" -maxdepth 1 -type f -name "*.bak" -delete 2>/dev/null || true
  fi
done

if [ "$LEVEL" = "Full" ] || [ "$LEVEL" = "Factory" ]; then
  # Purge vendor/el{7,8,9}/salt contents (force re-extract later)
  for v in "${ROOT}/vendor/el7/salt" "${ROOT}/vendor/el8/salt" "${ROOT}/vendor/el9/salt"; do
    purge_dir_contents "$v" "$DRY"
    mkdir -p "$v" 2>/dev/null
  done
  # Secrets scrub
  scrub_secrets "$DRY"
fi

if [ "$LEVEL" = "Factory" ]; then
  # Clear deployables/, roster/ (all data), runtime/ (all data)
  purge_dir_contents "${ROOT}/deployables" "$DRY"
  purge_dir_contents "${ROOT}/roster" "$DRY"
  purge_dir_contents "${ROOT}/runtime" "$DRY"
  # Recreate essential skeletons
  for d in bin tmp vendor/thin deployables runtime roster; do
    [ "$DRY" -eq 1 ] && info "DRY mkdir -p ${ROOT}/${d}" || mkdir -p "${ROOT}/${d}"
  done
  # Ensure vendor salt dirs exist (empty)
  for v in vendor/el7/salt vendor/el8/salt vendor/el9/salt; do
    [ "$DRY" -eq 1 ] && info "DRY mkdir -p ${ROOT}/${v}" || mkdir -p "${ROOT}/${v}"
  done
fi

say
ok "${LEVEL} clean complete"
exit 0

