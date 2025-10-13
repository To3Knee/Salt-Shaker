#!/usr/bin/env bash
#===============================================================
# Script Name: 11-stage-deployables.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Stage artifacts into deployables/ with final names
# About: Locates latest project RPM and remote tarball(s), renames to
#        salt-shaker-remote-<EL version>-<date>, and copies to deployables/.
#        EL detection:
#          - el7: uses thin tarball (vendor/thin/salt-thin.tgz) as the "remote" tarball.
#          - el8/el9: if a prebuilt remote tarball exists (tmp/stage.*/*.tgz),
#            it will be used per-EL. Otherwise it will skip with a warning.
#        RPM selection:
#          - Finds newest RPM under rpmbuild/RPMS or dist/. If multiple per-EL
#            RPMs exist it picks newest per EL. If only one RPM exists, it is
#            duplicated/renamed per EL at request (so you have one RPM per EL name).
#===============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/deployables"
DATE="$(date +%Y%m%d)"
mkdir -p "$DEST"

say() { printf "%s\n" "$*"; }
ok()  { printf "✓ %s\n" "$*"; }
warn(){ printf "⚠ %s\n" "$*" >&2; }
err() { printf "✖ %s\n" "$*" >&2; exit 1; }

# --- helpers ---------------------------------------------------

find_latest_rpm_for_el() {
  local el="$1"
  # Prefer explicit el-tagged RPMs
  # search rpmbuild and dist in descending mtime; allow both noarch and el* tags
  find "$ROOT/rpmbuild/RPMS" "$ROOT/dist" -type f -name '*.rpm' 2>/dev/null \
    | grep -E "(el${el}|noarch)" \
    | xargs -r ls -1t 2>/dev/null | head -n1
}

find_latest_any_rpm() {
  find "$ROOT/rpmbuild/RPMS" "$ROOT/dist" -type f -name '*.rpm' 2>/dev/null \
    | xargs -r ls -1t 2>/dev/null | head -n1
}

find_remote_tgz_for_el() {
  local el="$1"
  # Prefer a staged tgz produced by packaging, if any
  local staged
  staged="$(find "$ROOT/tmp" -maxdepth 1 -type d -name 'stage.*' -print 2>/dev/null \
           | xargs -r -I{} find {} -maxdepth 1 -type f -name '*.tgz' 2>/dev/null \
           | xargs -r ls -1t 2>/dev/null | head -n1 || true)"
  if [[ -n "${staged:-}" ]]; then
    echo "$staged"
    return 0
  fi

  # For EL7 we can always use the Salt thin bundle
  if [[ "$el" == "7" && -f "$ROOT/vendor/thin/salt-thin.tgz" ]]; then
    echo "$ROOT/vendor/thin/salt-thin.tgz"
    return 0
  fi

  # Nothing found
  return 1
}

copy_as() {
  local src="$1" dst="$2"
  install -m 0644 "$src" "$dst"
}

# --- main ------------------------------------------------------

say "════════ Stage → deployables (${DEST}) ════════"

EL_LIST=(7 8 9)
declare -A EL_RPM EL_TGZ

# Gather RPM(s)
for el in "${EL_LIST[@]}"; do
  if rpm="$(find_latest_rpm_for_el "$el")"; then
    EL_RPM["$el"]="$rpm"
  fi
done
if [[ ${#EL_RPM[@]} -eq 0 ]]; then
  # No per-EL RPM; try newest any and reuse for all ELs as requested
  if anyrpm="$(find_latest_any_rpm)"; then
    for el in "${EL_LIST[@]}"; do
      EL_RPM["$el"]="$anyrpm"
    done
    warn "Using a single RPM for all ELs (no per-EL RPMs found): $(basename "$anyrpm")"
  else
    warn "No RPMs found under rpmbuild/RPMS or dist."
  fi
fi

# Gather remote tgz(s)
for el in "${EL_LIST[@]}"; do
  if tgz="$(find_remote_tgz_for_el "$el")"; then
    EL_TGZ["$el"]="$tgz"
  else
    warn "No remote tarball found for EL${el}. (If this is expected, ignore.)"
  fi
done

# Stage
for el in "${EL_LIST[@]}"; do
  [[ -n "${EL_RPM[$el]:-}" ]] && {
    out="$DEST/salt-shaker-remote-el${el}-${DATE}.rpm"
    copy_as "${EL_RPM[$el]}" "$out"
    ok "[el${el}] RPM → $(basename "$out")"
  }
  [[ -n "${EL_TGZ[$el]:-}" ]] && {
    out="$DEST/salt-shaker-remote-el${el}-${DATE}.tgz"
    copy_as "${EL_TGZ[$el]}" "$out"
    ok "[el${el}] Tarball → $(basename "$out")"
  }
done

say "════════ SUMMARY ════════"
ls -lh "$DEST" | awk 'NR==1 || /salt-shaker-remote-/{print}'

ok "Done."
