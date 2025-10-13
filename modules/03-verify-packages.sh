#!/usr/bin/env bash
#===============================================================
#Script Name: 03-verify-packages.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Verify offline packages
#About: Validates presence/sha/versions of all offline artifacts.
#===============================================================
#!/bin/bash
# Script Name: 03-verify-packages.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Verify offline assets
# About: Verifies presence/sha/size for offline tarballs and RPMs.
#!/bin/bash
set -euo pipefail

# ----- Colors (TTY-aware) -----
if [ -t 1 ]; then
  G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'
else
  G=""; Y=""; R=""; C=""; W=""; N=""
fi
ok(){ printf "${G}✓ %s${N}\n" "$*"; }
warn(){ printf "${Y}⚠ %s${N}\n" "$*"; }
err(){ printf "${R}✖ %s${N}\n" "$*"; }
info(){ printf "${C}%s${N}\n" "$*"; }
bar(){ printf "${C}══════════════════════════════════════════════════════════════════════${N}\n"; }

# ----- Resolve PROJECT_ROOT -----
RESOLVE(){ # EL7-safe absolute path
  local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  fi
}
FINDROOT(){
  local d="$1" i=8
  while [ "$i" -gt 0 ] && [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/modules" ] || [ -d "$d/vendor" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then
      echo "$d"; return 0
    fi
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  return 1
}
SCRIPT_ABS="$(RESOLVE "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_ABS")"
PROJECT_ROOT="${SALT_SHAKER_ROOT:-}"
[ -z "${PROJECT_ROOT}" ] && PROJECT_ROOT="$(FINDROOT "$SCRIPT_DIR" || true)"
[ -z "${PROJECT_ROOT}" ] && PROJECT_ROOT="$(FINDROOT "$(pwd)" || true)"
[ -z "${PROJECT_ROOT}" ] && PROJECT_ROOT="$(pwd)"

# ----- Dirs & Logs -----
OFFLINE_DIR="${PROJECT_ROOT}/offline"
SALT_DIR="${OFFLINE_DIR}/salt"
EL7_DIR="${SALT_DIR}/el7"
EL8_DIR="${SALT_DIR}/el8"
EL9_DIR="${SALT_DIR}/el9"
TB_DIR="${SALT_DIR}/tarballs"
THIN_EL7_DIR="${SALT_DIR}/thin/el7"

LOG_DIR="${PROJECT_ROOT}/logs"; mkdir -p "$LOG_DIR" 2>/dev/null || true
MAIN_LOG="${LOG_DIR}/salt-shaker.log"
ERR_LOG="${LOG_DIR}/salt-shaker-errors.log"
log(){ printf "%s %s\n" "$(date '+%F %T')" "$*" >>"$MAIN_LOG" 2>/dev/null || true; }

# ----- CLI -----
PLAT="all"; SUMMARY=0; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--platform) shift; PLAT="${1:-all}";;
    --summary) SUMMARY=1;;
    --strict) STRICT=1;;
    -h|--help)
      cat <<EOF
