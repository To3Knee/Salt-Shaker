#!/usr/bin/env bash
# cleanup/cleanup.sh  —  interactive cleanup for Salt Shaker
# Compatible with RHEL 7.9 (bash 4.2). No symlinks, fully portable.

set -o errexit
set -o pipefail
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------- Colors (fallback if tput missing or no tty) ----------
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  bold="$(tput bold)"; dim="$(tput dim)"; ul="$(tput smul)"; noul="$(tput rmul)"
  red="$(tput setaf 1)"; green="$(tput setaf 2)"; yellow="$(tput setaf 3)"
  blue="$(tput setaf 4)"; magenta="$(tput setaf 5)"; cyan="$(tput setaf 6)"
  reset="$(tput sgr0)"
else
  bold=""; dim=""; ul=""; noul=""; red=""; green=""; yellow=""; blue=""; magenta=""; cyan=""; reset=""
fi

banner () {
  echo "${cyan}══════════════════════════════════════════════════════════════════════${reset}"
  echo "▶ ${bold}$1${reset}"
  echo "Project Root: ${dim}${PROJECT_ROOT}${reset}"
  echo "${cyan}══════════════════════════════════════════════════════════════════════${reset}"
}

note () { echo "• $*"; }
ok   () { echo "${green}✓${reset} $*"; }
warn () { echo "${yellow}!${reset} $*"; }
err  () { echo "${red}✗${reset} $*"; }

# ---------- Defaults / options ----------
PROFILE=""           # standard | full | factory
DRY_RUN="ask"        # ask | yes | no
SNAP_DIR_DEFAULT="${PROJECT_ROOT}/archive/snapshots"

# allow quick flags
for arg in "$@"; do
  case "$arg" in
    --standard) PROFILE="standard" ;;
    --full)     PROFILE="full"     ;;
    --factory)  PROFILE="factory"  ;;
    --dry-run)  DRY_RUN="yes"      ;;
    --live|--yes) DRY_RUN="no"     ;;
  esac
done

# ---------- Protected & content scopes ----------
# NEVER delete or pack these top-level paths
PROTECTED_TOPLEVEL=(
  "salt-shaker.sh"
  "salt-shaker-el7.sh"
  "offline"
  "env"
  "info"
  "modules"
  "tools"
  "cleanup"
  "rpm"
  "archive"
  "support"
)

# Areas where we may delete files (not dirs)
CONTENT_DIRS=( "vendor" "logs" "deployables" "tmp" ".cache" "roster" "runtime" )

# Clutter patterns (Standard & Full)
CLUTTER_PATTERNS=( "*.bak" "*.orig" "*.rej" "*.patch" "*~" ".*.swp" ".*.swo" ".DS_Store" "*.tmp" )

# Secret patterns (Full & Factory)
SECRET_PATTERNS=( "*.key" "*.pem" "*.p12" "*.pfx" "*.jks" "*.kdb" "*.rnd" "*.crt" "*.cer" "id_rsa" "id_dsa" "id_ecdsa" "known_hosts" ".env" "*.env" "*.kube/config" )

# ---------- Small helpers ----------
join_by() { local IFS="$1"; shift; echo "$*"; }

is_protected_path () {
  # $1 = path (relative to project root)
  local p="$1"
  for keep in "${PROTECTED_TOPLEVEL[@]}"; do
    [[ "$p" == "$keep" || "$p" == "$keep/"* ]] && return 0
  done
  return 1
}

ensure_dirs () {
  # minimal skeletons after cleanup
  local list=( "bin" "tmp" "vendor/thin" "deployables" "runtime" )
  if [[ "$1" == "full" || "$1" == "factory" ]]; then
    list+=( "vendor/el7/salt" "vendor/el8/salt" "vendor/el9/salt" )
  fi
  for d in "${list[@]}"; do
    [[ "$DRY_RUN" == "yes" ]] && note "DRY mkdir -p $d" || mkdir -p "$PROJECT_ROOT/$d"
  done
  ok "skeletons ready"
}

