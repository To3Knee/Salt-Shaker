#!/usr/bin/env bash
#===============================================================
#Script Name: build-bundle.sh
#Date: 09/04/2025
#Created By: To3Knee
#Version: 0.1.0
#About: Fetch Salt SSH + dependencies (RPMs) on a connected EL host,
#       extract them WITHOUT installing, and assemble a portable bundle
#       under vendor/salt/ for the Salt Shaker project.
#       Supports EL7/EL8/EL9 with dnf or yumdownloader (yum-utils).
#===============================================================

# ===================== BEGIN: EDIT HERE (Safe Defaults) ======================
# Where is the Salt Shaker project?
# Default: the project root is one level above this script.
# change-me example:
#   PROJECT_DIR="/srv/tmp/salt-shaker"
PROJECT_DIR="${PROJECT_DIR:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"

# Bundle destination inside the project (no underscores in names)
BUNDLE_DIR_REL="vendor/salt"         # final bundle lives here
BIN_DIR_NAME="bin"                   # where salt-ssh will be placed
LIB_DIR_REL="lib"                    # library root under vendor/salt

# RPM download workspace (safe to clean afterwards)
# If you run under /home/* or /srv/tmp/*, this lives in your PWD by default.
RPM_CACHE_DIR="${RPM_CACHE_DIR:-"$PROJECT_DIR/.cache/rpms"}"

# What to download (minimal set for salt-ssh runtime)
# These names vary slightly by EL release; the resolver will pull the right deps.
BASE_PACKAGES=(
  salt-ssh
  salt
  salt-common
)

# Common Python deps frequently required by salt-ssh (resolver usually pulls these)
# Keep this list lean; resolver adds exact versions/variants.
EXTRA_PY_DEPS=(
  python3-jinja2
  python3-msgpack
  python3-yaml
  python3-requests
  python3-tornado
  python3-markupsafe
)

# Architecture and release hints (usually auto-detected; override if needed)
RELEASEVER="${RELEASEVER:-}"   # e.g. "8" or "9" (empty = let dnf/yum detect)
BASEARCH="${BASEARCH:-$(/bin/arch)}"

# Produce a portable tarball of vendor/salt at the end?
MAKE_TARBALL="${MAKE_TARBALL:-1}"   # 1=yes, 0=no
TARBALL_NAME="${TARBALL_NAME:-salt-vendor-bundle.tar.gz}"

# ====================== END: EDIT HERE (Safe Defaults) ======================

set -euo pipefail

# ---------- Paths & logging ----------
BUNDLE_DIR="$PROJECT_DIR/$BUNDLE_DIR_REL"
BIN_DIR="$BUNDLE_DIR/$BIN_DIR_NAME"
LIB_DIR="$BUNDLE_DIR/$LIB_DIR_REL"
STAGING_DIR="$PROJECT_DIR/.cache/staging"
MANIFEST="$BUNDLE_DIR/manifest.txt"