${W}Usage:${N} ${0##*/} [-p el7|el8|el9|all] [--summary] [--strict]
Verifies controller RPMs/tarballs (EL7/EL8/EL9) and EL7 thin core.

Examples:
  ${0##*/} --summary
  ${0##*/} -p el7
  ${0##*/} -p all --strict
EOF
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      exit 2
      ;;
  esac
  shift
done
case "$PLAT" in all|el7|el8|el9) :;; *) err "Invalid platform: $PLAT"; exit 2;; esac

# ----- Artifact lists -----
# Controller RPMs
EL7_RPMS="salt-3006.15-0.x86_64.rpm salt-ssh-3006.15-0.x86_64.rpm salt-cloud-3006.15-0.x86_64.rpm"
EL8_RPMS="salt-3007.8-0.x86_64.rpm  salt-ssh-3007.8-0.x86_64.rpm  salt-cloud-3007.8-0.x86_64.rpm"
EL9_RPMS="salt-3007.8-0.x86_64.rpm  salt-ssh-3007.8-0.x86_64.rpm  salt-cloud-3007.8-0.x86_64.rpm"
# Controller tarballs
EL7_TARB="${TB_DIR}/salt-3006.15-onedir-linux-x86_64.tar.xz"
EL8_TARB="${TB_DIR}/salt-3007.8-onedir-linux-x86_64.tar.xz"
EL9_TARB="${TB_DIR}/salt-3007.8-onedir-linux-x86_64.tar.xz"
# Thin core (EL7)
THIN_CORE_RPMS="salt-2019.2.8-1.el7.noarch.rpm python2-msgpack-0.5.6-5.el7.x86_64.rpm PyYAML-3.10-11.el7.x86_64.rpm python-tornado-4.2.1-5.el7.x86_64.rpm"
THIN_SIX_ANY="six-1.16.0.tar.gz six-1.15.0.tar.gz"
THIN_EXTRAS="python-jinja2-2.7.2-2.el7.noarch.rpm python-markupsafe-0.11-10.el7.x86_64.rpm python-requests-1.1.0-8.el7.noarch.rpm"
THIN_BACKPORTS="python2-futures-3.0.5-1.el7.noarch.rpm python2-backports_abc-0.5-2.el7.noarch.rpm python-singledispatch-3.4.0.2-2.el7.noarch.rpm python-enum34-1.0.4-1.el7.noarch.rpm python2-certifi-2018.10.15-5.el7.noarch.rpm"

# ----- Helpers -----
have(){ [ -f "$1" ] && [ -s "$1" ]; }
size_mb(){ du -m -- "$1" 2>/dev/null | awk '{print $1}'; }
chk_tarball(){
  local label="$1" t="$2"
  if have "$t"; then
    if tar -tf "$t" >/dev/null 2>>"$ERR_LOG"; then
      ok "${label}: $(basename "$t") ($(size_mb "$t") MB)"; log "[OK] tarball $t"; return 0
    else
      err "${label}: invalid/corrupt $(basename "$t")"; log "[ERR] bad tarball $t"; return 1
    fi
  else
    err "${label}: missing $(basename "$t")"; log "[ERR] missing tarball $t"; return 1
  fi
}
chk_one_of(){ # $1=label $2=dir $3="file1 file2 ..."
  local label="$1" dir="$2" list="$3" f
  for f in $list; do
    if have "${dir}/${f}"; then ok "${label}: $(basename "$f")"; log "[OK] $label ${dir}/${f}"; return 0; fi
  done
  return 1
}
chk_file_in_dirs(){ # $1=label $2=fname $3="dir1 dir2" $4=severity(required|optional|info)
  local label="$1" fname="$2" dlist="$3" sev="$4" d
  for d in $dlist; do
    if have "${d}/${fname}"; then ok "${label}: $(basename "$fname")"; log "[OK] $label ${d}/${fname}"; return 0; fi
  done
  case "$sev" in
    required) err "${label}: not found (${fname})"; log "[ERR] missing $fname";;
    optional) warn "${label}: not found (${fname})"; log "[WARN] missing $fname";;
    info)     info "info: ${label} not found (${fname})"; log "[INFO] missing optional $fname";;
  esac
  return 1
}
summ_row(){ printf "%-4s | %3s/%-3s | %10s | %s\n" "$1" "$2" "$3" "$4" "$5"; }

# ----- Verify -----
REQ_FAIL=0

