#!/bin/bash
#===============================================================
#Script Name: 05-build-thin-el7.sh
#Date: 09/29/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 3.40
#Short: Build EL7 Python2 salt-ssh thin (2019.2.x)
#About: Creates vendor/el7/thin/salt-thin.tgz for Python 2.7.5 targets (EL7).
#About: Required: salt, msgpack, PyYAML (yaml), tornado, six. Optional: jinja2,
#About: markupsafe, requests. Backports (optional): futures, backports_abc,
#About: singledispatch, enum34, certifi. EL7-safe Bash, in-project artifacts only.
#===============================================================

set -e -o pipefail  # EL7-safe (no -u)

# ---------- Colors/UI ----------
if [ -t 1 ]; then
  COK='\033[1;32m'; CWARN='\033[1;33m'; CERR='\033[1;31m'; CINFO='\033[0;36m'; CRESET='\033[0m'
else
  COK=""; CWARN=""; CERR=""; CINFO=""; CRESET=""
fi
ok(){ printf "%b✓ %s%b\n" "$COK" "$*" "$CRESET"; }
warn(){ printf "%b⚠ %s%b\n" "$CWARN" "$*" "$CRESET" >&2; }
err(){ printf "%b✖ %s%b\n" "$CERR" "$*" "$CRESET" >&2; }
info(){ printf "%b%s%b\n" "$CINFO" "$*" "$CRESET"; }
bar(){ printf "%b%s%b\n" "$CINFO" "══════════════════════════════════════════════════════════════════════" "$CRESET"; }

# ---------- Bootstrap PROJECT_ROOT ----------
RESOLVE_ABS(){ local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  fi
}
FIND_ROOT_UP(){ local d="$1" i=8
  while [ "$i" -gt 0 ] && [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then echo "$d"; return 0; fi
    d="$(dirname -- "$d")"; i=$((i-1))
  done; return 1
}
SCRIPT_ABS="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_ABS")"
if [ -n "${SALT_SHAKER_ROOT:-}" ] && [ -d "${SALT_SHAKER_ROOT}" ]; then
  PROJECT_ROOT="$(RESOLVE_ABS "$SALT_SHAKER_ROOT")"
else
  PROJECT_ROOT="$(FIND_ROOT_UP "$SCRIPT_DIR" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(FIND_ROOT_UP "$(pwd)" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(RESOLVE_ABS "$(pwd)")"
fi

# ---------- Paths ----------
OFFLINE_DIR="${PROJECT_ROOT}/offline"
SALT_DIR="${OFFLINE_DIR}/salt"
THIN_POOL_EL7="${SALT_DIR}/thin/el7"
EL7_POOL="${SALT_DIR}/el7"
TMP_DIR="${PROJECT_ROOT}/tmp"
CACHE_DIR="${PROJECT_ROOT}/.cache"
LOG_DIR="${PROJECT_ROOT}/logs"; mkdir -p "${LOG_DIR}" 2>/dev/null || true
MAIN_LOG="${LOG_DIR}/salt-shaker.log"; ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
OUT_DIR="${PROJECT_ROOT}/vendor/el7/thin"; OUT_TGZ="${OUT_DIR}/salt-thin.tgz"

# ---------- Tools ----------
need_tool(){ command -v "$1" >/dev/null 2>&1 || { err "Missing tool: $1"; exit 2; }; }
need_tool rpm2cpio; need_tool cpio; need_tool tar

# ---------- CLI ----------
FORCE=0; DRY=0; PROMPT_WRAPPERS=1; DEBUG_TREE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1;;
    --force) FORCE=1;;
    --no-wrapper-prompt) PROMPT_WRAPPERS=0;;
    --debug-tree) DEBUG_TREE=1;;
    -h|--help)
      cat <<EOF
Usage: ${0##*/} [--dry-run] [--force] [--debug-tree] [--no-wrapper-prompt]
Build EL7 thin tarball from staged RPMs:
  ${THIN_POOL_EL7}  (preferred)  and  ${EL7_POOL} (fallback)
Output: ${OUT_TGZ}
EOF
      exit 0;;
    *) warn "Unknown option: $1";;
  esac
  shift || true
done

logi(){ printf "[%s] [INFO] %s\n" "$(date +'%F %T')" "$*" >>"$MAIN_LOG" 2>/dev/null || true; }
loge(){ printf "[%s] [ERROR] %s\n" "$(date +'%F %T')" "$*" | tee -a "$ERROR_LOG" >>"$MAIN_LOG" 2>/dev/null || true; }

