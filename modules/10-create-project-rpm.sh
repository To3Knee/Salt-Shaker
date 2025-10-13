#!/usr/bin/env bash
#===============================================================
#Script Name: 10-create-project-rpm.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Package project RPM
#About: Bundles project artifacts into an installable RPM.
#===============================================================
#!/bin/bash
# Script Name: 10-create-project-rpm.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Package project RPM
# About: Stages project and builds the project RPM/spec.
#!/bin/bash

set -euo pipefail

# Config
PROJECT_NAME="salt-shaker"                         # internal package name & install tree
VERSION="${SALT_SHAKER_VERSION:-3.12}"
RELEASE="${SALT_SHAKER_RELEASE:-1}"
DISTTAG="${SALT_SHAKER_DISTTAG:-el8}"              # ex: el7|el8|el9 (from smoke-all)
DATESTAMP="$(date +%Y%m%d)"

ROOT="${SALT_SHAKER_ROOT:-$(pwd)}"
PREFIX="${SALT_SHAKER_PREFIX:-$ROOT}"
ART_DIR="$ROOT/deployables"                        # <- artifacts here
TMP_DIR="$ROOT/tmp"
STAGE_DIR="$TMP_DIR/stage.$(date +%Y%m%d-%H%M%S).$$"
RPM_TOP="$ROOT/tmp/rpmbuild"

mkdir -p "$ART_DIR" "$TMP_DIR" "$RPM_TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Friendly base name for artifacts
BASENAME="salt-shaker-remote-${DISTTAG}-${DATESTAMP}"   # e.g. salt-shaker-remote-el8-20251003

log() { printf '%s %s\n' "$(date +%F\ %T) [PKG]" "$*"; }

stage_tree() {
  log "Staging → $STAGE_DIR"
  rsync -a --delete \
    --exclude 'logs/' \
    --exclude '*.bak' \
    --exclude '*.tmp' \
    --exclude '.cache/jobs/' \
    --exclude 'runtime/.cache/jobs/' \
    --exclude 'runtime/.cache/file_lists/' \
    --exclude 'tmp/' \
    "$ROOT/./" "$STAGE_DIR/"

  mkdir -p "$STAGE_DIR/runtime/.cache/thin"
}

make_tarball() {
  local tarball="$ART_DIR/${BASENAME}.tar.gz"
  log "Tarball → $tarball"
  tar -C "$STAGE_DIR" -czf "$tarball" .
  echo "$tarball"
}

write_spec() {
  local spec="$ROOT/rpm/${PROJECT_NAME}.spec"
  mkdir -p "$ROOT/rpm"
  log "SPEC → $spec"

  cat >"$spec" <<SPEC
Name:           ${PROJECT_NAME}
Version:        ${VERSION}
Release:        ${RELEASE}.%{?dist}%{!?dist:.${DISTTAG}}
Summary:        Portable Salt-SSH bundle for air-gapped EL7/8/9
License:        MIT
BuildArch:      x86_64
%global _topdir        ${RPM_TOP}
%global _tmppath       ${TMP_DIR}
%global debug_package  %{nil}
%global _enable_debug_packages 0
%global _find_debuginfo 0
%global _find_debuginfo_sh /bin/true
%global __strip        /bin/true
%global __os_install_post %{nil}
%global __provides_exclude_from ^%{_prefix}/${PROJECT_NAME}/vendor/.*$

%description
Salt-Shaker: portable Salt-SSH controller for air-gapped EL7/EL8/EL9.
Installs under %{_prefix}/${PROJECT_NAME} with vendor onedir runtimes & runtime configs.

%prep
%setup -q -n ${PROJECT_NAME}-${VERSION}

%build
# none

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_prefix}/${PROJECT_NAME}
cp -a . %{buildroot}%{_prefix}/${PROJECT_NAME}/

# Post-build README
cat > %{buildroot}%{_prefix}/${PROJECT_NAME}/README-INSTALL.txt <<'RMD'
Salt-Shaker Portable (Install/Run)

