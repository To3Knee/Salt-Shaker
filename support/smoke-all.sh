#!/bin/bash
#===============================================================
#Script Name: smoke-all.sh
#Date: 10/03/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.8
#Short: End-to-end gates; tidy, runtime-first, no drips
#About: Adds Gate 0 verify, auto wrapper, packages without leaving tmp artifacts.
#===============================================================
set -euo pipefail
LC_ALL=C

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD="$(tput bold 2>/dev/null || true)"; RESET="$(tput sgr0 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"; RED="$(tput setaf 1 2>/dev/null || true)"
  CYAN="$(tput setaf 6 2>/dev/null || true)"
else
  BOLD=""; RESET=""; GREEN=""; RED=""; CYAN=""
fi

ROOT="${SALT_SHAKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
RUNTIME_DIR="${SALT_SHAKER_RUNTIME_DIR:-$ROOT/runtime}"
CONF_DIR="$RUNTIME_DIR/conf"
TMP_DIR="$ROOT/tmp"
LOG_DIR="$ROOT/logs"
mkdir -p "$TMP_DIR" "$LOG_DIR"

HOST="${HOST:-}"
USERN="${USERN:-root}"
PORT="${PORT:-22}"
AUTOFIX=0
DO_PACKAGE=""
PKG_PREFIX=""
PKG_VENDOR=""
YES=0
ARTIFACT_LIST=0
WRAPPER_OPT="auto"

usage(){ cat <<'HLP'
Usage: support/smoke-all.sh [options]
  --host HOST             Remote host (optional)
  --user USER             SSH user (default: root)
  --port N                SSH port (default: 22)
  --wrapper auto|el7|el8  Wrapper selection (default: auto)
  --autofix               Fix CSV BOM/CRLF before lint
  --package               Run packaging gate
  --vendor LIST           Vendors "el7,el8" | all | none
  --prefix PATH           Absolute install prefix
  --artifact-list         Show tar listing after package
  --yes                   Non-interactive
HLP
}
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --host) HOST="${2:-}"; shift 2;;
    --user) USERN="${2:-$USERN}"; shift 2;;
    --port) PORT="${2:-$PORT}"; shift 2;;
    --wrapper) WRAPPER_OPT="${2:-auto}"; shift 2;;
    --autofix) AUTOFIX=1; shift;;
    --package) DO_PACKAGE="y"; shift;;
    --vendor) PKG_VENDOR="${2:-}"; shift 2;;
    --prefix) PKG_PREFIX="${2:-}"; shift 2;;
    --artifact-list) ARTIFACT_LIST=1; shift;;
    --yes) YES=1; shift;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

ask(){ local p="$1" d="${2:-}"; if [ $YES -eq 1 ] || [ ! -t 0 ]; then echo "$d"; else read -r -p "$p " a; echo "${a:-$d}"; fi; }
banner(){ printf "\n${BOLD}════════ %s ════════${RESET}\n" "$1"; }
fail(){ printf "${RED}✖ %s${RESET}\n" "$1"; exit 2; }
pass(){ printf "${GREEN}✔ %s${RESET}\n" "$1"; }

detect_target_os(){
  local h="${1:-}" u="${2:-root}" p="${3:-22}"
  [ -z "$h" ] && { echo "unknown"; return 0; }
  local tmp="$TMP_DIR/detect.${h//[^A-Za-z0-9._-]/_}.$$.yaml"
  {
    echo "$h:"; echo "  host: $h"; echo "  user: $u"; echo "  port: $p"
    echo "  sudo: false"; echo "  tty: false"
    echo "  ssh_options:"; echo "    - StrictHostKeyChecking=no"; echo "    - UserKnownHostsFile=/dev/null"
  } > "$tmp"
  local WR="$ROOT/bin/salt-ssh-el8" out rc
  if [ ! -x "$WR" ]; then rm -f "$tmp"; echo "unknown"; return 0; fi
  set +e
  out="$("$WR" --ignore-host-keys -c "$CONF_DIR" --roster-file "$tmp" -W -t "$h" --user "$u" --askpass -r 'cat /etc/redhat-release || cat /etc/os-release' 2>&1)"
  rc=$?
  set -e
  rm -f "$tmp"
  [ $rc -eq 0 ] || { echo "unknown"; return 0; }
  printf '%s\n' "$out" | grep -qE 'release 7|VERSION_ID="?7' && { echo "7"; return 0; }
  printf '%s\n' "$out" | grep -qE 'release 8|VERSION_ID="?8' && { echo "8"; return 0; }
  printf '%s\n' "$out" | grep -qE 'release 9|VERSION_ID="?9' && { echo "9"; return 0; }
  echo "unknown"
}