# ---------- Helpers ----------
space_ok(){ local need="$1" here="$PROJECT_ROOT"; local have="$(df -Pm "$here" | awk 'NR==2{print $4}')"; [ -z "$have" ] && have=0
  [ "$have" -ge "$need" ] && { ok "Space OK: need ${need}MB, have ${have}MB"; return 0; } || { err "Insufficient space: need ${need}MB, have ${have}MB"; return 1; }; }
first_present(){ local name="$1" p; for p in "${THIN_POOL_EL7}" "${EL7_POOL}"; do if [ -f "${p}/${name}" ] && [ -s "${p}/${name}" ]; then printf "%s\n" "$(RESOLVE_ABS "${p}/${name}")"; return 0; fi; done; return 1; }
have_any(){ local name="$1"; first_present "$name" >/dev/null 2>&1; }
extract_rpm_payload(){ local rpm="$1" dest="$2"; mkdir -p "$dest"; rpm2cpio "$rpm" | ( cd "$dest" && cpio -idm --quiet ); }

copy_py2_site_if_present(){ # copy site/dist-packages trees if available
  local root="$1" dest="$2" src found=0; mkdir -p "$dest"
  for src in \
    "$root/usr/lib/python2.7/site-packages" \
    "$root/usr/lib64/python2.7/site-packages" \
    "$root/usr/lib/python2.7/dist-packages" \
    "$root/usr/lib64/python2.7/dist-packages"
  do
    if [ -d "$src" ]; then (cd "$src" && tar -cf - .) | (cd "$dest" && tar -xf -); found=1; fi
  done
  return $found
}

copy_module_anywhere(){ # fallback, find module dir by name anywhere in payload
  local root="$1" dest="$2" mod="$3" path; mkdir -p "$dest"
  path="$(cd "$root" && find . -maxdepth 10 -type d -name "$mod" 2>/dev/null | head -n1 || true)"
  if [ -n "$path" ] && [ -d "$root/$path" ]; then
    (cd "$root/$path/.." && tar -cf - "$mod") | (cd "$dest" && tar -xf -)
    return 0
  fi
  return 1
}

verify_pkg(){ # assert module staged
  local dest="$1" mod="$2" critical="$3"
  if [ -f "${dest}/${mod}/__init__.py" ] || [ -d "${dest}/${mod}" ]; then ok "Added: ${mod}"; return 0; fi
  if [ "$critical" -eq 1 ]; then err "Failed to stage critical module: ${mod}"; return 1; else warn "Could not locate ${mod} in payload"; return 0; fi
}

dump_payload_hints(){ # triage
  { echo "--- payload hint for $2 ---"
    ( cd "$1" && find . -maxdepth 10 -type d \( -name 'salt' -o -name 'yaml' -o -name 'msgpack' -o -name 'tornado' \) -print 2>/dev/null | head -n 80 )
    echo "---------------------------"
  } >>"$MAIN_LOG" 2>/dev/null || true
}

copy_six_from_tar(){ local six_tgz="$1" dest="$2"
  mkdir -p "$dest"; local tmp="${TMP_DIR}/six-src.$$"
  mkdir -p "$tmp"; tar -xzf "$six_tgz" -C "$tmp" >/dev/null 2>&1 || true
  local sixpy; sixpy="$(find "$tmp" -type f -name 'six.py' 2>/dev/null | head -n1 || true)"
  if [ -n "$sixpy" ] && [ -s "$sixpy" ]; then install -m0644 "$sixpy" "${dest}/six.py"; else err "six.py not found in $(basename "$six_tgz")"; rm -rf "$tmp"; return 1; fi
  rm -rf "$tmp"; return 0
}

# Robust archive check (works with "./salt/..." or "salt/...")
has_salt_in_tgz(){ # $1 tgz path, echoes count; returns 0 if >0 else 1
  local tgz="$1" cnt
  cnt="$(tar -tzf "$tgz" 2>/dev/null | sed 's#^\./##' | grep -E '^salt(/|$)' -c || true)"
  [ -z "$cnt" ] && cnt=0
  if [ "$cnt" -gt 0 ]; then echo "$cnt"; return 0; else echo 0; return 1; fi
}

