#!/usr/bin/env bash
#===============================================================
#Script Name: 04-extract-binaries.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Extract controller binaries
#About: Unpacks onedir controllers into vendor paths (EL7/8/9).
#===============================================================
#!/bin/bash
# Script Name: 04-extract-binaries.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Extract onedir vendors
# About: Extracts EL7/8/9 onedir trees, overlays RPMs, normalizes perms.
#!/bin/bash
set -euo pipefail

#---------------------------
# Config (editable)
#---------------------------
PROJECT_ROOT="/sto/salt-shaker"
OFFLINE_DIR="$PROJECT_ROOT/offline/salt"
TARBALLS_DIR="$OFFLINE_DIR/tarballs"
RPM_EL7_DIR="$OFFLINE_DIR/el7"
RPM_EL8_DIR="$OFFLINE_DIR/el8"
RPM_EL9_DIR="$OFFLINE_DIR/el9"
VENDOR_DIR="$PROJECT_ROOT/vendor"
LOG1="$(cd "$(dirname "$0")/.." && pwd)/logs/salt-shaker.log"
LOG2="$PROJECT_ROOT/logs/salt-shaker.log"
DEFAULT_PLATFORM="el7"           # el7|el8|el9
REQUIRED_FREE_SLACK_MB=200       # buffer on top of 2x tarball size
MODULE_SHORT="Extract onedir + overlay RPMs to vendor"
MODULE_DESC="Extracts onedir tarball, overlays Salt RPMs, fixes shebangs, normalizes perms, validates."
#---------------------------

# Symbols (ASCII-safe fallbacks)
ICON_OK="✓"; ICON_WARN="⚠"; ICON_ERR="✖"
# Colors kept, but console output is minimal
CLR_RESET='\033[0m'
CLR_OK='\033[1;32m'
CLR_WARN='\033[1;33m'
CLR_ERR='\033[1;31m'

mkdir -p "$(dirname "$LOG1")" "$(dirname "$LOG2")" || true

_ts() { date +"%Y-%m-%d %H:%M:%S"; }

# File logging (timestamped). Console is minimal: only OK/WARN/ERROR.
_file_log() {
  local level="$1"; shift
  local msg="$*"
  local line="[$(_ts)] [$level] $msg"
  printf "%s\n" "$line" >> "$LOG1"
  printf "%s\n" "$line" >> "$LOG2"
}

ok()   { _file_log "OK"    "$*";   printf "%b%s %s%b\n"   "$CLR_OK"   "$ICON_OK" "$*" "$CLR_RESET"; }
warn() { _file_log "WARN"  "$*";   printf "%b%s %s%b\n"   "$CLR_WARN" "$ICON_WARN" "$*" "$CLR_RESET"; }
err()  { _file_log "ERROR" "$*";   printf "%b%s %s%b\n"   "$CLR_ERR"  "$ICON_ERR" "$*" "$CLR_RESET"; }
# Internal steps/information go only to log files (no console noise)
log()  { _file_log "INFO"  "$*"; }
step() { _file_log "STEP"  "$*"; }

about() {
  cat <<'EOF'
Extracts and assembles a portable SaltStack toolchain:
- Extracts specified onedir tarball into vendor/<platform>/salt
- Overlays Salt RPM payloads (salt-ssh, salt, salt-cloud) into the onedir
- Fixes python shebangs to bundled Python in onedir
- Normalizes permissions and validates key binaries
- Quiet console output (checkmarks only); full details in logs
- Flags: --all (el7+el8+el9), --dry-run (checks only), --tarball <path> override
- Env: SALT_SHAKER_DEFAULT_ALL=1|0 (default 1) controls default behavior when no flags are given
EOF
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [-a] [-p el7|el8|el9] [--all] [--force] [--dry-run] [--tarball <path>]
  -h             Show help
  -a             About
  -p <plat>      Platform (default: $DEFAULT_PLATFORM)
  --all          Process el7, el8, and el9 in sequence
  --force        Remove and recreate vendor/<plat>/salt
  --dry-run      Perform validations only (no writes or extraction)
  --tarball <p>  Override onedir tarball path for the selected platform
Env:
  SALT_SHAKER_DEFAULT_ALL=1|0  Default multi-platform behavior when no -p/--all is given (default: 1)
EOF
}

