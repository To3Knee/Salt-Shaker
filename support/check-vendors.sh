# support/check-vendors.sh
#!/bin/bash
#===============================================================
# Script:   support/check-vendors.sh
# Purpose:  Validate vendor/el{7,8,9} Salt environments (+ EL7 thin)
# Version:  1.0
# Compat:   EL7 (bash 4.2+) / EL8 / EL9
#===============================================================

set -o pipefail

#------------------------- Colors & Bars -----------------------
if [ -t 1 ]; then
  GRY=$'\033[90m'; RED=$'\033[91m'; GRN=$'\033[92m'; YLW=$'\033[93m'
  BLU=$'\033[94m'; CYN=$'\033[96m'; WHT=$'\033[97m'; NON=$'\033[0m'
else
  GRY= RED= GRN= YLW= BLU= CYN= WHT= NON=
fi
BAR="══════════════════════════════════════════════════════════════════════════" # 74 cols

print_bar(){ echo -e "${BLU}${BAR}${NON}"; }
print_h(){ echo -e "${WHT}$1${NON}"; }
ok(){ echo -e "  ${GRN}✓${NON} $1"; }
warn(){ echo -e "  ${YLW}!${NON} $1"; }
err(){ echo -e "  ${RED}✗${NON} $1"; }

#------------------------- Root Detection ----------------------
PROJECT_ROOT="${SALT_SHAKER_ROOT:-}"
if [ -z "$PROJECT_ROOT" ]; then
  # try relative to this script: support/ -> project root = parent
  THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [ -f "${THIS_DIR}/../Salt-Shaker.sh" ] || [ -d "${THIS_DIR}/../vendor" ]; then
    PROJECT_ROOT="$(cd "${THIS_DIR}/.." && pwd)"
  else
    PROJECT_ROOT="${PWD}"
  fi
fi
[ -d "$PROJECT_ROOT" ] || { echo "${RED}[ERROR] Project root not found${NON}" >&2; exit 1; }

VENDOR_DIR="${PROJECT_ROOT}/vendor"
VENDOR_EL7="${VENDOR_DIR}/el7"
VENDOR_EL8="${VENDOR_DIR}/el8"
VENDOR_EL9="${VENDOR_DIR}/el9"
VENDOR_EL7_THIN="${VENDOR_EL7}/thin"

LOG_DIR="${PROJECT_ROOT}/logs"; mkdir -p "$LOG_DIR" 2>/dev/null || true
MAIN_LOG="${LOG_DIR}/vendor-check.log"

VERBOSITY=0
_log_ts(){ date '+%Y-%m-%d %H:%M:%S'; }
logf(){ printf '%s [%s] %s\n' "$(_log_ts)" "$1" "$2" >> "$MAIN_LOG" 2>/dev/null || true; }
note(){ [ "$VERBOSITY" -ge 2 ] && echo -e "${GRY}.. $1${NON}"; logf NOTE "$1"; }

#------------------------- Helpers -----------------------------
timeout_cmd(){ if command -v timeout >/dev/null 2>&1; then timeout "$@"; else "$@"; fi; }

detect_salt_root(){ # $1=platform dir
  local p="$1"
  if [ -d "${p}/salt/bin" ]; then printf '%s' "${p}/salt"; return 0; fi
  # fallback: first dir that has python3* under it
  local cand; cand="$(find "$p" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
  if [ -n "$cand" ] && find "$cand" -maxdepth 3 -type f -name 'python3*' 2>/dev/null | grep -q .; then
    printf '%s' "$cand"; return 0
  fi
  printf '%s' "$p"
}

find_python_bin(){ # $1=root
  local root="$1"
  find "$root" -maxdepth 10 -type f -perm -u+x \( -name 'python3*' -o -name 'python' \) 2>/dev/null | head -n1
}