# Gate 0
banner "Gate 0: Verify wrappers"
if [ -x "$ROOT/support/verify-wrappers.sh" ]; then
  set +e; "$ROOT/support/verify-wrappers.sh"; rc=$?; set -e
  [ $rc -eq 0 ] || fail "Wrapper drift detected. Run env/install-env-wrappers.sh"
  pass "Wrappers verified"
else
  echo "verify-wrappers.sh not found; skipping"
fi

# Gate 1
banner "Gate 1: Install wrappers"
[ -x "$ROOT/env/install-env-wrappers.sh" ] || fail "env/install-env-wrappers.sh missing"
"$ROOT/env/install-env-wrappers.sh" || fail "Wrapper install failed"
[ -x "$ROOT/bin/salt-ssh-el8" ] || fail "salt-ssh-el8 missing"
pass "Wrappers installed"

# Gate 2
banner "Gate 2: Wrappers sanity"
"$ROOT/bin/salt-ssh-el8" --version >/dev/null 2>&1 || fail "salt-ssh-el8 --version failed"
pass "salt-ssh-el8 healthy"

# Gate 3
banner "Gate 3: Generate configs"
"$ROOT/modules/08-generate-configs.sh" || fail "08 failed"
[ -f "$CONF_DIR/master" ] || fail "master missing"
grep -q '^thin_dir:' "$CONF_DIR/master" || fail "thin_dir not set"
pass "Configs OK"

# Gate 4
banner "Gate 4: CSV lint"
[ $AUTOFIX -eq 1 ] && "$ROOT/modules/02-create-csv.sh" --autofix >/dev/null 2>&1 || true
"$ROOT/modules/02-create-csv.sh" --lint || fail "CSV lint failed"
pass "CSV OK"

# Gate 5
banner "Gate 5: Generate roster"
"$ROOT/modules/09-generate-roster.sh" >/dev/null || fail "09 failed"
[ -f "$RUNTIME_DIR/roster/roster.yaml" ] || fail "runtime roster missing"
pass "Roster OK"

# Gate 6
DO_REMOTE="n"; [ -n "${HOST:-}" ] && DO_REMOTE="y"
if [ "$DO_REMOTE" = "y" ]; then
  banner "Gate 6: Remote smoke → $HOST"
  OSMAJ="$(detect_target_os "$HOST" "$USERN" "$PORT")"
  PICKED="${WRAPPER_OPT}"
  [ "$PICKED" = "auto" ] && { case "$OSMAJ" in 7) PICKED="el7";; 8|9) PICKED="el8";; *) PICKED="el8";; esac; }
  case "$PICKED" in
    el7) WRAP="$ROOT/bin/salt-ssh-el7"; PYBIN="/usr/bin/python";;
    el8) WRAP="$ROOT/bin/salt-ssh-el8"; PYBIN="/usr/bin/python3";;
    *) fail "Invalid wrapper";;
  esac
  TMP_ROSTER="$TMP_DIR/smoke.$(date +%Y%m%d-%H%M%S).$$.yaml"
  {
    echo "$HOST:"; echo "  host: $HOST"; echo "  user: $USERN"; echo "  port: $PORT"
    echo "  sudo: false"; echo "  tty: false"
    echo "  python_bin: $PYBIN"
    echo "  ssh_options:"; echo "    - StrictHostKeyChecking=no"; echo "    - UserKnownHostsFile=/dev/null"
  } > "$TMP_ROSTER"
  set +e
  "$WRAP" --ignore-host-keys -c "$CONF_DIR" --roster-file "$TMP_ROSTER" -W -t "$HOST" --user "$USERN" --askpass test.ping
  rc=$?
  set -e
  rm -f "$TMP_ROSTER"
  [ $rc -eq 0 ] || fail "Remote ping failed (OS=$OSMAJ, wrapper=$PICKED)"
  pass "Remote ping OK (OS=$OSMAJ, wrapper=$PICKED)"