cleanup() {
  local ec=$?
  if [ $ec -ne 0 ]; then err "Module 04 aborted (exit $ec)"; fi
}
trap cleanup EXIT

#----------------------------------
# Defaults & option parsing (EL7-safe)
#----------------------------------
: "${SALT_SHAKER_DEFAULT_ALL:=1}"
case "$(printf "%s" "$SALT_SHAKER_DEFAULT_ALL" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|y) DO_ALL_DEFAULT=1 ;;
  *)            DO_ALL_DEFAULT=0 ;;
esac

FORCE=0
DRYRUN=0
DO_ALL=$DO_ALL_DEFAULT
PLATFORM="$DEFAULT_PLATFORM"
TARBALL_OVERRIDE=""
SUMMARY_FILE="$PROJECT_ROOT/tmp/04-summary.$$"
mkdir -p "$PROJECT_ROOT/tmp"; chmod 700 "$PROJECT_ROOT/tmp" || true
: > "$SUMMARY_FILE"

while [ $# -gt 0 ]; do
  case "${1:-}" in
    -h|--help) usage; exit 0;;
    -a|--about) about; exit 0;;
    -p) PLATFORM="${2:-}"; DO_ALL=0; shift 2;;
    --all) DO_ALL=1; shift;;
    --force) FORCE=1; shift;;
    --dry-run) DRYRUN=1; shift;;
    --tarball) TARBALL_OVERRIDE="${2:-}"; shift 2;;
    *) err "Unknown option: $1"; usage; exit 2;;
  esac
done

case "$PLATFORM" in
  el7|el8|el9) ;;
  *) err "Invalid platform '$PLATFORM'. Use el7|el8|el9."; exit 2;;
esac

#----------------------------------
# Helpers
#----------------------------------
size_mb_of_dir() {
  local d="$1"
  [ -d "$d" ] || { echo "0"; return; }
  local kb; kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
  [ -n "$kb" ] || kb=0
  echo $(( kb / 1024 ))
}

detect_python_path() {
  local root="$1"
  if   [ -x "$root/bin/python3.10" ]; then echo "$root/bin/python3.10"; return 0
  elif [ -x "$root/bin/python3.11" ]; then echo "$root/bin/python3.11"; return 0
  elif [ -x "$root/bin/python3" ]; then echo "$root/bin/python3"; return 0
  fi
  local p; p="$(find "$root/pyenv" -maxdepth 4 -type f -name 'python3*' -perm -u+x 2>/dev/null | head -n1 || true)"
  [ -n "$p" ] && echo "$p" || echo ""
}

detect_launcher_path() {
  local root="$1" name="$2"
  if   [ -x "$root/$name" ]; then echo "$root/$name"; return 0
  elif [ -x "$root/bin/$name" ]; then echo "$root/bin/$name"; return 0
  else echo ""; return 1
  fi
}