Install:
  rpm -Uvh /path/to/salt-shaker-${VERSION}-${RELEASE}.${DISTTAG}.x86_64.rpm

Layout (installed):
  %{_prefix}/${PROJECT_NAME}/
    bin/     wrappers
    env/     wrapper sources
    runtime/ conf/, roster/, file-roots/, pillar/, logs/, .cache/
    vendor/  onedir runtimes
    modules/ menu modules
    support/ helpers

Example usage:
  export SALT_SHAKER_ROOT="%{_prefix}/${PROJECT_NAME}"
  export SALT_SHAKER_RUNTIME_DIR="$SALT_SHAKER_ROOT/runtime"

  "$SALT_SHAKER_ROOT/bin/salt-ssh-el8" -c "$SALT_SHAKER_RUNTIME_DIR/conf" \
      --roster-file "$SALT_SHAKER_RUNTIME_DIR/roster/roster.yaml" \
      -W --ignore-host-keys TARGET test.ping
RMD

%files
%{_prefix}/${PROJECT_NAME}
/%{_prefix}/${PROJECT_NAME}/README-INSTALL.txt

%post
echo "Installed: %{_prefix}/${PROJECT_NAME}"
echo "See: %{_prefix}/${PROJECT_NAME}/README-INSTALL.txt"

%changelog
* Fri Oct 03 2025 Salt-Shaker - ${VERSION}-${RELEASE}
- In-project rpmbuild; artifacts exported to deployables/
SPEC
}

build_rpm() {
  local build_dir="$ROOT/tmp/src.${PROJECT_NAME}-${VERSION}"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  rsync -a --delete "$STAGE_DIR/./" "$build_dir/${PROJECT_NAME}-${VERSION}/"
  tar -C "$build_dir" -czf "$RPM_TOP/SOURCES/${PROJECT_NAME}-${VERSION}.tar.gz" "${PROJECT_NAME}-${VERSION}"

  write_spec

  log "Building RPM..."
  rpmbuild -bb "$ROOT/rpm/${PROJECT_NAME}.spec" \
    --define "_topdir ${RPM_TOP}" \
    --define "_tmppath ${TMP_DIR}" \
    --define "_sourcedir %{_topdir}/SOURCES" \
    --define "_builddir %{_topdir}/BUILD" \
    --define "_srcrpmdir %{_topdir}/SRPMS" \
    --define "_rpmdir %{_topdir}/RPMS" \
    --define "debug_package %{nil}" \
    --define "_enable_debug_packages 0" \
    --define "_find_debuginfo 0" \
    --define "_find_debuginfo_sh /bin/true" \
    --define "__strip /bin/true" \
    --define "__os_install_post %{nil}" \
    --define "dist .${DISTTAG}" \
    --target x86_64

  # find the built rpm and copy to deployables with friendly name
  local built
  built="$(ls -1t "$RPM_TOP"/RPMS/*/${PROJECT_NAME}-${VERSION}-*.${DISTTAG}.x86_64.rpm 2>/dev/null | head -1 || true)"
  if [[ -z "${built:-}" ]]; then
    built="$(ls -1t "$RPM_TOP"/RPMS/*/*.rpm 2>/dev/null | head -1 || true)"
  fi
  if [[ -n "${built:-}" ]]; then
    local friendly="$ART_DIR/${BASENAME}.rpm"
    cp -f "$built" "$friendly"
    echo "$friendly"
  else
    echo "RPM build failed (no artifact found)" >&2
    return 1
  fi
}

main() {
  stage_tree
  local TAR
  TAR="$(make_tarball)"
  local RPM
  RPM="$(build_rpm)"

  log "Artifacts:"
  log "  Tar: $TAR"
  log "  RPM: $RPM"

  # Cleanup heavy build dirs
  rm -rf "$STAGE_DIR" "$RPM_TOP/BUILD" "$RPM_TOP/BUILDROOT"
}
main "$@"