fi

# Gate 7
if [ -x "$ROOT/modules/06-check-vendors.sh" ]; then
  banner "Gate 7: Vendors check"
if [ -d "$ROOT/vendor/el7/salt" ] && [ ! -f "$ROOT/vendor/thin/salt-thin.tgz" ]; then
  echo "[THIN WARN] el7 vendor detected but no vendor/thin/salt-thin.tgz. Run modules/05-build-thin-el7.sh before packaging for EL7."
fi
  "$ROOT/modules/06-check-vendors.sh" || fail "vendors check failed"
  pass "Vendors OK"
if [ -d "/sto/salt-shaker/vendor/el7/salt" ] && [ ! -f "/sto/salt-shaker/vendor/thin/salt-thin.tgz" ]; then
  echo "[THIN WARN] el7 vendor detected but no vendor/thin/salt-thin.tgz. Run modules/05-build-thin-el7.sh before packaging for EL7."
fi
fi

# Gate 8
if [ -n "$DO_PACKAGE" ]; then
  banner "Gate 8: Packaging → prefix=${PKG_PREFIX:-/sto/salt-shaker} vendors=${PKG_VENDOR:-none}"
  [ -n "$PKG_PREFIX" ] || PKG_PREFIX="/sto/salt-shaker"
  [ -n "$PKG_VENDOR" ] || PKG_VENDOR="none"
  "$ROOT/modules/10-create-project-rpm.sh" --prefix "$PKG_PREFIX" --vendor "$PKG_VENDOR" || fail "Packaging failed"
  TFILE="$(ls -1t "$ROOT"/offline/salt-shaker-*-full.tar.gz 2>/dev/null | head -n1 || true)"
  RPMFILE="$(ls -1t "$ROOT"/offline/*.rpm 2>/dev/null | head -n1 || true)"
  [ -n "$TFILE" ] || fail "Tarball not found"
  pass "Packaging OK: $TFILE"
  [ -n "$RPMFILE" ] && { echo "rpm -qlp (first 60): $RPMFILE"; rpm -qlp "$RPMFILE" | head -n 60 || true; }
  [ $ARTIFACT_LIST -eq 1 ] && { echo "Tar contents (first 60):"; tar -tzf "$TFILE" | head -n 60; }
fi

echo
echo "✅ ALL GATES PASSED."
[ -n "${HOST:-}" ] && echo "Remote verified: $HOST"

# GATE 8: Packaging helper (confined in-project)
GATE8() {
  echo
  echo "════════ Gate 8: Packaging → prefix=${SALT_SHAKER_PREFIX:-$PWD} vendors=${VENDOR_LIST:-el8} ════════"
  export SALT_SHAKER_ROOT="${SALT_SHAKER_ROOT:-$PWD}"
  export SALT_SHAKER_PREFIX="${SALT_SHAKER_PREFIX:-$SALT_SHAKER_ROOT}"
  export SALT_SHAKER_DISTTAG="${SALT_SHAKER_DISTTAG:-el8}"
  export TMPDIR="$SALT_SHAKER_ROOT/tmp"

  # module 10 now performs staging, tarball, SPEC, and rpmbuild all in $ROOT
  if "$SALT_SHAKER_ROOT/modules/10-create-project-rpm.sh"; then
    echo "✔ Packaging OK: $SALT_SHAKER_ROOT/offline/${PROJECT_NAME:-salt-shaker}-${SALT_SHAKER_VERSION:-3.12}-full.tar.gz"
    # Previews
    local rpm="$(ls -1t "$SALT_SHAKER_ROOT"/offline/*.rpm 2>/dev/null | head -1)"
    if [[ -n "${rpm:-}" ]]; then
      echo "rpm -qlp (first 60): $rpm"
      rpm -qlp "$rpm" | head -60
    fi
    local tar="$(ls -1t "$SALT_SHAKER_ROOT"/offline/*-full.tar.gz 2>/dev/null | head -1)"
    if [[ -n "${tar:-}" ]]; then
      echo "Tar contents (first 60):"
      tar -tzf "$tar" | head -60
    fi
  else
    echo "✖ Packaging failed"
    exit 1
  fi
}
