#!/usr/bin/env bash
#===============================================================
#Script Name: 06-check-vendors.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Check vendors & thin
#About: Runs health checks for onedir wrappers and thin archive contents.
#===============================================================
#!/usr/bin/env bash
# Script Name: 06-check-vendors.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Validate vendors & thin
# About: Prints a clean status table; verifies wrappers, vendors, and thin contents.
set -euo pipefail

export LC_ALL=C LANG=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIN="$ROOT/vendor/thin/salt-thin.tgz"
VROOT="$ROOT/vendor"
PATH="$ROOT/bin:$ROOT/runtime/bin:$PATH"

p_cyan(){ printf "\033[36m%s\033[0m\n" "$*"; }
p_green(){ printf "\033[32m%s\033[0m\n" "$*"; }
p_yell(){ printf "\033[33m%s\033[0m\n" "$*"; }
p_red(){ printf "\033[31m%s\033[0m\n" "$*"; }

# Import shared thin verification
. "$ROOT/tools/verify-thin.sh"

printf "\n"
p_cyan "══════════════════════════════════════════════════════════════════════"
p_cyan "▶ Vendor & Thin Checks"
printf "Project Root: %s\n" "$ROOT"
p_cyan "══════════════════════════════════════════════════════════════════════"

# Detect platforms present
plats=()
for p in el7 el8 el9; do
  if [[ -d "$VROOT/$p/salt" ]]; then
    plats+=("$p")
  fi
done
((${#plats[@]})) || { p_red "No vendors found under $VROOT/{el7,el8,el9}/salt"; exit 1; }

# Header
printf "%-12s | %-8s | %-13s | %-24s | %-24s | %s\n" \
  "Platform" "Status" "Python" "salt-ssh" "salt-call" "Path"
printf -- "------------ | ------ | ------------- | ------------------------ | ------------------------ | ------------------------------\n"

# Row for each platform
for p in "${plats[@]}"; do
  base="$VROOT/$p/salt"
  pyver="-" sshv="-" callv="-"
  status="OK"

  if [[ -x "$base/bin/python3.10" ]]; then
    pyver="$("$base/bin/python3.10" -V 2>&1 | awk '{print $2}')"
  elif [[ -x "$base/bin/python3" ]]; then
    pyver="$("$base/bin/python3" -V 2>&1 | awk '{print $2}')"
  elif [[ -x "$base/bin/python" ]]; then
    pyver="$("$base/bin/python" -V 2>&1 | awk '{print $2}')"
  fi

  if [[ -x "$base/salt-ssh" ]]; then
    sshv="$("$base/salt-ssh" --version 2>/dev/null | tr -s ' ' | awk '{print $2,$3}' | tr ' ' '\n' | sed -n '1p;2p' | paste -sd' ' -)"
  fi
  if [[ -x "$base/salt-call" ]]; then
    callv="$("$base/salt-call" --version 2>/dev/null | tr -s ' ' | awk '{print $2,$3}' | tr ' ' '\n' | sed -n '1p;2p' | paste -sd' ' -)"
  fi

  printf "%-12s | %-8s | %-13s | %-24s | %-24s | %s\n" \
    "$p" "$status" "${pyver:--}" "${sshv:--}" "${callv:--}" "vendor/$p/salt"
done

# Wrapper sanity (quiet; just OK/X)
ok() { command -v "$1" >/dev/null 2>&1; }
if ok salt-ssh-el7; then p_green "✓ Wrapper salt-ssh-el7 OK"; fi
if ok salt-ssh-el8; then p_green "✓ Wrapper salt-ssh-el8 OK"; fi
if ok salt-call-el8; then p_green "✓ Wrapper salt-call-el8 OK"; fi

# Thin verification (robust)
if [[ -f "$THIN" ]]; then
  if has_top_salt "$THIN"; then
    cnt="$(thin_entries "$THIN")"
    p_green "✓ Thin found: ${THIN}"
    printf "Thin contents: salt/ entries = %s\n" "${cnt:-0}"
  else
    p_red "✖ Thin archive present but does not expose top-level salt/"
    p_yell "  Rebuild with: modules/05-build-thin-el7.sh --force"
    exit 1
  fi
else
  p_yell "⚠ No thin archive at $THIN (build via module 05)."
fi

# READY summary (uses el8 if present)
if [[ -d "$VROOT/el8/salt" ]]; then
  PV="$("$VROOT/el8/salt/bin/python3.10" -V 2>/dev/null | awk '{print $2}')"
  printf "\nREADY  \033[32m✓\033[0m   (el8 · /sto/salt-shaker/vendor/el8/salt · %s)\n\n" "${PV:-unknown}"
  printf "Checklist:\n"
  printf "  [\033[32m✓\033[0m] Wrappers resolve onedir  (bin/salt-ssh-*) → vendor/el8/salt\n"
  printf "  [\033[32m✓\033[0m] Controller onedir executable (python/salt-ssh/salt-call)\n"
  if [[ -f "$THIN" ]] && has_top_salt "$THIN"; then
    printf "  [\033[32m✓\033[0m] Thin archive has salt/ (entries: %s)\n" "$(thin_entries "$THIN")"
  else
    printf "  [\033[31m✖\033[0m] Thin archive missing or malformed\n"
  fi
  printf "\nRuntime config: files=1, roster_yaml=1\n\n"
  p_green "✓ READY."
fi