prep_env(){ # $1=root
  local root="$1"
  local bins libs sps
  bins="$(find "$root" -maxdepth 10 -type d -name bin 2>/dev/null | tr '\n' ':' | sed 's/:$//')"
  libs="$(find "$root" -maxdepth 10 -type d \( -name lib -o -name lib64 \) 2>/dev/null | tr '\n' ':' | sed 's/:$//')"
  sps="$(find "$root" -maxdepth 10 -type d -name site-packages 2>/dev/null | tr '\n' ':' | sed 's/:$//')"
  [ -n "$bins" ] && export PATH="${bins}:$PATH"
  [ -n "$libs" ] && export LD_LIBRARY_PATH="${libs}:${LD_LIBRARY_PATH}"
  [ -n "$sps" ]  && export PYTHONPATH="${sps}:${PYTHONPATH}"
}

bin_path(){ # $1=root $2=name
  local root="$1" name="$2"
  find "$root" -maxdepth 10 -type f -name "$name" -perm -u+x 2>/dev/null | head -n1
}

get_salt_version(){ # $1=bin path
  local b="$1"
  timeout_cmd 5 "$b" --version 2>/dev/null | tr -d '\r' | head -n1
}

cmp_expect(){ # $1=reported $2=expect
  [ -z "$2" ] && return 0
  echo "$1" | grep -q "$2"
}

check_el7_thin(){
  local thin="${VENDOR_EL7_THIN}"
  local okcount=0
  if [ ! -d "$thin" ]; then err "EL7 thin: directory missing ($thin)"; return 1; fi
  if [ -f "${thin}/salt-thin.tgz" ]; then
    ok "EL7 thin: salt-thin.tgz present"
    if tar -tzf "${thin}/salt-thin.tgz" 'salt/__init__.py' >/dev/null 2>&1; then ok "EL7 thin: contains salt package"; okcount=$((okcount+1)); else err "EL7 thin: salt package missing in tar"; fi
    if tar -tzf "${thin}/salt-thin.tgz" 'jinja2/__init__.py' >/dev/null 2>&1; then ok "EL7 thin: contains jinja2"; okcount=$((okcount+1)); else warn "EL7 thin: jinja2 missing"; fi
  else
    err "EL7 thin: salt-thin.tgz missing"; return 1
  fi
  if [ -x "${thin}/bin/salt-ssh" ]; then
    local head1; head1="$(head -n1 "${thin}/bin/salt-ssh" 2>/dev/null)"
    if echo "$head1" | grep -qE '#!.*python2'; then ok "EL7 thin: bin/salt-ssh uses python2 shebang"; okcount=$((okcount+1)); else warn "EL7 thin: bin/salt-ssh shebang not python2"; fi
  else
    warn "EL7 thin: bin/salt-ssh wrapper missing"
  fi
  [ "$okcount" -ge 2 ]
}

#------------------------- Args & Interactive ------------------
PLAT="all"
EXPECT_SALT=""
ASSUME_YES=false

while [ $# -gt 0 ]; do
  case "$1" in
    -p) shift; PLAT="${1:-all}";;
    -v) shift; EXPECT_SALT="${1:-}";;
    --debug) VERBOSITY=2;;
    -y|--yes) ASSUME_YES=true;;
    -h|--help)
      cat <<EOF
Usage: support/check-vendors.sh [-p el7|el8|el9|all] [-v expected_salt_version] [--debug] [-y]
- Default: interactive prompts if TTY and no flags.
EOF
      exit 0;;
    *) ;;
  esac
  shift
done

if [ -t 0 ] && [ "$PLAT" = "all" ] && [ -z "$EXPECT_SALT" ] && [ "$VERBOSITY" -eq 0 ] && [ "$ASSUME_YES" = false ]; then
  print_bar; print_h "▶ Vendor Environment Validator (Interactive)"; print_bar
  read -r -e -p "$(echo -e "${CYN}Platform(s) to test [all|el7|el8|el9] (default all): ${NON}")" ans
  [ -n "$ans" ] && PLAT="$ans"
  read -r -e -p "$(echo -e "${CYN}Expected Salt version (e.g., 3006.15) [optional]: ${NON}")" ans
  [ -n "$ans" ] && EXPECT_SALT="$ans"
  read -r -e -p "$(echo -e "${CYN}Enable debug output? [y/N]: ${NON}")" ans
  if echo "$ans" | grep -qi '^y'; then VERBOSITY=2; fi