verify_el7(){
  local okc=0 tot=0 notes=""
  for f in $EL7_RPMS; do tot=$((tot+1)); chk_file_in_dirs "el7 rpm" "$f" "$EL7_DIR" required && okc=$((okc+1)) || REQ_FAIL=1; done
  tot=$((tot+1)); chk_tarball "el7 tarball" "$EL7_TARB" && okc=$((okc+1)) || REQ_FAIL=1
  local search_dirs="$THIN_EL7_DIR $EL7_DIR"
  for f in $THIN_CORE_RPMS; do tot=$((tot+1)); chk_file_in_dirs "el7 thin core" "$f" "$search_dirs" required && okc=$((okc+1)) || REQ_FAIL=1; done
  tot=$((tot+1))
  if chk_one_of "el7 thin core" "$THIN_EL7_DIR" "$THIN_SIX_ANY"; then okc=$((okc+1)); else
    warn "el7 thin core: six*.tar.gz not found"; [ $STRICT -eq 1 ] && REQ_FAIL=1; notes="${notes} six"
  fi
  for f in $THIN_EXTRAS; do
    if chk_file_in_dirs "el7 thin optional" "$f" "$search_dirs" info; then :; else notes="${notes} $(echo "$f"|cut -d- -f2)"; fi
  done
  for f in $THIN_BACKPORTS; do
    if chk_file_in_dirs "el7 thin backport" "$f" "$search_dirs" info; then :; else
      notes="${notes} $(echo "$f"|cut -d- -f2)"; [ $STRICT -eq 1 ] && REQ_FAIL=1
    fi
  done
  local tmb="0"; have "$EL7_TARB" && tmb="$(size_mb "$EL7_TARB")"
  [ -z "$notes" ] && notes="OK"
  summ_row "el7" "$okc" "$tot" "$tmb" "$notes"
}

verify_el8(){
  local okc=0 tot=0
  for f in $EL8_RPMS; do tot=$((tot+1)); chk_file_in_dirs "el8 rpm" "$f" "$EL8_DIR" required && okc=$((okc+1)) || REQ_FAIL=1; done
  tot=$((tot+1)); chk_tarball "el8 tarball" "$EL8_TARB" && okc=$((okc+1)) || REQ_FAIL=1
  local tmb="0"; have "$EL8_TARB" && tmb="$(size_mb "$EL8_TARB")"
  summ_row "el8" "$okc" "$tot" "$tmb" "OK"
}
verify_el9(){
  local okc=0 tot=0
  for f in $EL9_RPMS; do tot=$((tot+1)); chk_file_in_dirs "el9 rpm" "$f" "$EL9_DIR" required && okc=$((okc+1)) || REQ_FAIL=1; done
  tot=$((tot+1)); chk_tarball "el9 tarball" "$EL9_TARB" && okc=$((okc+1)) || REQ_FAIL=1
  local tmb="0"; have "$EL9_TARB" && tmb="$(size_mb "$EL9_TARB")"
  summ_row "el9" "$okc" "$tot" "$tmb" "OK"
}

# ----- Run -----
bar; info "▶ Package Verification"; printf "Project Root: %s\n" "$PROJECT_ROOT"; bar

# Heads-up INFO for optional/backports if absent in thin/el7 (non-fatal)
for f in $THIN_EXTRAS; do [ -f "${THIN_EL7_DIR}/${f}" ] || info "info: el7 thin optional: not found (${f})"; done
for f in $THIN_BACKPORTS; do [ -f "${THIN_EL7_DIR}/${f}" ] || info "info: el7 thin backport: not found (${f})"; done

bar
printf "%-4s | %-7s | %-10s | %s\n" "Plat" "OK/All" "Tarball(MB)" "Notes"
bar
[ "$PLAT" = "all" ] || [ "$PLAT" = "el7" ] && verify_el7
[ "$PLAT" = "all" ] || [ "$PLAT" = "el8" ] && verify_el8
[ "$PLAT" = "all" ] || [ "$PLAT" = "el9" ] && verify_el9
bar

if [ $REQ_FAIL -eq 0 ]; then
  ok "All required artifacts verified."
  info "Next: modules/04-extract-binaries.sh"
  exit 0
else
  err "Missing required artifacts. See lines above."
  info "Tip: add --strict to enforce optional/backports as required."
  exit 1
fi

