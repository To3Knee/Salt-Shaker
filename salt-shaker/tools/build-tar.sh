#!/usr/bin/env bash
#===============================================================
#Script Name: build-tar.sh
#Date: 09/04/2025
#Created By: To3Knee
#Version: 0.1.1
#About: Create a portable tarball of the Salt Shaker project.
#===============================================================
set -euo pipefail
LOG_DIR="$(pwd)"; [[ "$LOG_DIR" =~ ^(/home/|/srv/tmp/) ]] || LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/salt-shaker-build-tar.log"
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }

print_about(){ sed -n '1,8p' "$0"; }
print_help(){ echo "Usage: $(basename "$0") [-a|-h] [OUTPUT]"; }

while getopts ":ah" o; do case "$o" in
  a) print_about; exit 0;;
  h) print_help; exit 0;;
esac; done; shift $((OPTIND-1))

OUT="${1:-salt-shaker-portable.tar.gz}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$(basename "$ROOT")"
cd "$(dirname "$ROOT")"
log "Creating tarball: $OUT from $BASE"
tar -czf "$OUT" "$BASE"
log "Wrote $(pwd)/$OUT"