fi

case "$PLAT" in all|el7|el8|el9) ;; *) echo "${RED}Invalid -p '${PLAT}'${NON}"; exit 2;; esac

#------------------------- Execution ---------------------------
print_bar; print_h "📦 Vendor Check: $(basename "$PROJECT_ROOT")"; print_bar
echo "Project root: ${PROJECT_ROOT}"
echo "Log file    : ${MAIN_LOG}"
[ -n "$EXPECT_SALT" ] && echo "Expect Salt : ${EXPECT_SALT}"

ANY_FAIL=0
run_one(){
  local plat="$1" plat_dir root
  case "$plat" in
    el7) plat_dir="$VENDOR_EL7";;
    el8) plat_dir="$VENDOR_EL8";;
    el9) plat_dir="$VENDOR_EL9";;
  esac

  print_bar; print_h "▶ ${plat^^} • Vendor Validation"; print_bar

  if [ ! -d "$plat_dir" ]; then err "vendor/${plat} missing"; ANY_FAIL=1; return; fi

  root="$(detect_salt_root "$plat_dir")"
  if [ ! -d "$root" ]; then err "salt root not found under vendor/${plat}"; ANY_FAIL=1; return; fi
  ok "Found salt root: ${root#$PROJECT_ROOT/}"
  note "Preparing environment (PATH/LD_LIBRARY_PATH/PYTHONPATH)"
  prep_env "$root"

  local py; py="$(find_python_bin "$root")"
  if [ -n "$py" ]; then
    local pyv; pyv="$("$py" -V 2>&1 | tr -d '\r')"
    ok "Python: ${pyv} ($py)"
  else
    err "Python not found in vendor/${plat}"; ANY_FAIL=1
  fi

  # Check key salt binaries
  local bins=("salt-ssh" "salt-call" "salt-key" "salt-cloud")
  local bpath bver
  local missing=0 mismatch=0
  for b in "${bins[@]}"; do
    bpath="$(bin_path "$root" "$b")"
    if [ -n "$bpath" ]; then
      bver="$(get_salt_version "$bpath")"
      if [ -n "$bver" ]; then
        ok "$b --version: ${bver}"
        if [ -n "$EXPECT_SALT" ] && ! cmp_expect "$bver" "$EXPECT_SALT"; then
          warn "$b version mismatch vs expected '${EXPECT_SALT}'"
          mismatch=$((mismatch+1))
        fi
      else
        warn "$b present but did not return --version cleanly"
      fi
    else
      warn "$b not found"
      missing=$((missing+1))
    fi
  done

  # EL7 thin checks
  if [ "$plat" = "el7" ]; then
    print_h "• EL7 Thin Payload"
    if check_el7_thin; then ok "EL7 thin payload looks good"; else warn "EL7 thin payload incomplete"; fi
  fi

  # Final per-plat status
  if [ "$missing" -gt 0 ]; then ANY_FAIL=1; fi
  if [ "$mismatch" -gt 0 ]; then ANY_FAIL=1; fi

  if [ "$missing" -eq 0 ] && [ "$mismatch" -eq 0 ]; then
    ok "${plat^^} vendor validation PASSED"
  else
    err "${plat^^} vendor validation had issues"
  fi
}

case "$PLAT" in
  all) run_one el7; run_one el8; run_one el9;;
  el7|el8|el9) run_one "$PLAT";;
esac

print_bar; print_h "Validation Summary"; print_bar
if [ "$ANY_FAIL" -eq 0 ]; then
  echo -e "${GRN}All requested vendors passed validation.${NON}"
  exit 0
else
  echo -e "${YLW}Some checks failed. See ${MAIN_LOG} for details.${NON}"
  exit 1
fi

