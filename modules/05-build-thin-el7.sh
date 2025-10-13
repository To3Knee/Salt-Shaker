#!/usr/bin/env bash
#===============================================================
#Script Name: 05-build-thin-el7.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Build salt-thin for EL7
#About: Assembles salt-thin from offline RPMs/tarballs (with six fallback).
#===============================================================
# Script Name: 05-build-thin-el7.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Build thin (EL7)
# About: Wrapper that delegates to xx-rebuild-thin-el7-min.sh to (re)create
#        vendor/thin/salt-thin.tgz from offline EL7 RPM payloads, with sanity checks.
set -euo pipefail
exec "$(dirname "$0")/xx-rebuild-thin-el7-min.sh" "$@"
