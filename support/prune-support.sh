#!/bin/bash
#===============================================================
#Script Name: prune-support.sh
#Date: 10/03/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Interactively disable unused/broken support scripts
#About: Moves selected support/*.sh to support/.disabled/<ts>/ (safe revert).
# Also supports --list and --restore <file|all>. EL7-safe.
#===============================================================
set -euo pipefail
LC_ALL=C

ROOT="${SALT_SHAKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
SUP="$ROOT/support"
DIS="$SUP/.disabled/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIS"

usage(){ cat <<'HLP'
Usage: support/prune-support.sh [--list] [--restore <file|all>]
  No args → interactive disable picker.
HLP
}

list_files() {
  echo "Support scripts:"
  find "$SUP" -maxdepth 1 -type f -name '*.sh' -printf '  %f\n' | sort
  echo
  echo "Disabled scripts:"
  find "$SUP/.disabled" -type f -name '*.sh' -printf '  %P\n' 2>/dev/null | sort || true
}

restore_one() {
  local rel="$1"
  local src="$SUP/.disabled/$rel"
  local dst="$SUP/$(basename "$rel")"
  [ -f "$src" ] || { echo "Not found in disabled: $rel"; return 1; }
  mv "$src" "$dst"
  chmod 0755 "$dst" 2>/dev/null || true
  echo "Restored -> $dst"
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
  --list) list_files; exit 0;;
  --restore)
    rel="${2:-}"; [ -n "$rel" ] || { echo "Need a file path under .disabled or 'all'"; exit 2; }
    if [ "$rel" = "all" ]; then
      while IFS= read -r -d '' f; do
        r="${f#"$SUP/.disabled/"}"
        restore_one "$r" || true
      done < <(find "$SUP/.disabled" -type f -name '*.sh' -print0 2>/dev/null || true)
      exit 0
    else
      restore_one "$rel"; exit 0
    fi
    ;;
esac

# Interactive disable
echo "Select support scripts to disable (move to .disabled/)."
echo "Enter names separated by spaces, or 'none' to cancel."
echo
list_files
echo
read -r -p "Disable which scripts: " picks
[ -n "$picks" ] || { echo "No selection."; exit 0; }
[ "$picks" = "none" ] && { echo "Cancelled."; exit 0; }

mkdir -p "$DIS"
for b in $picks; do
  src="$SUP/$b"
  if [ ! -f "$src" ]; then
    echo "Skip (not found): $b"
    continue
  fi
  mv "$src" "$DIS/"
  echo "Disabled -> $DIS/$b"
done

echo "Done. You can restore with:"
echo "  support/prune-support.sh --restore all"
