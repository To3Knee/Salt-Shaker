#!/usr/bin/env bash
#===============================================================
#Script Name: build-rpm.sh
#Date: 09/04/2025
#Created By: To3Knee
#Version: 0.1.1
#About: Build a noarch RPM for Salt Shaker (if rpmbuild present).
#===============================================================
set -euo pipefail
LOG_DIR="$(pwd)"; [[ "$LOG_DIR" =~ ^(/home/|/srv/tmp/) ]] || LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/salt-shaker-build-rpm.log"
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }

print_about(){ sed -n '1,8p' "$0"; }
print_help(){ echo "Usage: $(basename "$0") [-a|-h] [VERSION] [RELEASE] [INSTALL_PREFIX]"; echo "Defaults: VERSION=0.2.2 RELEASE=1 INSTALL_PREFIX=/opt/salt-shaker"; }

while getopts ":ah" o; do case "$o" in
  a) print_about; exit 0;;
  h) print_help; exit 0;;
esac; done; shift $((OPTIND-1))

VER="${1:-0.2.2}"; REL="${2:-1}"; PREFIX="${3:-/opt/salt-shaker}"

if ! command -v rpmbuild >/dev/null 2>&1; then
  log "rpmbuild not found. Cannot build RPM on this system."
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$LOG_DIR/rpmbuild"
mkdir -p "$WORK"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
TARBALL="$WORK/SOURCES/salt-shaker-$VER.tar.gz"

log "Packaging tree into source tarball..."
tar -czf "$TARBALL" -C "$(dirname "$ROOT")" "$(basename "$ROOT")"

SPEC_SRC="$ROOT/SPECS/salt-shaker.spec"
SPEC_TMP="$WORK/SPECS/salt-shaker.spec"

sed -e "s|@@VERSION@@|$VER|g" \
    -e "s|@@RELEASE@@|$REL|g" \
    -e "s|@@PREFIX@@|$PREFIX|g" \
    "$SPEC_SRC" > "$SPEC_TMP"

log "Building RPM..."
rpmbuild --define "_topdir $WORK" -ba "$SPEC_TMP"
log "Done. See $WORK/RPMS/ for the RPM."