# ---------- Sets ----------
REQ_LIST="salt-2019.2.8-1.el7.noarch.rpm python2-msgpack-0.5.6-5.el7.x86_64.rpm PyYAML-3.10-11.el7.x86_64.rpm python-tornado-4.2.1-5.el7.x86_64.rpm"
OPT_LIST="python-jinja2-2.7.2-2.el7.noarch.rpm python-markupsafe-0.11-10.el7.x86_64.rpm python-requests-1.1.0-8.el7.noarch.rpm"
BP_LIST="python2-futures-3.0.5-1.el7.noarch.rpm python2-backports_abc-0.5-2.el7.noarch.rpm python-singledispatch-3.4.0.2-2.el7.noarch.rpm python-enum34-1.0.4-1.el7.noarch.rpm python2-certifi-2018.10.15-5.el7.noarch.rpm"
SIX_RPM="python-six-1.16.0-1.el7.noarch.rpm"  # else six-*.tar.gz present

# ---------- Start ----------
bar; info "▶ Build thin el7"; info "Project Root: ${PROJECT_ROOT}"; bar
chmod -R u+rw "${THIN_POOL_EL7}" 2>/dev/null || true
chmod -R u+rw "${EL7_POOL}" 2>/dev/null || true
space_ok 333

STAGE="${TMP_DIR}/thin-el7-build.$$"
[ "$DRY" -eq 1 ] || rm -rf "$STAGE"
[ "$DRY" -eq 1 ] || mkdir -p "$STAGE/extract" "$STAGE/lib/python2.7/site-packages" "$OUT_DIR" "$CACHE_DIR"
[ "$FORCE" -eq 1 ] && [ -f "$OUT_TGZ" ] && { ok "Cleared existing: ${OUT_TGZ}"; [ "$DRY" -eq 1 ] || rm -f "$OUT_TGZ"; }

SITE="${STAGE}/lib/python2.7/site-packages"

# Salt RPM (mandatory)
SALT_RPM="salt-2019.2.8-1.el7.noarch.rpm"
SALT_RPM_PATH="$(first_present "$SALT_RPM" || true)"
[ -z "$SALT_RPM_PATH" ] && { err "Salt RPM not found: ${SALT_RPM}"; exit 5; }
ok "Using salt RPM: $(basename "$SALT_RPM_PATH")"

# Required payloads
for name in $REQ_LIST; do
  path="$(first_present "$name" || true)"; [ -z "$path" ] && { err "Required missing: $name"; exit 5; }
  if [ "$DRY" -eq 1 ]; then ok "[DRY] would add: $(basename "$path")"; continue; fi
  EX="${STAGE}/extract/$(basename "$name" .rpm)"; mkdir -p "$EX"; extract_rpm_payload "$path" "$EX"
  mod=""; case "$name" in
    salt-*)              mod="salt" ;;
    python2-msgpack-*)   mod="msgpack" ;;
    PyYAML-*)            mod="yaml" ;;
    python-tornado-*)    mod="tornado" ;;
  esac
  copied=0
  copy_py2_site_if_present "$EX" "$SITE" && copied=1
  if [ "$copied" -eq 1 ] && [ -n "$mod" ] && [ ! -d "${SITE}/${mod}" ]; then copy_module_anywhere "$EX" "$SITE" "$mod" && copied=1; fi
  if [ "$copied" -eq 0 ] && [ -n "$mod" ]; then copy_module_anywhere "$EX" "$SITE" "$mod" && copied=1; fi
  critical=0; [ "$mod" = "salt" ] && critical=1
  if ! verify_pkg "$SITE" "$mod" "$critical"; then dump_payload_hints "$EX" "$name"; err "Cannot build thin: '${mod}' not found in ${name}"; exit 6; fi
done

# six
if have_any "$SIX_RPM"; then
  SIX_PATH="$(first_present "$SIX_RPM")"
  [ "$DRY" -ne 1 ] && { EX="${STAGE}/extract/$(basename "$SIX_RPM" .rpm)"; mkdir -p "$EX"; extract_rpm_payload "$SIX_PATH" "$EX"; copy_py2_site_if_present "$EX" "$SITE" >/dev/null 2>&1 || true; }
  ok "Added: six.py"
else
  SIX_TGZ="$(ls -1 "${THIN_POOL_EL7}"/six-*.tar.gz 2>/dev/null | head -n1 || true)"
  [ -z "$SIX_TGZ" ] && { err "Missing six (RPM or six-*.tar.gz)"; exit 5; }
  [ "$DRY" -ne 1 ] && copy_six_from_tar "$SIX_TGZ" "$SITE" || true
  ok "Added: six.py"
fi

# optional extras
for name in $OPT_LIST; do
  path="$(first_present "$name" || true)"; [ -z "$path" ] && continue
  [ "$DRY" -ne 1 ] && { EX="${STAGE}/extract/$(basename "$name" .rpm)"; mkdir -p "$EX"; extract_rpm_payload "$path" "$EX"; copy_py2_site_if_present "$EX" "$SITE" >/dev/null 2>&1 || true; }
  ok "Added: $(echo "$name" | sed 's/\.rpm$//')"