#----------------------------------
# Core worker (per-platform)
#----------------------------------
run_for_platform() {
  local PLATFORM="$1"
  local TARBALL_OVERRIDE="${2:-}"

  local vendor_platform_dir="$VENDOR_DIR/$PLATFORM"
  local vendor_salt_dir="$vendor_platform_dir/salt"
  local tmp_dir="$PROJECT_ROOT/tmp/04-extract.$$.$PLATFORM"

  mkdir -p "$VENDOR_DIR" "$PROJECT_ROOT/tmp"
  chmod 700 "$PROJECT_ROOT/tmp" || true

  # Select tarball based on platform
  local tarball="" rpm_dir=""
  case "$PLATFORM" in
    el7) tarball="$TARBALLS_DIR/salt-3006.15-onedir-linux-x86_64.tar.xz" ; rpm_dir="$RPM_EL7_DIR" ;;
    el8) tarball="$TARBALLS_DIR/salt-3007.8-onedir-linux-x86_64.tar.xz"  ; rpm_dir="$RPM_EL8_DIR" ;;
    el9) tarball="$TARBALLS_DIR/salt-3007.8-onedir-linux-x86_64.tar.xz"  ; rpm_dir="$RPM_EL9_DIR" ;;
  esac
  [ -n "$TARBALL_OVERRIDE" ] && tarball="$TARBALL_OVERRIDE"

  step "[$PLATFORM] Begin"

  # Validations
  if [ ! -r "$tarball" ]; then
    warn "[$PLATFORM] Tarball missing: $tarball (skipping)"
    echo "$PLATFORM,SKIPPED,0,0,,," >> "$SUMMARY_FILE"
    return 1
  fi
  if [ ! -d "$rpm_dir" ]; then
    warn "[$PLATFORM] RPM directory missing: $rpm_dir (overlay skipped)"
  fi
  chmod u+rw "$tarball" || true

  # Integrity + space
  local tarball_size_bytes tarball_size_mb required_mb fs_path df_out free_kb free_mb
  tarball_size_bytes=$(stat -c '%s' "$tarball" 2>/dev/null || stat -f '%z' "$tarball" 2>/dev/null || echo 0)
  tarball_size_mb=$(( (tarball_size_bytes + 1024*1024 - 1) / (1024*1024) ))
  required_mb=$(( tarball_size_mb * 2 + REQUIRED_FREE_SLACK_MB ))

  if ! tar -tJf "$tarball" >/dev/null 2>&1; then
    warn "[$PLATFORM] Tarball corrupt/unsupported: $tarball (skipping)"
    echo "$PLATFORM,CORRUPT,$tarball_size_mb,0,,," >> "$SUMMARY_FILE"
    return 1
  fi
  ok "[$PLATFORM] Tarball OK (${tarball_size_mb}MB)"

  fs_path="$VENDOR_DIR"
  df_out=$(df -Pk "$fs_path" | tail -1)
  free_kb=$(echo "$df_out" | awk '{print $4}')
  free_mb=$(( free_kb / 1024 ))
  if [ "$DRYRUN" -eq 0 ] && [ "$free_mb" -lt "$required_mb" ]; then
    warn "[$PLATFORM] Not enough space: need ${required_mb}MB, have ${free_mb}MB (skipping)"
    echo "$PLATFORM,NO-SPACE,$tarball_size_mb,0,,," >> "$SUMMARY_FILE"
    return 1
  fi
  [ "$DRYRUN" -eq 1 ] && ok "[$PLATFORM] DRY-RUN checks passed"

  # RPM discovery (info -> log only)
  step "[$PLATFORM] Scan RPMs"
  local rpm_count=0
  if ls "$rpm_dir"/*.rpm >/dev/null 2>&1; then
    for rpm in "$rpm_dir"/*.rpm; do
      [ -e "$rpm" ] || continue
      case "$(basename "$rpm")" in
        salt-ssh-*|salt-cloud-*|salt-[0-9]*.rpm|salt-*.rpm) rpm_count=$((rpm_count+1)); log "[$PLATFORM] RPM: $(basename "$rpm")";;
        *) :;;
      esac
    done
  fi
  [ "$rpm_count" -gt 0 ] && ok "[$PLATFORM] RPMs found: $rpm_count" || warn "[$PLATFORM] No Salt RPMs to overlay"

  # Exit for DRY-RUN
  if [ "$DRYRUN" -eq 1 ]; then
    echo "$PLATFORM,DRYRUN,$tarball_size_mb,0,,," >> "$SUMMARY_FILE"
    ok "[$PLATFORM] Dry-run complete"
    return 0
  fi

  # Prepare vendor dir
  if [ -d "$vendor_salt_dir" ]; then
    if [ "$FORCE" -eq 1 ]; then
      rm -rf "$vendor_salt_dir"
      ok "[$PLATFORM] Cleared existing vendor"
    else
      warn "[$PLATFORM] Reusing existing vendor (use --force to replace)"
    fi
  fi
  mkdir -p "$vendor_salt_dir"; chmod 700 "$vendor_platform_dir" || true

  # Extract onedir
  tar -xJf "$tarball" -C "$vendor_platform_dir"
  if [ ! -d "$vendor_salt_dir" ]; then
    local top; top=$(find "$vendor_platform_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)
    if [ -n "$top" ] && [ "$top" != "$vendor_salt_dir" ]; then mv "$top" "$vendor_salt_dir"; fi
  fi
  ok "[$PLATFORM] Onedir extracted"

  # Extract RPMs to temp and overlay
  local tmp_dir="$PROJECT_ROOT/tmp/04-extract.$$.$PLATFORM"
  mkdir -p "$tmp_dir/rpms"; chmod 700 "$tmp_dir" || true
  local extracted=0
  for rpm in "$rpm_dir"/*.rpm; do
    [ -e "$rpm" ] || continue
    case "$(basename "$rpm")" in
      salt-ssh-*|salt-cloud-*|salt-[0-9]*.rpm|salt-*.rpm) ;;
      *) continue;;
    esac
    if command -v rpm2cpio >/dev/null 2>&1; then
      if rpm2cpio "$rpm" 2>/dev/null | (cd "$tmp_dir/rpms" && cpio -idmv --no-absolute-filenames >/dev/null 2>&1); then
        extracted=$((extracted+1))
      fi
    fi
  done
  [ "$extracted" -gt 0 ] && ok "[$PLATFORM] RPMs extracted: $extracted" || warn "[$PLATFORM] No RPM payloads extracted"

  # Overlay (usr/bin, python libs, etc/salt)
  if [ -d "$tmp_dir/rpms/usr" ]; then
    mkdir -p "$vendor_salt_dir/bin" "$vendor_salt_dir/etc/salt"
    [ -d "$tmp_dir/rpms/usr/bin" ] && cp -a "$tmp_dir/rpms/usr/bin/." "$vendor_salt_dir/bin/" || true
    if ls -d "$tmp_dir/rpms/usr/lib"*/python* >/dev/null 2>&1; then
      for pyroot in "$tmp_dir/rpms/usr/lib"*/python*; do
        [ -d "$pyroot" ] || continue
        local site; site="$(find "$vendor_salt_dir" -maxdepth 3 -type d -name site-packages | head -n1 || true)"
        if [ -n "$site" ]; then cp -a "$pyroot/"* "$site/" || true
        else
          local base="$vendor_salt_dir/lib/$(basename "$pyroot")"
          mkdir -p "$base"; cp -a "$pyroot/"* "$base/" || true
        fi
      done
    fi
    [ -d "$tmp_dir/rpms/etc/salt" ] && cp -a "$tmp_dir/rpms/etc/salt/." "$vendor_salt_dir/etc/salt/" || true
  fi
  ok "[$PLATFORM] Overlay complete"

  # Shebang fixes (bin/ OR pyenv/versions/*/bin/)
  local py; py="$(detect_python_path "$vendor_salt_dir")"
  if [ -n "$py" ]; then
    find "$vendor_salt_dir" -type f -perm -u+x -print0 2>/dev/null | while IFS= read -r -d '' f; do
      head -c 2 "$f" 2>/dev/null | grep -q "^#!" || continue
      if head -n1 "$f" | grep -Eq '^#!.*/python'; then sed -i.bak "1s|^#!.*python.*$|#!$py|" "$f" && rm -f "$f.bak"; fi
    done
    ok "[$PLATFORM] Shebangs set to $py"
  else
    warn "[$PLATFORM] Bundled Python not found; skipped shebang fix"
  fi

  # Permissions
  find "$vendor_salt_dir" -type d -exec chmod 755 {} + 2>/dev/null || true
  find "$vendor_salt_dir" -type f -name "*.sh" -exec chmod 755 {} + 2>/dev/null || true
  for b in salt-ssh salt-call salt-minion salt salt-api salt-cloud; do
    [ -e "$vendor_salt_dir/$b" ] && chmod 755 "$vendor_salt_dir/$b" || true
    [ -e "$vendor_salt_dir/bin/$b" ] && chmod 755 "$vendor_salt_dir/bin/$b" || true
  done
  for p in python3 python3.10 python3.11; do
    [ -e "$vendor_salt_dir/bin/$p" ] && chmod 755 "$vendor_salt_dir/bin/$p" || true
  done
  if ls "$vendor_salt_dir/pyenv"/versions/*/bin/python3* >/dev/null 2>&1; then
    chmod 755 "$vendor_salt_dir"/pyenv/versions/*/bin/python3* 2>/dev/null || true
  fi
  ok "[$PLATFORM] Permissions normalized"

  # Validation (pyenv optional if python is present)
  local missing=0
  local ssh_path call_path
  local py_path="$(detect_python_path "$vendor_salt_dir")"
  ssh_path="$(detect_launcher_path "$vendor_salt_dir" "salt-ssh")" || true
  call_path="$(detect_launcher_path "$vendor_salt_dir" "salt-call")" || true

  [ -z "$py_path" ]   && { warn "[$PLATFORM] Missing python3.x"; missing=$((missing+1)); }
  [ -z "$ssh_path" ]  && { warn "[$PLATFORM] Missing salt-ssh";  missing=$((missing+1)); }
  [ -z "$call_path" ] && { warn "[$PLATFORM] Missing salt-call"; missing=$((missing+1)); }
  [ -d "$vendor_salt_dir/lib" ] || { warn "[$PLATFORM] Missing lib/"; missing=$((missing+1)); }
  # Do not require pyenv if python is present
  [ -z "$py_path" ] && [ ! -d "$vendor_salt_dir/pyenv" ] && warn "[$PLATFORM] Missing pyenv/ (not required if python in bin/)"

  local vendor_sz_mb; vendor_sz_mb="$(size_mb_of_dir "$vendor_salt_dir")"
  if [ "$missing" -gt 0 ]; then
    warn "[$PLATFORM] Validation: $missing issue(s)"
    echo "$PLATFORM,WARN,$tarball_size_mb,$vendor_sz_mb,$py_path,$ssh_path,$call_path" >> "$SUMMARY_FILE"
  else
    ok "[$PLATFORM] Validation OK"
    echo "$PLATFORM,OK,$tarball_size_mb,$vendor_sz_mb,$py_path,$ssh_path,$call_path" >> "$SUMMARY_FILE"
  fi

  ok "[$PLATFORM] Done"
  return 0
}

