#!/usr/bin/env bash
#===============================================================
#Script Name: xx-rebuild-thin-el7-min.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Minimal EL7 thin builder
#About: Robust extractor used by module 05; handles deps + six fallback.
#===============================================================
#!/usr/bin/env bash
#Script Name: xx-rebuild-thin-el7-min.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Minimal EL7 salt-thin builder (offline)
#About: Robust extractor/packager used by Module 05. Handles
#       staging of salt/ plus deps and six.py from offline tarballs.
# Script Name: xx-rebuild-thin-el7-min.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.3
# Short: Build-thin-el7 (quiet, robust mini builder)
# About: Rebuilds vendor/thin/salt-thin.tgz from EL7 RPM payloads.
#        - Overwrites on extract to avoid "newer or same age" noise
#        - Locates 'salt/' under py2.7 or (fallback) py3.6 site-packages
#        - Stages optional libs from multiple candidate roots
#        - Verifies tarball has top-level 'salt/' and prints pro status
set -euo pipefail

bold=$'\e[1m'; reset=$'\e[0m'
green=$'\e[32m'; yellow=$'\e[33m'; red=$'\e[31m'; cyan=$'\e[36m'

say()   { printf "%s\n" "$*"; }
info()  { printf "%s%s%s\n" "$cyan" "$*" "$reset"; }
ok()    { printf "%s✓%s %s\n" "$green" "$reset" "$*"; }
warn()  { printf "%s⚠%s %s\n" "$yellow" "$reset" "$*" >&2; }
fail()  { printf "%s✖%s %s\n" "$red" "$reset" "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OFF="$ROOT/offline/salt/thin/el7"
OUT_DIR="$ROOT/vendor/thin"
OUT="$OUT_DIR/salt-thin.tgz"

STAGE="$(mktemp -d "$ROOT/tmp/thin.el7.stage.XXXXXX")"
EXTRACT="$(mktemp -d "$ROOT/tmp/thin.el7.extract.XXXXXX")"
trap 'rm -rf "$STAGE" "$EXTRACT"' EXIT
mkdir -p "$OUT_DIR" "$ROOT/tmp" >/dev/null 2>&1 || true

banner() {
  say "══════════════════════════════════════════════════════════════════════════"
  say "📦 ${bold}MODULE OUTPUT: build-thin-el7${reset}"
  say "══════════════════════════════════════════════════════════════════════════"
}
banner

need_mb=333
have_mb=$(df -m "$ROOT" | awk 'NR==2{print $4}')
(( have_mb >= need_mb )) || fail "Not enough space: need ${need_mb}MB, have ${have_mb}MB"
ok "Space OK: need ${need_mb}MB, have ${have_mb}MB"

mapfile -t RPMS < <(ls -1 "$OFF"/*.rpm 2>/dev/null | sort)
(( ${#RPMS[@]} > 0 )) || fail "No RPMs found in $OFF"

say "✓ Using RPMs:"
for r in "${RPMS[@]}"; do say "  $r"; done

YES=false; FORCE=false; DEBUG=false
while (( $# )); do
  case "${1:-}" in
    -y|--yes) YES=true;;
    -f|--force) FORCE=true;;
    --debug) DEBUG=true;;
  esac; shift || true
done

if [[ -f "$OUT" && "$FORCE" != true ]]; then
  if [[ "$YES" == true ]]; then
    say "• Rebuilding existing thin (auto-yes)."
  else
    read -r -p "Thin exists at salt-thin.tgz. Rebuild now? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || { ok "Skipped (existing thin retained)"; exit 0; }
  fi
fi

extract_one() {
  local rpm="$1"
  info "• Extracting $(basename "$rpm") ..."
  set +e
  rpm2cpio "$rpm" 2>/dev/null | (cd "$EXTRACT" && cpio -idmu --quiet)
  local rc=$?
  set -e
  (( rc == 0 )) || fail "rpm2cpio/cpio failed on $(basename "$rpm") (rc=$rc)"
}
for rpm in "${RPMS[@]}"; do extract_one "$rpm"; done
ok "Extracted RPM payloads"

# locate salt package root
pkg_root=""
if [[ -d "$EXTRACT/usr/lib/python2.7/site-packages/salt" ]]; then
  pkg_root="$EXTRACT/usr/lib/python2.7/site-packages"
elif [[ -d "$EXTRACT/usr/lib64/python2.7/site-packages/salt" ]]; then
  pkg_root="$EXTRACT/usr/lib64/python2.7/site-packages"
elif [[ -d "$EXTRACT/usr/lib/python3.6/site-packages/salt" ]]; then
  pkg_root="$EXTRACT/usr/lib/python3.6/site-packages"
else
  found="$(find "$EXTRACT" -type d -path '*/site-packages/salt' | head -n1 || true)"
  [[ -n "$found" ]] && pkg_root="${found%/salt}"
fi
[[ -n "$pkg_root" ]] || fail "Could not locate site-packages/salt in RPM payload."

salt_dir="$pkg_root/salt"
[[ -d "$salt_dir" ]] || fail "salt/ not found under $pkg_root"

# candidate roots (fixed: no 'read -d ""' anymore)
CANDIDATE_ROOTS=("$pkg_root")
for rel in usr/lib/python2.7/site-packages usr/lib64/python2.7/site-packages usr/lib/python3.6/site-packages; do
  abs="$EXTRACT/$rel"
  [[ -d "$abs" && "$abs" != "$pkg_root" ]] && CANDIDATE_ROOTS+=("$abs")
done

# stage salt
mkdir -p "$STAGE"
cp -a "$salt_dir" "$STAGE/salt"
ok "salt/ staged"

# helpers
stage_opt_dir(){
  local sub="$1"
  for root in "${CANDIDATE_ROOTS[@]}"; do
    if [[ -d "$root/$sub" ]]; then
      cp -a "$root/$sub" "$STAGE/$sub"
      ok "$sub staged"
      return 0
    fi
  done
  say "• $(basename "$sub") not found (optional)"
}
stage_opt_file(){
  local sub="$1" dst="$2"
  for root in "${CANDIDATE_ROOTS[@]}"; do
    if [[ -f "$root/$sub" ]]; then
      install -m0644 "$root/$sub" "$STAGE/$dst"
      ok "$dst staged"
      return 0
    fi
  done
  say "• $dst not found (optional)"
}

# optionals
stage_opt_dir "yaml"
stage_opt_dir "msgpack"
stage_opt_dir "tornado"
stage_opt_dir "jinja2"
stage_opt_dir "markupsafe"
stage_opt_dir "enum"
if ! stage_opt_file "six.py" "six.py"; then
  if [[ -f "$salt_dir/ext/six.py" ]]; then
    install -m0644 "$salt_dir/ext/six.py" "$STAGE/six.py"
    ok "six.py staged (from salt/ext/)"
  fi
fi

# ---------------------------------------------------------------
# FINALIZER: stage six.py from offline tarballs if still missing
# ---------------------------------------------------------------
if [[ ! -f "$STAGE/six.py" ]]; then
  OFF_TRY=()
  [[ -n "${OFF:-}" ]] && OFF_TRY+=("$OFF")
  [[ -n "${ROOT:-}" ]] && OFF_TRY+=("$ROOT/offline/salt/thin/el7" "$ROOT/offline/salt/thin" "$ROOT/offline")
  OFF_TRY+=("/sto/salt-shaker/offline/salt/thin/el7" "/sto/salt-shaker/offline")
  for d in "${OFF_TRY[@]}"; do
    [[ -d "$d" ]] || continue
    for tgz in "$d"/python2-six-*.tar.gz "$d"/six-*.tar.gz; do
      [[ -f "$tgz" ]] || continue
      tmp="$(mktemp -d)"
      if tar -xzf "$tgz" -C "$tmp" 2>/dev/null; then
        sixp="$(find "$tmp" -maxdepth 4 -type f -name six.py | head -n1)"
        if [[ -n "$sixp" ]]; then
          install -m0644 "$sixp" "$STAGE/six.py"
          echo "✓ six.py staged (from $(basename "$tgz"))"
          rm -rf "$tmp"
          break 2
        fi
      fi
      rm -rf "$tmp"
    done
  done
  [[ -f "$STAGE/six.py" ]] || echo "• six.py not found (optional) [finalizer]"
fi
# ---------------------------------------------------------------
say "• Pruning bytecode/docs/tests ..."
find "$STAGE" -type f \( -name '*.pyc' -o -name '*.pyo' -o -name '*.so.debug' \) -delete || true
rm -rf "$STAGE/salt/tests" "$STAGE/salt/daemons/test" 2>/dev/null || true
ok "Prune complete"

tmpout="$(mktemp "$ROOT/tmp/salt-thin.XXXXXX.tgz")"
( cd "$STAGE" && tar -czf "$tmpout" salt )

first="$(tar -tzf "$tmpout" | head -n1 || true)"
case "$first" in
  salt/*|./salt/*)
    mkdir -p "$OUT_DIR"
    mv -f "$tmpout" "$OUT"
    ok "Thin archived → $OUT"
    entries=$(tar -tzf "$OUT" | awk '/^(|\.\/)salt\//{c++} END{print c+0}')
    say "Thin contents: salt/ entries = ${entries}"
    ;;
  *)
    say "First few entries (debug):"
    tar -tzf "$tmpout" | sed -n '1,40p'
    rm -f "$tmpout"
    fail "Built archive lacks top-level salt/"
    ;;
esac

exit 0
# ---------------------------------------------------------------
# FINALIZER: stage six.py from offline tarballs if still missing
# ---------------------------------------------------------------
if [[ ! -f "$STAGE/six.py" ]]; then
  OFF_TRY=()
  [[ -n "${OFF:-}" ]] && OFF_TRY+=("$OFF")
  [[ -n "${ROOT:-}" ]] && OFF_TRY+=("$ROOT/offline/salt/thin/el7" "$ROOT/offline/salt/thin" "$ROOT/offline")
  # harden with common absolute paths too
  OFF_TRY+=("/sto/salt-shaker/offline/salt/thin/el7" "/sto/salt-shaker/offline")

  for d in "${OFF_TRY[@]}"; do
    [[ -d "$d" ]] || continue
    for tgz in "$d"/python2-six-*.tar.gz "$d"/six-*.tar.gz; do
      [[ -f "$tgz" ]] || continue
      tmp="$(mktemp -d)"
      if tar -xzf "$tgz" -C "$tmp"; then
        sixp="$(find "$tmp" -maxdepth 4 -type f -name six.py | head -n1)"
        if [[ -n "$sixp" ]]; then
          install -m0644 "$sixp" "$STAGE/six.py"
          echo "✓ six.py staged (from $(basename "$tgz"))"
          rm -rf "$tmp"
          break 2
        fi
      fi
      rm -rf "$tmp"
    done
  done

  [[ -f "$STAGE/six.py" ]] || echo "• six.py not found (optional) [finalizer]"
fi
# ---------------------------------------------------------------
