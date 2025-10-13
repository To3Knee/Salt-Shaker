#!/bin/bash
#===============================================================
#Script Name: test-wrappers.sh
#Date: 10/02/2025
#Created By: Salt-Shaker
#Version: 2.2
#Short: Wrapper smoke test (runtime-first + thin check, robust)
#About: Validates syntax, --print-env, runtime CONF_DIR, roster passthrough,
#About: and EL7 thin contents. Tolerates BOM/CR and non-anchored tar listings.
#===============================================================
set -euo pipefail

OK="✓"; WARN="⚠"; ERR="✖"
cok=$([ -t 1 ] && echo $'\033[1;32m' || true)
cwa=$([ -t 1 ] && echo $'\033[1;33m' || true)
cer=$([ -t 1 ] && echo $'\033[1;31m' || true)
c0=$([ -t 1 ] && echo $'\033[0m' || true)
ok(){   printf "%b%s %s%b\n" "$cok"  "$OK"  "$*" "$c0"; }
warn(){ printf "%b%s %s%b\n" "$cwa"  "$WARN" "$*" "$c0" >&2; }
err(){  printf "%b%s %s%b\n" "$cer"  "$ERR" "$*" "$c0" >&2; }

resolve_abs(){ p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || echo "$p"; else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" ); fi; }
detect_root(){
  d="$(dirname -- "$(resolve_abs "$0")")"; i=6
  while [ "$i" -gt 0 ]; do
    [ -d "$d/modules" ] || [ -d "$d/vendor" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ] && { echo "$d"; return; }
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  pwd
}
ROOT="${SALT_SHAKER_ROOT:-$(detect_root)}"
BIN="$ROOT/bin"

echo "SALT SHAKER | Wrapper Smoke Test"
ok "Project Root: $ROOT"

syntax_ok(){ bash -n "$1" 2>/dev/null; }
print_env(){ "$1" --print-env 2>/dev/null || true; }
ver_ok(){ "$1" --version >/dev/null 2>&1; }

check_conf_runtime(){
  local envdump="$1" name="$2" want="$ROOT/runtime/conf" got
  got="$(printf "%s" "$envdump" | awk -F= '/^CONF_DIR=/{print $2; exit}')"
  if [ "$got" = "$want" ]; then ok "$name: CONF_DIR → runtime OK"; else warn "$name: CONF_DIR not runtime-first (${got:-})"; fi
}

check_roster_passthrough(){
  local envdump="$1" name="$2" pass
  pass="$(printf "%s" "$envdump" | awk -F= '/^PASS_ROSTER=/{print $2; exit}')"
  if [ "$pass" = "yes" ]; then ok "$name: PASS_ROSTER=yes"; else warn "$name: PASS_ROSTER not 'yes' (${pass:-})"; fi
}

# More tolerant thin check:
# - strips leading './'
# - strips CRs
# - drops blank lines
# - matches any entry that STARTS WITH 'salt' (salt/, salt/__init__.py, salt/cloud, …)
check_thin_has_salt(){
  local envdump="$1" name="$2" arch tmplist
  arch="$(printf "%s" "$envdump" | awk -F= '/^SALT_THIN_ARCHIVE=/{print $2; exit}')"
  if [ -z "${arch:-}" ]; then warn "$name: SALT_THIN_ARCHIVE not set"; return 1; fi
  if [ ! -s "$arch" ]; then err "$name: thin archive not found: $arch"; return 1; fi
  ok "$name: SALT_THIN_ARCHIVE=$arch"

  tmplist="$(mktemp "${TMPDIR:-/tmp}/thinlist.XXXXXX")"
  if ! tar -tzf "$arch" 2>/dev/null \
      | sed 's#^\./##' \
      | tr -d '\r' \
      | awk 'NF {print}' > "$tmplist"; then
    err "$name: unable to list archive"
    rm -f "$tmplist"
    return 1
  fi

  if grep -a -m1 -E '^salt([/]|$)' "$tmplist" >/dev/null 2>&1; then
    ok "$name: thin contains salt/"
    rm -f "$tmplist"
    return 0
  fi

  err "$name: thin missing salt/"
  echo "----- first 60 archive entries ($arch) -----"
  head -60 "$tmplist" || true
  echo "-------------------------------------------"
  rm -f "$tmplist"
  return 1
}

check_wrapper(){
  local name="$1" path="$BIN/$1" fail=0
  [ -x "$path" ] || { warn "$name: not found in bin/"; return 1; }
  syntax_ok "$path" && ok "$name: syntax OK" || { err "$name: syntax error"; return 1; }
  local dump; dump="$(print_env "$path")" || true
  [ -n "$dump" ] && ok "$name: --print-env OK" || warn "$name: --print-env missing vars"
  check_conf_runtime "$dump" "$name"
  case "$name" in salt-ssh-*) check_roster_passthrough "$dump" "$name";; esac
  ver_ok "$path" && ok "$name: --version OK" || warn "$name: --version failed (non-fatal)"
  if [ "$name" = "salt-ssh-el7" ]; then check_thin_has_salt "$dump" "$name" || fail=1; fi
  return $fail
}

overall=0
check_wrapper salt-ssh-el7 || overall=1
check_wrapper salt-ssh-el8 || overall=1
check_wrapper salt-call-el8 || overall=1

if [ $overall -eq 0 ]; then ok "All wrapper checks passed"; exit 0; else err "One or more wrapper checks failed"; exit 1; fi
