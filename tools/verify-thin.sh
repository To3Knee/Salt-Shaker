#!/usr/bin/env bash
#===============================================================
# Script Name: verify-thin.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Helpers to validate thin tarballs
# About: Provides has_top_salt() and thin_entries() used by modules.
#===============================================================
set -euo pipefail

export LC_ALL=C LANG=C

# has_top_salt <tar.gz>
# Returns 0 when the tarball contains top-level salt/ (or ./salt/)
has_top_salt() {
  local t="$1"
  [[ -f "$t" ]] || return 1
  # Be tolerant of leading ./ and of GNU/bsdtar variants
  if tar -tzf "$t" 2>/dev/null | awk -F/ '
      NR==1 { first=$1; second=$2 }
      END {
        if (first=="salt")               exit 0;
        if (first=="." && second=="salt") exit 0;
        exit 1;
      }'
  then
    return 0
  fi
  return 1
}

# thin_entries <tar.gz>
# Prints total entry count (numeric), 0 on error.
thin_entries() {
  local t="$1"
  tar -tzf "$t" 2>/dev/null | wc -l | awk '{print $1+0}'
}
