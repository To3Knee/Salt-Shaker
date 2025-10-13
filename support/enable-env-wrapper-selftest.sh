#!/bin/bash
#===============================================================
#Script Name: enable-env-wrapper-selftest.sh
#Date: 10/02/2025
#Created By: Salt-Shaker
#Version: 1.0
#Short: Add env/test-wrappers.sh and patch installer to use it
#About: Writes env/test-wrappers.sh (EL7-safe) and updates
#About: env/install-env-wrappers.sh to prefer that script when
#About: --self-test is given. Creates a timestamped backup first.
#===============================================================
set -euo pipefail

# --- locate project root (portable) ---
resolve_abs(){ p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || echo "$p"; else (cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")"); fi; }
detect_root(){
  d="$(dirname -- "$(resolve_abs "$0")")"; i=6
  while [ "$i" -gt 0 ]; do
    [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ] || [ -d "$d/vendor" ] && { echo "$d"; return; }
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  pwd
}
ROOT="${SALT_SHAKER_ROOT:-$(detect_root)}"
ENV_DIR="$ROOT/env"
SUPPORT_DIR="$ROOT/support"
BIN_DIR="$ROOT/bin"

# --- UI helpers ---
ok(){   printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m⚠ %s\033[0m\n" "$*" >&2; }
err(){  printf "\033[1;31m✖ %s\033[0m\n" "$*" >&2; }

mkdir -p "$ENV_DIR" "$SUPPORT_DIR" "$ROOT/logs" >/dev/null 2>&1 || true

# 1) Write env/test-wrappers.sh
cat > "$ENV_DIR/test-wrappers.sh" <<'WRAPTEST'
#!/bin/bash
#===============================================================
#Script Name: test-wrappers.sh
#Date: 10/02/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Smoke test env/bin wrappers (syntax/env/runtime)
#About: EL7-safe checks: bash -n, --print-env parsing, runtime path
#About: validation, minimal --version run. No remote actions.
#===============================================================
set -euo pipefail

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
c(){ [ -t 1 ] || { printf "%s" ""; return; }; case "$1" in ok) printf "\033[1;32m";; warn) printf "\033[1;33m";; err) printf "\033[1;31m";; head) printf "\033[0;36m";; reset) printf "\033[0m";; esac; }
ok(){   printf "%b✓ %s%b\n" "$(c ok)"   "$*" "$(c reset)"; }
warn(){ printf "%b⚠ %s%b\n" "$(c warn)" "$*" "$(c reset)"; }
err(){  printf "%b✖ %s%b\n" "$(c err)"  "$*" "$(c reset)"; }
resolve_abs(){ p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || echo "$p"; else (cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")"); fi; }
detect_root(){
  d="$(dirname -- "$(resolve_abs "$0")")"; i=6
  while [ "$i" -gt 0 ]; do
    [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ] || [ -d "$d/vendor" ] && { echo "$d"; return; }
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  pwd
}

ROOT="${SALT_SHAKER_ROOT:-$(detect_root)}"
BIN="$ROOT/bin"
ENV="$ROOT/env"
printf "%bSALT SHAKER | Wrapper Smoke Test%b\n" "$(c head)" "$(c reset)"
ok "Project Root: $ROOT"

