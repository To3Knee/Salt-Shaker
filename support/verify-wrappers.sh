#!/bin/bash
#===============================================================
#Script Name: verify-wrappers.sh
#Date: 10/03/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.1
#Short: Verify env/ vs bin/ vs runtime/bin/ wrappers, honoring ignore list
#About: Skips names in env/.wrapper-ignore and --ignore "name1,name2".
#       Fails if any remaining wrapper differs or is missing. EL7-safe.
#===============================================================
set -euo pipefail
LC_ALL=C

ROOT="${SALT_SHAKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
ENV_DIR="$ROOT/env"
BIN_DIR="$ROOT/bin"
RT_BIN_DIR="$ROOT/runtime/bin"
IGNORE_FILE="$ENV_DIR/.wrapper-ignore"
EXTRA_IGNORE=""

usage(){ cat <<'HLP'
Usage: support/verify-wrappers.sh [--ignore "name1,name2,..."]
HLP
}
while [ $# -gt 0 ]; do
  case "$1" in -h|--help) usage; exit 0;;
    --ignore) EXTRA_IGNORE="${2:-}"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

IGN_SET="install-env-wrappers.sh *.bak *.orig"
[ -f "$IGNORE_FILE" ] && while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$line" ] || IGN_SET="$IGN_SET $line"
done < "$IGNORE_FILE"
if [ -n "$EXTRA_IGNORE" ]; then
  IFS=',' read -r -a extra <<< "$EXTRA_IGNORE"
  for n in "${extra[@]}"; do n="$(echo "$n" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"; [ -z "$n" ] || IGN_SET="$IGN_SET $n"; done
fi

should_skip(){ local f="$1" pat; for pat in $IGN_SET; do case "$f" in $pat) return 0;; esac; done; return 1; }

err=0
hdr(){ printf '\n%-22s | %-8s | %-64s | %s\n' "FILE" "WHERE" "SHA256" "SIZE"; }
row(){ printf '%-22s | %-8s | %-64s | %s\n' "$1" "$2" "$3" "$4"; }
sha(){ sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
sz(){ stat -c '%s' "$1" 2>/dev/null || wc -c <"$1" 2>/dev/null || echo 0; }

WRAPS=""
while IFS= read -r -d '' f; do b="$(basename "$f")"; should_skip "$b" && continue; WRAPS="$WRAPS $b"; done \
  < <(find "$ENV_DIR" -maxdepth 1 -type f -perm -111 -print0)

[ -n "$WRAPS" ] || { echo "No executable wrappers in $ENV_DIR (after ignore)"; exit 0; }

hdr
for w in $WRAPS; do
  e="$ENV_DIR/$w"; b="$BIN_DIR/$w"; r="$RT_BIN_DIR/$w"
  esha="$(sha "$e")"; esz="$(sz "$e")"
  if [ -f "$b" ]; then bsha="$(sha "$b")"; bsz="$(sz "$b")"; else bsha="(missing)"; bsz="-"; err=1; fi
  if [ -f "$r" ]; then rsha="$(sha "$r")"; rsz="$(sz "$r")"; else rsha="(missing)"; rsz="-"; err=1; fi
  row "$w" "env" "$esha" "$esz"; row "$w" "bin" "$bsha" "$bsz"; row "$w" "runtime" "$rsha" "$rsz"
  if [ -f "$b" ] && [ -f "$r" ]; then
    [ "$esha" = "$bsha" ] && [ "$esha" = "$rsha" ] || { echo "DIFF: $w differs"; err=1; }
  fi
done

echo
[ $err -eq 0 ] && echo "✔ Wrappers match across env/ bin/ runtime/bin/ (ignoring patterns)" || { echo "✖ Wrapper mismatch detected. Reinstall: env/install-env-wrappers.sh"; exit 2; }