done

# backports
MISSING_BP=""
for name in $BP_LIST; do
  path="$(first_present "$name" || true)"
  if [ -n "$path" ]; then
    [ "$DRY" -ne 1 ] && { EX="${STAGE}/extract/$(basename "$name" .rpm)"; mkdir -p "$EX"; extract_rpm_payload "$path" "$EX"; copy_py2_site_if_present "$EX" "$SITE" >/dev/null 2>&1 || true; }
    ok "Added: $(echo "$name" | sed 's/\.rpm$//')"
  else
    short="$(echo "$name" | sed -e 's/^python2-//' -e 's/^python-//' -e 's/\.noarch\.rpm$//' -e 's/-[0-9].*$//' )"
    [ -z "$MISSING_BP" ] && MISSING_BP="$short" || MISSING_BP="$MISSING_BP,$short"
  fi
done
[ -n "$MISSING_BP" ] && warn "Missing backports (optional): $MISSING_BP"

# sanity before packaging
if [ "$DRY" -ne 1 ] && [ ! -d "${SITE}/salt" ]; then
  err "Staging sanity failed: ${SITE}/salt missing"; exit 6
fi

# prune + package
if [ "$DRY" -ne 1 ]; then
  find "$SITE" -type d \( -name 'tests' -o -name 'test' \) -prune -exec rm -rf {} + 2>/dev/null || true
  find "$SITE" -type f -name '*.pyc' -delete 2>/dev/null || true
  ok "Pruned development files"

  mkdir -p "${OUT_DIR}"
  ( cd "$SITE" && tar -czf "${OUT_TGZ}" . )
  size_k="$(du -k "${OUT_TGZ}" | awk '{print $1}')"; size_disp="$(awk "BEGIN { printf \"%.1f\", ${size_k}/1024 }")"
  ok "Thin created: ${OUT_TGZ} (${size_disp} MB)"

  # FINAL: relaxed archive validation (EL7/EL8/EL9 consistent)
  count="$(has_salt_in_tgz "${OUT_TGZ}")"
  if [ "$count" -gt 0 ]; then
    ok "Archive contains salt/ (entries: ${count})"
  else
    { echo "--- archive listing (head) ---"; tar -tzf "${OUT_TGZ}" 2>/dev/null | head -n 120; echo "------------------------------"; } >>"$MAIN_LOG" 2>/dev/null || true
    err "Thin missing salt/ package"; exit 6
  fi
else
  ok "Dry-run complete"
fi

# summary
echo
echo "SUMMARY (thin for EL7 Py2)"
printf "%-14s | %-18s | %9s | %s\n" "Output" "Salt Version" "Size(MB)" "Included"
printf "%-14s | %-18s | %9s | %s\n" "--------------" "------------------" "---------" "----------------------------------------"
size_disp="$( [ -f "${OUT_TGZ}" ] && du -m "${OUT_TGZ}" | awk '{print $1}' || echo 0 )"
inc="salt,msgpack,yaml,tornado,six"
for name in $OPT_LIST; do path="$(first_present "$name" || true)"; [ -n "$path" ] && inc="${inc},$(echo "$name" | cut -d- -f2)"; done
for name in $BP_LIST; do path="$(first_present "$name" || true)"; [ -n "$path" ] && inc="${inc},$(echo "$name" | sed -e 's/^python2-//' -e 's/^python-//' -e 's/-[0-9].*$//' )"; done
printf "%-14s | %-18s | %9s | %s\n" "salt-thin.tgz" "2019.2.8-1.el7" "$( [ "$DRY" -eq 1 ] && echo 0 || echo "$size_disp" )" "$inc"
[ -n "$MISSING_BP" ] && warn "missing backports: $MISSING_BP"

# offer wrappers install
if [ "$PROMPT_WRAPPERS" -eq 1 ] && [ "$DRY" -ne 1 ] && [ -f "${PROJECT_ROOT}/env/90-install-env-wrappers.sh" ]; then
  printf "Install/refresh env wrappers now? [Y/n]: "; read ans || ans=""
  case "${ans}" in n|N|no|NO) info "Skipped wrapper install.";;
    *) info "Installing wrappers..."; ( cd "${PROJECT_ROOT}" && ./env/90-install-env-wrappers.sh ) || warn "Wrapper install reported issues";;
  esac
fi

ok "Module 05 completed"
exit 0