rotate_logs () {
  local ts="$(date +%Y%m%d%H%M%S)"
  local src="${PROJECT_ROOT}/logs"
  [[ -d "$src" ]] || { warn "logs/ not present"; return 0; }
  local dst="${PROJECT_ROOT}/archive/snapshots/logs.${ts}"
  [[ "$DRY_RUN" == "yes" ]] && note "DRY rotate logs -> ${dst}" || { mkdir -p "$dst"; mv "$src"/* "$dst"/ 2>/dev/null || true; }
  ok "logs rotated"
}

make_snapshot () {
  # $1 profile, $2 snapshot_dir
  local profile="$1"; local snapdir="$2"
  mkdir -p "$snapdir"
  local ts="$(date +%Y%m%d%H%M%S)"
  local tarball="${snapdir}/${profile}-${ts}.tar.gz"

  # build exclude args
  local ex=()
  for p in "${PROTECTED_TOPLEVEL[@]}"; do
    # we still snapshot everything except the snapshot file itself
    :
  done

  note "Creating snapshot → ${tarball}"
  if [[ "$DRY_RUN" == "yes" ]]; then
    note "DRY tar czf ${tarball} . (excluding the tarball itself)"
  else
    # Avoid “file changed as we read it”: write to a temporary file then mv
    local tmp="${tarball}.partial"
    # Exclude the snapshot file itself just in case:
    ( cd "$PROJECT_ROOT" && tar --exclude="$(basename "$tarball")" -czf "$tmp" . )
    mv "$tmp" "$tarball"
  fi
  ok "Snapshot created"
}

safe_rm_globs () {
  # $1 label, $2.. patterns (globs) — delete only inside CONTENT_DIRS and not inside protected roots
  local label="$1"; shift
  local total=0

  note "Remove ${label}"
  for base in "${CONTENT_DIRS[@]}"; do
    local bpath="${PROJECT_ROOT}/${base}"
    [[ -e "$bpath" ]] || continue
    for pat in "$@"; do
      # Use find so we can count & delete quietly
      if [[ "$DRY_RUN" == "yes" ]]; then
        local n
        n=$(find "$bpath" -type f -name "$pat" 2>/dev/null | wc -l || true)
        (( total += n ))
      else
        find "$bpath" -type f -name "$pat" -exec rm -f {} + 2>/dev/null || true
      fi
    done
  done
  [[ "$DRY_RUN" == "yes" ]] && ok "would remove ~${total} ${label}" || ok "removed ${label}"
}

safe_rm_paths () {
  # Remove whole dirs (like tmp, .cache, vendor/thin) safely within project root
  # args: list of relative paths from project root
  for rel in "$@"; do
    local p="${PROJECT_ROOT}/${rel}"
    [[ -e "$p" ]] || continue
    if [[ "$DRY_RUN" == "yes" ]]; then
      note "DRY rm -rf ${rel}"
    else
      rm -rf "$p"
    fi
    ok "removed ${rel}"
  done
}

wipe_vendor_salt_trees () {
  local trees=( "vendor/el7/salt" "vendor/el8/salt" "vendor/el9/salt" )
  for t in "${trees[@]}"; do
    local p="${PROJECT_ROOT}/${t}"
    [[ -e "$p" ]] || continue
    if [[ "$DRY_RUN" == "yes" ]]; then
      note "DRY rm -rf ${t}"
    else
      rm -rf "$p"
    fi
    ok "removed ${t}"
  done
}

scrub_secrets () {
  note "Scrubbing secrets in content areas"
  for base in "${CONTENT_DIRS[@]}"; do
    local bpath="${PROJECT_ROOT}/${base}"
    [[ -e "$bpath" ]] || continue
    for pat in "${SECRET_PATTERNS[@]}"; do
      if [[ "$DRY_RUN" == "yes" ]]; then
        local n; n=$(find "$bpath" -type f -name "$pat" 2>/dev/null | wc -l || true)
        [[ "$n" -gt 0 ]] && note "DRY would remove ~${n} × ${pat} under ${base}"
      else
        find "$bpath" -type f -name "$pat" -exec rm -f {} + 2>/dev/null || true
      fi
    done
  done
  ok "secret scrub complete"
}

headline () {
  local title="$1"
  banner "$title"
  echo "This will ${bold}modify files${reset} under: $(join_by ", " "${CONTENT_DIRS[@]}")"
  echo "Always preserved: ${green}$(join_by ", " "${PROTECTED_TOPLEVEL[@]}")${reset}"
  echo
}

# ---------- Interact ----------
headline "Cleanup"

if [[ -z "$PROFILE" ]]; then
  echo "Choose level:"
  echo "  [1] Standard  – mop & dust + clutter"
  echo "  [2] Full      – Standard + wipe vendor/el*/salt + scrub secrets"
  echo "  [3] Factory   – Aggressive reset (safe: preserves protected assets)"
  read -rp "Select 1/2/3: " ans
  case "${ans:-}" in
    1) PROFILE="standard" ;;
    2) PROFILE="full" ;;
    3) PROFILE="factory" ;;
    *) err "Invalid selection"; exit 1 ;;
  esac
