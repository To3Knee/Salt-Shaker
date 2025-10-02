#!/bin/bash
#===============================================================
#Script Name: 06-check-vendors.sh
#Date: 10/01/2025
#Created By: T03KNEE
#Version: 6.0
#Short: Check vendor onedirs (el7/el8/el9) + EL7 thin tarball
#About: Validates vendor/el{7,8,9}/salt and vendor/el7/thin/salt-thin.tgz.
#       Picks controller onedir by host OS (el7→el7, el8→el8, el9→el9; fallback el8→el9→el7).
#       Wrapper detection improved: robust --print-env parsing (ssh/call wrappers).
#===============================================================

set -e -o pipefail
LC_ALL=C

# ---------- Colors/UI ----------
COLOR_MODE="auto"  # auto|always|never
[ -n "${SALT_SHAKER_COLOR:-}" ] && COLOR_MODE="always"
for i in "$@"; do
  case "$i" in
    --color=always) COLOR_MODE="always";;
    --color=never) COLOR_MODE="never";;
    --color=auto) COLOR_MODE="auto";;
  esac
done
use_color=0
case "$COLOR_MODE" in
  always) use_color=1;;
  never)  use_color=0;;
  auto)   [ -t 1 ] && use_color=1 || use_color=0;;
esac
if [ "$use_color" -eq 1 ]; then
  COK='\033[1;32m'; CWARN='\033[1;33m'; CERR='\033[1;31m'; CINFO='\033[0;36m'; CRESET='\033[0m'
else
  COK=""; CWARN=""; CERR=""; CINFO=""; CRESET=""
fi
ok(){ printf -- "%b✓ %s%b\n" "$COK" "$*" "$CRESET"; }
warn(){ printf -- "%b⚠ %s%b\n" "$CWARN" "$*" "$CRESET" >&2; }
err(){ printf -- "%b✖ %s%b\n" "$CERR" "$*" "$CRESET" >&2; }
info(){ printf -- "%b%s%b\n" "$CINFO" "$*" "$CRESET"; }
bar(){ printf -- "%b%s%b\n" "$CINFO" "══════════════════════════════════════════════════════════════════════" "$CRESET"; }

# ---------- Root detection ----------
RESOLVE_ABS(){ local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf -- "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf -- "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  fi
}
FIND_ROOT_UP(){ local d="$1" i=8
  while [ "$i" -gt 0 ] && [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then echo "$d"; return 0; fi
    d="$(dirname -- "$d")"; i=$((i-1))
  done; return 1
}
SCRIPT_ABS="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_ABS")"
if [ -n "${SALT_SHAKER_ROOT:-}" ] && [ -d "${SALT_SHAKER_ROOT}" ]; then
  PROJECT_ROOT="$(RESOLVE_ABS "$SALT_SHAKER_ROOT")"
else
  PROJECT_ROOT="$(FIND_ROOT_UP "$SCRIPT_DIR" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(FIND_ROOT_UP "$(pwd)" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(RESOLVE_ABS "$(pwd)")"
fi
short_path(){ local p="$1"; printf -- "%s" "$p" | sed "s#^${PROJECT_ROOT}/##"; }

# ---------- Paths ----------
LOG_DIR="${PROJECT_ROOT}/logs"; mkdir -p "$LOG_DIR" 2>/dev/null || true
MAIN_LOG="${LOG_DIR}/salt-shaker.log"; ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
VENDOR_EL7="${PROJECT_ROOT}/vendor/el7/salt"
VENDOR_EL8="${PROJECT_ROOT}/vendor/el8/salt"
VENDOR_EL9="${PROJECT_ROOT}/vendor/el9/salt"
THIN_TGZ="${PROJECT_ROOT}/vendor/el7/thin/salt-thin.tgz"
BIN_DIR="${PROJECT_ROOT}/bin"
CACHE_DIR="${PROJECT_ROOT}/.cache"

logi(){ printf -- "[%s] [INFO] %s\n" "$(date +'%F %T')" "$*" >>"$MAIN_LOG" 2>/dev/null || true; }
loge(){ printf -- "[%s] [ERROR] %s\n" "$(date +'%F %T')" "$*" | tee -a "$ERROR_LOG" >>"$MAIN_LOG" 2>/dev/null || true; }

# ---------- CLI ----------
SKIP_THIN_TEST=0; WRAPPER_TEST=1; FORCE_CTRL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-thin-test) SKIP_THIN_TEST=1;;
    --no-wrapper-test) WRAPPER_TEST=0;;
    --controller) shift || true; FORCE_CTRL="$1";;
    --color=*) : ;; # parsed above
    -h|--help)
      cat <<EOF
