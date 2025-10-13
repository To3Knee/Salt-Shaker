#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIG: set Short/About per file (filename => SHORT|ABOUT) =====
declare -A SHORT ABOUT
SHORT["00-setup.sh"]="Project bootstrap"
ABOUT["00-setup.sh"]="Create initial directory structure, verify tools, prepare env."

SHORT["01-check-dirs.sh"]="Verify required directories"
ABOUT["01-check-dirs.sh"]="Checks and (optionally) creates all required directories with proper perms."

SHORT["02-create-csv.sh"]="Create/seed CSV"
ABOUT["02-create-csv.sh"]="Seeds/updates inventory CSV used to generate roster/configs."

SHORT["03-verify-packages.sh"]="Verify offline assets"
ABOUT["03-verify-packages.sh"]="Verifies presence/sha/size for offline tarballs and RPMs."

SHORT["04-extract-binaries.sh"]="Extract onedir vendors"
ABOUT["04-extract-binaries.sh"]="Extracts EL7/8/9 onedir trees, overlays RPMs, normalizes perms."

SHORT["05-build-thin-el7.sh"]="Build EL7 thin archive"
ABOUT["05-build-thin-el7.sh"]="Delegates to xx-rebuild-thin-el7-min.sh to (re)build vendor/thin/salt-thin.tgz."

SHORT["06-check-vendors.sh"]="Validate vendors & thin"
ABOUT["06-check-vendors.sh"]="Prints a clean status table; verifies wrappers, vendors, and thin contents."

SHORT["07-remote-test.sh"]="Smoke remote wrapper"
ABOUT["07-remote-test.sh"]="Runs a minimal salt-ssh ping using project wrappers."

SHORT["08-generate-configs.sh"]="Write runtime configs"
ABOUT["08-generate-configs.sh"]="Generates runtime/conf and related files from CSV."

SHORT["09-generate-roster.sh"]="Create roster YAML"
ABOUT["09-generate-roster.sh"]="Builds runtime/roster/roster.yaml from CSV."

SHORT["10-create-project-rpm.sh"]="Package project RPM"
ABOUT["10-create-project-rpm.sh"]="Stages project and builds the project RPM/spec."

# ===== END CONFIG =====

AUTHOR="T03KNEE"
GITHUB="https://github.com/To3Knee/Salt-Shaker"
VERSION="1.0"
TODAY="$(date +%m/%d/%Y)"

emit_header() {
  local file="$1"
  local short="${SHORT[$file]:-Utility script}"
  local about="${ABOUT[$file]:-Utility script in the Salt-Shaker toolchain.}"
  local name="$file"
  cat <<EOF
#===============================================================
# Script Name: ${name}
# Date: ${TODAY}
# Created By: ${AUTHOR}
# Github: ${GITHUB}
# Version: ${VERSION}
# Short: ${short}
# About: ${about}
#===============================================================
EOF
}

refresh_one() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Skip (not found): $path"; return; }
  local base="$(basename "$path")"

  # Read shebang if present
  local shebang=""
  if head -1 "$path" | grep -q '^#!'; then
    shebang="$(head -1 "$path")"
  fi

  # Strip existing top comment banner if it starts with a line of '=' or '# Script Name'
  local tmp="$(mktemp)"
  if [[ -n "$shebang" ]]; then
    tail -n +2 "$path" > "$tmp"
  else
    cp "$path" "$tmp"
  fi

  # Remove existing header block (best-effort)
  awk '
    BEGIN{skip=0; started=0}
    NR==1 && ($0 ~ /^#=+$/ || $0 ~ /^# *Script Name:/){skip=1; started=1; next}
    skip==1 {
      if ($0 ~ /^#=+$/) {skip=2; next}
      next
    }
    {print}
  ' "$tmp" > "$tmp.body" || cp "$tmp" "$tmp.body"

  {
    [[ -n "$shebang" ]] && echo "$shebang"
    emit_header "$base"
    cat "$tmp.body"
  } > "$path.new"

  mv "$path.new" "$path"
  chmod +x "$path"
  rm -f "$tmp" "$tmp.body"
  echo "✓ Header refreshed: $path"
}

main() {
  local target_dir="${1:-modules}"
  shopt -s nullglob
  for f in "$target_dir"/*.sh; do
    refresh_one "$f"
  done
}
main "$@"
