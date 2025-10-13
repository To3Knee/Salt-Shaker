#!/usr/bin/env bash
# Color helpers
b()  { tput bold; printf "%s" "$*"; tput sgr0; }
ok() { printf "\033[32m✓\033[0m %s\n" "$*"; }
warn(){ printf "\033[33m⚠\033[0m %s\n" "$*"; }
err(){ printf "\033[31m✗\033[0m %s\n" "$*"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODDIR="$ROOT/modules"

# Map Short/About per script (edit as you like)
short_about() {
  case "$1" in
    00-setup.sh)
      SHORT="Initialize project layout"
      ABOUT="Creates base dirs, sanity checks, and prepares workspace."
      ;;
    01-check-dirs.sh)
      SHORT="Validate project directories"
      ABOUT="Ensures required directories exist and are writable."
      ;;
    02-create-csv.sh)
      SHORT="Generate package CSV"
      ABOUT="Builds CSV inputs for offline processing and audits."
      ;;
    03-verify-packages.sh)
      SHORT="Verify offline packages"
      ABOUT="Validates presence/sha/versions of all offline artifacts."
      ;;
    04-extract-binaries.sh)
      SHORT="Extract controller binaries"
      ABOUT="Unpacks onedir controllers into vendor paths (EL7/8/9)."
      ;;
    05-build-thin-el7.sh)
      SHORT="Build salt-thin for EL7"
      ABOUT="Assembles salt-thin from offline RPMs/tarballs (with six fallback)."
      ;;
    05-rebuild-thin-el7-min.sh|xx-rebuild-thin-el7-min.sh)
      SHORT="Minimal EL7 thin builder"
      ABOUT="Robust extractor used by module 05; handles deps + six fallback."
      ;;
    06-check-vendors.sh)
      SHORT="Check vendors & thin"
      ABOUT="Runs health checks for onedir wrappers and thin archive contents."
      ;;
    07-remote-test.sh)
      SHORT="Remote test via salt-ssh"
      ABOUT="Lightweight end-to-end test against roster targets using thin."
      ;;
    08-generate-configs.sh)
      SHORT="Generate salt configs"
      ABOUT="Builds salt master/ssh configs tailored to this project layout."
      ;;
    09-generate-roster.sh)
      SHORT="Generate roster"
      ABOUT="Creates salt-ssh roster (YAML/CSV sources supported)."
      ;;
    10-create-project-rpm.sh)
      SHORT="Package project RPM"
      ABOUT="Bundles project artifacts into an installable RPM."
      ;;
    *)
      SHORT="Module utility"
      ABOUT="Detailed functionality not specified."
      ;;
  esac
  export SHORT ABOUT
}

stamp_header() {
  local f="$1"
  local base="$(basename "$f")"
  short_about "$base"

  local shebang line1 tmp="$(mktemp)"
  line1="$(head -n1 "$f" 2>/dev/null || true)"
  if [[ "$line1" =~ ^#!/ ]]; then
    shebang="$line1"; tail -n +2 "$f" > "${tmp}.body"
  else
    shebang='#!/usr/bin/env bash'; cp "$f" "${tmp}.body"
  fi

  # Strip an existing top banner between two lines of ===== if present (first 60 lines max)
  awk '
    NR==1,NR==60 {
      if ($0 ~ /^#=+$/) { if (flag==0) {flag=1; next} else {flag=2; next} }
      if (flag==1) next
    }
    { print }
  ' "${tmp}.body" > "${tmp}.clean"

  {
    printf "%s\n" "$shebang"
    cat <<HDR
#===============================================================
#Script Name: ${base}
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: ${SHORT}
#About: ${ABOUT}
#===============================================================
HDR
    cat "${tmp}.clean"
  } > "${tmp}.new"

  chmod --reference="$f" "${tmp}.new" 2>/dev/null || chmod +x "${tmp}.new"
  mv "${tmp}.new" "$f"
  rm -f "${tmp}.body" "${tmp}.clean"
  ok "Header refreshed → modules/${base}"
}

main() {
  cd "$MODDIR" || { err "Cannot cd to modules/"; exit 1; }

  # Target list (explicit to avoid touching temp/backups)
  files=(
    00-setup.sh
    01-check-dirs.sh
    02-create-csv.sh
    03-verify-packages.sh
    04-extract-binaries.sh
    05-build-thin-el7.sh
    06-check-vendors.sh
    07-remote-test.sh
    08-generate-configs.sh
    09-generate-roster.sh
    10-create-project-rpm.sh
    # include the mini so it looks pro, even if hidden in menu
    xx-rebuild-thin-el7-min.sh
  )

  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      stamp_header "$f"
    else
      warn "Skipping missing: modules/$f"
    fi
  done
  echo
  b "Done."; echo
}

main "$@"
