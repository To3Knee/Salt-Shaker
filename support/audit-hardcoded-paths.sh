#!/bin/bash
# Audit for hard-coded absolute project paths (EL7-safe)
set -euo pipefail
PRJ="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# What to search for
PATTERN='/srv/tmp/salt-shaker'

# Ignore list (regex): backups, archive/tmp/vendor/runtime/offline/logs/.git, the patcher, and this audit script
IGNORE_RE='(^|/)(\.git|archive|tmp|vendor|runtime|offline|logs)/|\.bak(\.|$)|~$|support/(patch-hardcoded-paths|audit-hardcoded-paths)\.sh$'

found=0
while IFS= read -r -d '' f; do
  # skip self explicitly
  [ "$f" = "$SELF" ] && continue
  rel="${f#$PRJ/}"
  # skip ignored
  printf '%s\n' "$rel" | grep -Eq "$IGNORE_RE" && continue
  if grep -q -- "$PATTERN" "$f"; then
    echo "⚠ Hard-coded path in: $f"
    grep -n -- "$PATTERN" "$f"
    echo
    found=$((found+1))
  fi
done < <(find "$PRJ" -type f -print0)

if [ "$found" -gt 0 ]; then
  echo "✖ Found $found file(s) with hard-coded absolute project paths"
  exit 1
else
  echo "✓ No hard-coded absolute project paths found"
fi