Usage: ${0##*/} [--controller el7|el8|el9] [--skip-thin-test] [--no-wrapper-test] [--color=always|auto|never]
Validates:
  • vendor/el7|el8|el9/salt onedirs (Python + salt tool versions)
  • vendor/el7/thin/salt-thin.tgz with relaxed 'salt/' archive check
  • Optional wrapper smoke tests (salt-ssh-el7|el8, salt-call-el8)
Controller:
  • Default: match host OS (el7/el8/el9) if present, else el8→el9→el7
  • Override with --controller elX
EOF
      exit 0;;
  esac; shift || true
done

# ---------- Host OS → elX ----------
HOST_EL=""
if [ -r /etc/os-release ]; then
  . /etc/os-release 2>/dev/null || true
  case "${VERSION_ID%%.*}" in 7) HOST_EL="el7";; 8) HOST_EL="el8";; 9) HOST_EL="el9";; esac
fi

# ---------- Helpers ----------
exists_exec(){ [ -x "$1" ] && [ -f "$1" ]; }
onedir_py(){ local od="$1"; if [ -x "${od}/bin/python3.10" ]; then echo "${od}/bin/python3.10"; elif [ -x "${od}/bin/python3" ]; then echo "${od}/bin/python3"; else echo ""; fi; }
onedir_run_version(){
  local od="$1" tool="$2" py; py="$(onedir_py "$od")"
  [ -z "$py" ] || [ ! -x "$py" ] || [ ! -x "${od}/${tool}" ] && { echo ""; return 1; }
  PYTHONHOME="$od" LD_LIBRARY_PATH="${od}/lib" PATH="${od}/bin:${PATH}" "${od}/${tool}" --version 2>&1 | head -n1 || true
}
onedir_pyver(){ local od="$1" py; py="$(onedir_py "$od")"; [ -z "$py" ] && { echo ""; return 1; }; "$py" -V 2>&1 || true; }
has_salt_in_tgz(){ local tgz="$1" cnt; cnt="$(tar -tzf "$tgz" 2>/dev/null | sed 's#^\./##' | grep -E '^salt(/|$)' -c || true)"; [ -z "$cnt" ] && cnt=0; echo "$cnt"; [ "$cnt" -gt 0 ]; }
wrapper_print_env(){
  local w="$1"
  if exists_exec "${BIN_DIR}/${w}"; then
    # capture both stdout and stderr; wrappers may write versions to stderr
    "${BIN_DIR}/${w}" --print-env 2>&1 || true
  else
    echo ""
  fi
}

pick_controller(){
  case "$FORCE_CTRL" in
    el7) [ -d "$VENDOR_EL7" ] && { echo "$VENDOR_EL7"; return 0; } ;;
    el8) [ -d "$VENDOR_EL8" ] && { echo "$VENDOR_EL8"; return 0; } ;;
    el9) [ -d "$VENDOR_EL9" ] && { echo "$VENDOR_EL9"; return 0; } ;;
  esac
  case "$HOST_EL" in
    el7) [ -d "$VENDOR_EL7" ] && { echo "$VENDOR_EL7"; return 0; } ;;
    el8) [ -d "$VENDOR_EL8" ] && { echo "$VENDOR_EL8"; return 0; } ;;
    el9) [ -d "$VENDOR_EL9" ] && { echo "$VENDOR_EL9"; return 0; } ;;
  esac
  [ -d "$VENDOR_EL8" ] && { echo "$VENDOR_EL8"; return 0; }
  [ -d "$VENDOR_EL9" ] && { echo "$VENDOR_EL9"; return 0; }
  [ -d "$VENDOR_EL7" ] && { echo "$VENDOR_EL7"; return 0; }
  echo ""; return 1
}

# ---------- Header ----------
bar; info "▶ Vendor & Thin Checks"; info "Project Root: ${PROJECT_ROOT}"; bar

# ---------- Per-platform table ----------
printf -- "%s\n" "Platform     | Status | Python        | salt-ssh                 | salt-call                | Path"
printf -- "%s\n" "------------ | ------ | ------------- | ------------------------ | ------------------------ | ------------------------------"
for plat in el7 el8 el9; do
  case "$plat" in
    el7) od="$VENDOR_EL7";;
    el8) od="$VENDOR_EL8";;
    el9) od="$VENDOR_EL9";;
  esac
  if [ -d "$od" ]; then
    pv="$(onedir_pyver "$od" | tr -s ' ')"
    sv_ssh="$(onedir_run_version "$od" "salt-ssh" | tr -s ' ')"
    sv_call="$(onedir_run_version "$od" "salt-call" | tr -s ' ')"
    printf -- "%-12s | %-6s | %-13s | %-24s | %-24s | %s\n" "$plat" "OK" "${pv:-?}" "${sv_ssh:-?}" "${sv_call:-?}" "$(short_path "$od")"
  else
    printf -- "%-12s | %-6s | %-13s | %-24s | %-24s | %s\n" "$plat" "MISS" "-" "-" "-" "$(short_path "$od")"
  fi
