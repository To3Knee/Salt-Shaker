# scripts/cleanup-artifacts.sh
#!/bin/bash
#===============================================================
#Script Name: cleanup-artifacts.sh
#Date: 2025-09-26
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0.1
#Short: Remove stray ANSI/quoted extract artifact directories
#About: Safely detects and removes top-level project directories whose names
#       contain control/ANSI characters, literal $'\033' quoting, \033/\x1b,
#       or contain “Extract onedir/Extracted onedir”. Dry-run by default.
#===============================================================
set -o pipefail

# Colors
if [ -t 1 ]; then RED=$'\033[91m'; GRN=$'\033[92m'; YLW=$'\033[93m'; BLU=$'\033[94m'; WHT=$'\033[97m'; NON=$'\033[0m'; else RED= GRN= YLW= BLU= WHT= NON=; fi

PROJECT_ROOT="${SALT_SHAKER_ROOT:-}"
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DRY_RUN=1
ASSUME_YES=0
VERBOSE=0

usage() {
  cat <<EOF
Usage: scripts/cleanup-artifacts.sh [options]

Options:
  --project-root PATH   Project root (default: ${PROJECT_ROOT})
  --dry-run             Only list what would be removed (default)
  --force, -y           Delete detected artifact directories
  --yes                 Don't prompt for confirmation when forcing
  --verbose             Print extra details
  -h, --help            Show this help
EOF
}

log()  { echo -e "${WHT}$*${NON}"; }
info() { echo -e "${GRN}$*${NON}"; }
warn() { echo -e "${YLW}$*${NON}"; }
err()  { echo -e "${RED}$*${NON}" 1>&2; }

# Args
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root) shift; PROJECT_ROOT="${1:-}";;
    --dry-run) DRY_RUN=1;;
    --force|-y) DRY_RUN=0;;
    --yes) ASSUME_YES=1;;
    --verbose) VERBOSE=1;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown option: $1"; usage; exit 2;;
  esac
  shift
done

[ -d "$PROJECT_ROOT" ] || { err "Project root not found: $PROJECT_ROOT"; exit 1; }
cd "$PROJECT_ROOT" || { err "Cannot cd to $PROJECT_ROOT"; exit 1; }

# Detect if name is artifact
is_artifact() {
  # $1 raw name (may include newlines)
  local name="$1"
  # 1) any non-printable (includes newline, ESC)
  # Use LC_ALL=C to make 'print' class ASCII-printable only.
  local ctrl
  ctrl="$(printf '%s' "$name" | LC_ALL=C tr -d '[:print:]')"
  if [ -n "$ctrl" ]; then
    [ $VERBOSE -eq 1 ] && log "non-printables in: $(printf '%q' "$name")"
    return 0
  fi
  # 2) semantic markers
  case "$name" in
    *Extract\ onedir*|*Extracted\ onedir*) return 0;;
  esac
  # 3) literal escape-notation patterns produced by bad echo/printf
  case "$name" in
    \$\'*|*\\033*|*\\x1b*|*'^[['*|*$'\033'* ) return 0;;
  esac
  return 1
}

# Collect dirs (null-delimited to survive newlines)
BAD=()
while IFS= read -r -d '' path; do
  base="${path#./}"
  if is_artifact "$base"; then
    BAD+=("$base")
  fi
done < <(find . -maxdepth 1 -mindepth 1 -type d -print0)

if [ ${#BAD[@]} -eq 0 ]; then
  info "No artifact directories detected in: $PROJECT_ROOT"
  exit 0
fi

log "Artifact directories detected:"
for d in "${BAD[@]}"; do
  printf '  - %q\n' "$d"
done

if [ $DRY_RUN -eq 1 ]; then
  warn "Dry-run mode; nothing deleted. Re-run with --force (or -y) to remove."
  exit 0
fi

# Confirm unless --yes
if [ $ASSUME_YES -ne 1 ]; then
  echo
  read -r -p "$(echo -e "${BLU}Remove ${#BAD[@]} directories listed above? [y/N]: ${NON}")" ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) warn "Aborted by user."; exit 3;; esac
fi

# Delete (null-safe, one by one)
RC=0
for d in "${BAD[@]}"; do
  if rm -rf -- "$d"; then
    info "Removed: $(printf '%q' "$d")"
  else
    err "Failed to remove: $(printf '%q' "$d")"
    RC=1
  fi
done

exit $RC