fi

case "$DRY_RUN" in
  ask)
    read -rp "Enable DRY-RUN (recommended first)? [Y/n]: " d
    case "${d:-Y}" in
      [Nn]*) DRY_RUN="no" ;;
      *)     DRY_RUN="yes" ;;
    esac
  ;;
esac

echo
warn "Type ${bold}PURGE${reset} to proceed with the ${bold}${PROFILE^^}${reset} cleanup."
read -rp "Confirm: " confirm
[[ "${confirm}" == "PURGE" ]] || { err "Aborted."; exit 1; }

[[ "$DRY_RUN" == "yes" ]] && warn "DRY-RUN mode: ${bold}no changes${reset} will be made."

# ---------- Do it ----------
case "$PROFILE" in
  standard)
    banner "Clean House · Standard"
    rotate_logs
    safe_rm_paths "tmp" ".cache" "vendor/thin"
    # roster/runtime CSV artifacts
    safe_rm_globs "CSV artifacts" "hosts_all_pods.csv" "hosts_all_pods.csv*" "hosts-all-pods*.csv"
    # clutter across content areas
    safe_rm_globs "clutter" "${CLUTTER_PATTERNS[@]}"
    ensure_dirs "standard"
    ok "Standard clean complete"
  ;;
  full)
    banner "Clean House · Full"
    make_snapshot "full" "$SNAP_DIR_DEFAULT"
    rotate_logs
    safe_rm_paths "tmp" ".cache" "vendor/thin"
    safe_rm_globs "CSV artifacts" "hosts_all_pods.csv" "hosts_all_pods.csv*" "hosts-all-pods*.csv"
    safe_rm_globs "clutter" "${CLUTTER_PATTERNS[@]}"
    wipe_vendor_salt_trees
    scrub_secrets
    ensure_dirs "full"
    ok "Full clean complete"
  ;;
  factory)
    banner "Clean House · FACTORY RESET"
    make_snapshot "factory" "$SNAP_DIR_DEFAULT"
    rotate_logs
    safe_rm_paths "tmp" ".cache" "vendor/thin"
    safe_rm_globs "CSV artifacts" "hosts_all_pods.csv" "hosts_all_pods.csv*" "hosts-all-pods*.csv"
    safe_rm_globs "clutter" "${CLUTTER_PATTERNS[@]}"
    wipe_vendor_salt_trees
    scrub_secrets
    # extra factory steps:
    # clear deployables/ files (keep dir)
    note "Clearing deployables/ files (keeping directory)"
    if [[ "$DRY_RUN" == "yes" ]]; then
      note "DRY find deployables -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
    else
      find "${PROJECT_ROOT}/deployables" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    fi
    # clear runtime/logs if exists
    [[ -d "${PROJECT_ROOT}/runtime/logs" ]] && safe_rm_paths "runtime/logs"
    ensure_dirs "factory"
    ok "Factory reset complete"
  ;;
esac