RUN_DIR="$(pwd)"
case "$RUN_DIR" in
  /home/*|/srv/tmp/*) LOG_DIR="$RUN_DIR" ;;
  *)                  LOG_DIR="$PROJECT_DIR/logs" ;;
esac
mkdir -p "$LOG_DIR" "$RPM_CACHE_DIR" "$STAGING_DIR" "$BIN_DIR" "$LIB_DIR"
LOG_FILE="$LOG_DIR/salt-shaker-build-bundle.log"

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" >&2; }
die(){ log "ERROR: $*"; exit 1; }

print_about(){ sed -n '1,10p' "$0"; }
print_help(){
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -a               Show About information and exit.
  -h               Show this help and exit.
  -r <releasever>  Force releasever (e.g., 7, 8, 9). Default: auto.
  -A <arch>        Force architecture (e.g., x86_64, aarch64). Default: $(/bin/arch)
  -n               Do NOT create tarball (default creates: $TARBALL_NAME)

Environment overrides (examples):
  PROJECT_DIR="/srv/tmp/salt-shaker" \\
  RPM_CACHE_DIR="/srv/tmp/rpms" \\
  MAKE_TARBALL=0 \\
  $(basename "$0")

What it does:
  1) Finds dnf or yumdownloader to fetch RPMs (with dependencies) for:
     ${BASE_PACKAGES[*]} + minimal Python deps
  2) Extracts RPM payloads into a staging area (no installs)
  3) Copies the needed runtime into: $BUNDLE_DIR_REL/
     - $BIN_DIR_NAME/salt-ssh (executable)
     - $LIB_DIR_REL/ (Python site-packages and friends)
  4) Writes a manifest file with versions and paths
  5) Optionally packs a tarball: $TARBALL_NAME

EOF
}

while getopts ":ahr:A:n" o; do
  case "$o" in
    a) print_about; exit 0 ;;
    h) print_help; exit 0 ;;
    r) RELEASEVER="$OPTARG" ;;
    A) BASEARCH="$OPTARG" ;;
    n) MAKE_TARBALL=0 ;;
    *) die "Unknown option: -$OPTARG (use -h)" ;;
  esac
done

# ---------- Pre-flight ----------
require_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
for c in bash rpm rpm2cpio cpio tar awk sed grep printf date tee; do require_cmd "$c"; done

# Choose downloader: prefer dnf
DOWNLOADER=""
if command -v dnf >/dev/null 2>&1; then
  DOWNLOADER="dnf"
elif command -v yumdownloader >/dev/null 2>&1; then
  DOWNLOADER="yumdownloader"
else
  die "Neither 'dnf' nor 'yumdownloader' found. Install one on the build host."
fi

log "Using downloader: $DOWNLOADER"
log "Project dir: $PROJECT_DIR"
log "Bundle dir : $BUNDLE_DIR"
log "RPM cache  : $RPM_CACHE_DIR"
log "Staging    : $STAGING_DIR"
log "Arch/Rel   : arch=$BASEARCH releasever=${RELEASEVER:-auto}"
log "Log file   : $LOG_FILE"

# ---------- Download RPMs with dependencies ----------
pushd "$RPM_CACHE_DIR" >/dev/null

download_with_dnf(){
  local relarg=()
  [[ -n "$RELEASEVER" ]] && relarg+=(--releasever="$RELEASEVER")
  # --resolve pulls deps; --alldeps for completeness; --arch ensures right arch/noarch
  log "dnf download --resolve ${relarg[*]} --arch $BASEARCH ${BASE_PACKAGES[*]} ${EXTRA_PY_DEPS[*]}"
  dnf -y download --resolve "${relarg[@]}" --arch "$BASEARCH" "${BASE_PACKAGES[@]}" "${EXTRA_PY_DEPS[@]}"
}

download_with_yumdownloader(){
  local relarg=()
  [[ -n "$RELEASEVER" ]] && relarg+=(--releasever="$RELEASEVER")
  # --resolve pulls deps; --archlist constrains arch
  log "yumdownloader --resolve ${relarg[*]} --archlist=$BASEARCH ${BASE_PACKAGES[*]} ${EXTRA_PY_DEPS[*]}"
  yumdownloader --resolve "${relarg[@]}" --archlist="$BASEARCH" "${BASE_PACKAGES[@]}" "${EXTRA_PY_DEPS[@]}"
}

case "$DOWNLOADER" in
  dnf) download_with_dnf ;;
  yumdownloader) download_with_yumdownloader ;;
esac

RPM_LIST=( *.rpm )
[[ ${#RPM_LIST[@]} -gt 0 ]] || die "No RPMs downloaded. Check repos/filters."

popd >/dev/null

# ---------- Extract RPM payloads (no installs) ----------
log "Extracting RPM payloads to staging..."
rm -rf "$STAGING_DIR" && mkdir -p "$STAGING_DIR"

for rpmf in "$RPM_CACHE_DIR"/*.rpm; do
  log "Extract: $(basename "$rpmf")"
  rpm2cpio "$rpmf" | (cd "$STAGING_DIR" && cpio -idmv >/dev/null 2>&1 || true)
done

# ---------- Identify components we need ----------
# salt-ssh executable usually under /usr/bin/salt-ssh
SALT_SSH_PATH=""
if [[ -x "$STAGING_DIR/usr/bin/salt-ssh" ]]; then
  SALT_SSH_PATH="$STAGING_DIR/usr/bin/salt-ssh"
elif [[ -x "$STAGING_DIR/bin/salt-ssh" ]]; then
  SALT_SSH_PATH="$STAGING_DIR/bin/salt-ssh"
fi
[[ -n "$SALT_SSH_PATH" ]] || die "salt-ssh not found in extracted payloads."

# Python site-packages roots vary by EL/Python version; gather likely paths
PY_SITES=()
while IFS= read -r -d '' d; do PY_SITES+=("$d"); done < <(find "$STAGING_DIR/usr/lib" -type d -path "*/python*/site-packages" -print0 2>/dev/null || true)
while IFS= read -r -d '' d; do PY_SITES+=("$d"); done < <(find "$STAGING_DIR/usr/lib64" -type d -path "*/python*/site-packages" -print0 2>/dev/null || true)

# Must include Salt modules and key deps
NEEDED_PKGS=(salt salt_thin jinja2 msgpack yaml requests tornado markupsafe)
FOUND_ANY=0
for sp in "${PY_SITES[@]}"; do
  if compgen -G "$sp/salt*" >/dev/null; then FOUND_ANY=1; break; fi
done
[[ "$FOUND_ANY" -eq 1 ]] || log "WARNING: Could not verify Salt site-packages. Proceeding; dnf/yum likely placed them in vendor."

# ---------- Lay down the vendor bundle ----------
log "Assembling vendor bundle under $BUNDLE_DIR_REL ..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BIN_DIR" "$LIB_DIR"

# Install salt-ssh binary
install -m 0755 "$SALT_SSH_PATH" "$BIN_DIR/salt-ssh"

# Copy python trees we found into vendor/lib/
for sp in "${PY_SITES[@]}"; do
  # Copy only the needed pieces to keep bundle lean; fallback to everything if unsure
  if [[ -d "$sp/salt" ]]; then
    mkdir -p "$LIB_DIR/$(basename "$(dirname "$sp")")/site-packages"
    cp -a "$sp/salt"* "$LIB_DIR/$(basename "$(dirname "$sp")")/site-packages/" 2>/dev/null || true
  fi
  for pkg in jinja2 msgpack yaml requests tornado markupsafe salt_thin; do
    if compgen -G "$sp/${pkg}*" >/dev/null; then
      mkdir -p "$LIB_DIR/$(basename "$(dirname "$sp_
