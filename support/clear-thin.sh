#!/bin/bash
#===============================================================
#Script Name: clear-thin.sh
#Date: 10/03/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Safely purge Salt thin caches
#About: Interactively removes common salt-thin cache paths to resolve checksum/
# permission issues. EL7-safe. Prompts before deletion.
#===============================================================

set -euo pipefail
LC_ALL=C

paths=(
  "/tmp/salt-thin-$USER"
  "/tmp/salt-thin-*"
  "$HOME/.cache/salt/py*"
  "/var/tmp/salt/*"
  "/tmp/.salt*"
)

echo "Salt thin cache cleanup (dry-run preview):"
for p in "${paths[@]}"; do
  matches=$(ls -d $p 2>/dev/null || true)
  [ -n "$matches" ] && echo "$matches"
done

read -r -p "Proceed to delete the above paths? [y/N]: " ans
case "${ans:-n}" in y|Y) : ;; *) echo "Aborted."; exit 0;; esac

# Delete safely
for p in "${paths[@]}"; do
  rm -rf $p 2>/dev/null || true
done

echo "Done. Thin caches purged."