done
echo

# ---------- Controller banner ----------
CTRL_OD="$(pick_controller || true)"
if [ -z "$CTRL_OD" ]; then
  err "No controller onedir found under vendor/el{7,8,9}/salt"
  loge "Missing onedirs for all platforms"
  exit 2
fi
CTRL_LABEL="$(echo "$CTRL_OD" | sed -n 's#.*/vendor/\(el[0-9]\)/salt#\1#p')"
SSHV="$(onedir_run_version "$CTRL_OD" "salt-ssh" | tr -s ' ')"
CALLV="$(onedir_run_version "$CTRL_OD" "salt-call" | tr -s ' ')"
PYV="$(onedir_pyver "$CTRL_OD" | tr -s ' ')"

printf -- "READY  %b✓%b   (%s · %s · %s)\n" "$COK" "$CRESET" "${CTRL_LABEL:-controller}" "$CTRL_OD" "${PYV:-Python ?}"
printf -- "%s · %s\n" "${SSHV:-salt-ssh ?}" "${CALLV:-salt-call ?}"
echo

# ---------- Checklist ----------
echo "Checklist:"
echo "  [✓] Wrappers resolve onedir  (bin/salt-ssh-*) → $(short_path "$CTRL_OD")"
if [ -x "${CTRL_OD}/salt-ssh" ] && [ -x "${CTRL_OD}/salt-call" ] && [ -x "$(onedir_py "$CTRL_OD")" ]; then
  echo "  [✓] Controller onedir executable (python/salt-ssh/salt-call)"
else
  echo "  [⚠] Controller onedir executables not fully present"
fi

if [ -f "$THIN_TGZ" ] && [ -s "$THIN_TGZ" ]; then
  size_mb="$(du -m "$THIN_TGZ" 2>/dev/null | awk '{print $1}')"
  echo "  [✓] EL7 thin present (${size_mb}.0 MB)"
  if [ "$SKIP_THIN_TEST" -eq 1 ]; then
    echo "  [✓] EL7 thin import test skipped on controller (not required)"
  else
    cnt="$(has_salt_in_tgz "$THIN_TGZ")"
    if [ "$cnt" -gt 0 ]; then
      echo "  [✓] EL7 thin archive contains salt/ (entries: $cnt)"
    else
      echo "  [⚠] EL7 thin archive present but salt/ not detected — rebuild in module 05"
      loge "Thin present but salt/ not found by relaxed check; tgz=${THIN_TGZ}"
    fi
  fi
else
  echo "  [⚠] EL7 thin not found (build with module 05)"
  logi "Thin missing: ${THIN_TGZ}"
fi
echo

# ---------- Advisories ----------
echo "Advisories:"
ADV="none"
if [ ! -d "$VENDOR_EL8" ] && [ ! -d "$VENDOR_EL9" ] && [ ! -d "$VENDOR_EL7" ]; then
  ADV="• extract vendors with modules/04-extract-binaries.sh"
elif [ ! -f "$THIN_TGZ" ]; then
  ADV="• build EL7 thin with modules/05-build-thin-el7.sh"
fi
[ "$ADV" = "none" ] && echo "  • none" || echo "  $ADV"

# ---------- Wrapper smoke tests ----------
if [ "$WRAPPER_TEST" -eq 1 ]; then
  echo
  for w in salt-ssh-el7 salt-ssh-el8 salt-call-el8; do
    if [ -x "${BIN_DIR}/${w}" ]; then
      ENVOUT="$(wrapper_print_env "$w" | sed -n '1,40p' || true)"
      if printf '%s\n' "$ENVOUT" | grep -E -q '(^ONEDIR=|^CONF_DIR=|^PROJECT_ROOT=|salt-(ssh|call)=)'; then
        ok "Wrapper ${w} OK"
        logi "Wrapper ${w} --print-env (truncated):
${ENVOUT}"
      else
        warn "Wrapper ${w}: --print-env not available or empty"
        logi "Wrapper ${w} --print-env (empty or missing signature)"
      fi
    else
      warn "Wrapper ${w} not found (install via env/90-install-env-wrappers.sh)"
    fi
  done
fi

echo
ok "READY."
exit 0