#----------------------------------
# Orchestrate one or many platforms
#----------------------------------
built_any=0
if [ "$DO_ALL" -eq 1 ]; then
  step "[ALL] Processing el7, el8, el9"
  for p in el7 el8 el9; do
    if run_for_platform "$p" "$TARBALL_OVERRIDE"; then built_any=1; fi
  done
else
  if run_for_platform "$PLATFORM" "$TARBALL_OVERRIDE"; then built_any=1; fi
fi

#----------------------------------
# Final summary table (console-friendly)
#----------------------------------
printf "\n"
printf "SUMMARY (vendors)\n"
printf "%-6s | %-8s | %10s | %12s | %-24s | %-30s | %-30s\n" "Plat" "Status" "Tarball(MB)" "Vendor(MB)" "Python" "salt-ssh" "salt-call"
printf "%s\n" "------ | -------- | ---------- | ------------ | ------------------------ | ------------------------------ | ------------------------------"
if [ -s "$SUMMARY_FILE" ]; then
  while IFS=',' read -r plat status tmb vmb pyp sshp callp; do
    short() {
      local s="$1" max="$2"
      [ ${#s} -le "$max" ] && { printf "%s" "$s"; return; }
      printf "...%s" "${s: -$((max-3))}"
    }
    printf "%-6s | %-8s | %10s | %12s | %-24s | %-30s | %-30s\n" \
      "$plat" "$status" "$tmb" "$vmb" "$(short "$pyp" 24)" "$(short "$sshp" 30)" "$(short "$callp" 30)"
  done < "$SUMMARY_FILE"
else
  printf "%s\n" "(no platforms processed)"
fi
printf "\n"

if [ "$built_any" -eq 1 ]; then
  ok "[ALL] Completed"
  exit 0
else
  err "[ALL] No platforms built"
  exit 1
fi