wrappers="salt-ssh-el7 salt-ssh-el8 salt-call-el8"
[ $# -gt 0 ] && wrappers="$*"

total=0; failed=0
for name in $wrappers; do
  total=$((total+1))
  src=""
  [ -x "$BIN/$name" ] && src="$BIN/$name" || [ -x "$ENV/$name" ] && src="$ENV/$name" || src=""
  if [ -z "$src" ]; then warn "$name: not found in bin/ or env/"; failed=$((failed+1)); continue; fi

  if bash -n "$src" 2>/dev/null; then ok "$name: syntax OK"; else err "$name: syntax ERR"; failed=$((failed+1)); continue; fi

  CONF_DIR=""; ROSTER_FILE=""; PASS_ROSTER=""
  if out="$("$src" --print-env 2>/dev/null || true)"; then
    printf "%s\n" "$out" | grep -E '^(CONF_DIR|ROSTER_FILE|PASS_ROSTER)=' >/dev/null 2>&1 && ok "$name: --print-env OK" || warn "$name: --print-env missing vars"
    CONF_DIR="$(printf "%s\n" "$out" | awk -F= '/^CONF_DIR=/{print $2}' | tail -n1)"
    ROSTER_FILE="$(printf "%s\n" "$out" | awk -F= '/^ROSTER_FILE=/{print $2}' | tail -n1)"
    PASS_ROSTER="$(printf "%s\n" "$out" | awk -F= '/^PASS_ROSTER=/{print $2}' | tail -n1)"
  else
    warn "$name: --print-env not supported"
  fi

  if [ -d "$ROOT/runtime/conf" ]; then
    [ "$CONF_DIR" = "$ROOT/runtime/conf" ] && ok "$name: CONF_DIR → runtime OK" || warn "$name: CONF_DIR not runtime-first ($CONF_DIR)"
  fi
  if printf "%s" "$name" | grep -q 'salt-ssh-'; then
    if [ -f "$ROOT/runtime/roster/roster.yaml" ]; then
      [ "$ROSTER_FILE" = "$ROOT/runtime/roster/roster.yaml" ] && ok "$name: ROSTER_FILE → runtime OK" || warn "$name: ROSTER_FILE not runtime-first ($ROSTER_FILE)"
    fi
    [ "${PASS_ROSTER:-}" = "yes" ] && ok "$name: PASS_ROSTER=yes" || warn "$name: PASS_ROSTER not 'yes' ($PASS_ROSTER)"
  fi

  if [ "$name" = "salt-ssh-el7" ]; then
    THIN="$ROOT/vendor/el7/thin/salt-thin.tgz"
    if [ -s "$THIN" ]; then
      if tar -tzf "$THIN" 2>/dev/null | sed 's#^\./##' | grep -q '^salt/'; then ok "$name: thin contains salt/"; else err "$name: thin missing salt/"; failed=$((failed+1)); fi
    else err "$name: thin archive missing ($THIN)"; failed=$((failed+1)); fi
  fi

  if "$src" --version >/dev/null 2>&1; then ok "$name: --version OK"; else warn "$name: --version failed (non-fatal)"; fi
done

[ $failed -eq 0 ] && { ok "All wrapper checks passed"; exit 0; } || { err "$failed/$total wrapper checks failed"; exit 1; }
WRAPTEST
chmod +x "$ENV_DIR/test-wrappers.sh"
ok "wrote: env/test-wrappers.sh"

# 2) Patch env/install-env-wrappers.sh to prefer env/test-wrappers.sh
INST="$ENV_DIR/install-env-wrappers.sh"
if [ ! -f "$INST" ]; then
  err "installer not found: $INST"
  exit 1
fi
cp -pf "$INST" "$INST.bak.$(date +%Y%m%d-%H%M%S)" || true

# Replace self_test() to search env/ first, then support/
awk '
  BEGIN{infunc=0}
  /^self_test\(\)\{/ {print; print "  local t=\"\""; print "  for cand in \"$ENV_DIR/test-wrappers.sh\" \"$PROJECT_ROOT/env/test-wrappers.sh\" \"$PROJECT_ROOT/support/test-wrappers.sh\"; do"; print "    if [ -x \"$cand\" ]; then t=\"$cand\"; break; fi"; print "  done"; print "  if [ -z \"$t\" ]; then"; print "    warn \"test-wrappers.sh not found in env/ or support/; skipping self-test\""; print "    return 0"; print "  fi"; print "  if [ $DRY_RUN -eq 1 ]; then"; print "    ok \"[DRY] would run: $t\""; print "    return 0"; print "  fi"; print "  echo"; print "  ok \"Running wrapper smoke test...\""; print "  if \"$t\"; then"; print "    ok \"Wrapper smoke test passed\""; print "  else"; print "    err \"Wrapper smoke test reported failures (see $MAIN_LOG)\""; print "    return 1"; print "  fi"; print "}"; infunc=1; next}
  { if(infunc==1){ if($0 ~ /^\}/){ infunc=0; next } else { next } } else { print } }
' "$INST" > "$INST.tmp" && mv "$INST.tmp" "$INST"

# sanity: make sure file still parses
if bash -n "$INST" 2>/dev/null; then
  ok "patched: env/install-env-wrappers.sh (self-test uses env/test-wrappers.sh)"
else
  err "syntax error after patch, restoring backup"
  cp -pf "$(ls -1t "$INST".bak.* | head -n1)" "$INST"
  exit 1
fi

ok "All done. Use: env/install-env-wrappers.sh --self-test"
