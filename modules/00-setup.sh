#!/usr/bin/env bash
#===============================================================
#Script Name: 00-setup.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Initialize project layout
#About: Creates base dirs, sanity checks, and prepares workspace.
#===============================================================
#!/bin/bash
# Script Name: 00-setup.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Project bootstrap
# About: Create initial directory structure, verify tools, prepare env.
#!/bin/bash

set -euo pipefail
LC_ALL=C

# -------- UI (EL7-safe) --------
if [ -t 1 ]; then
  COK='\033[1;32m'; CWARN='\033[1;33m'; CERR='\033[0;31m'; CINFO='\033[0;36m'; CRESET='\033[0m'
else
  COK=""; CWARN=""; CERR=""; CINFO=""; CRESET=""
fi
ok(){ printf "%b✓ %s%b\n" "$COK" "$*" "$CRESET"; }
warn(){ printf "%b⚠ %s%b\n" "$CWARN" "$*" "$CRESET" >&2; }
err(){ printf "%b✖ %s%b\n" "$CERR" "$*" "$CRESET" >&2; }
info(){ printf "%b%s%b\n" "$CINFO" "$*" "$CRESET"; }
bar(){ printf "%b%s%b\n" "$CINFO" "──────────────────────────────────────────────────────────────" "$CRESET"; }

# -------- About/Help --------
show_about(){ cat <<'EOF'
Portable Salt Shaker setup (runtime-first).
Creates runtime/ tree and a safe master config. No legacy dirs.
Idempotent: re-runs do not clobber existing files.
EOF
}
show_help(){ cat <<'EOF'
Usage: modules/00-setup.sh [--force-master] [--no-gitignore]

Options:
  --force-master   Rewrite runtime/conf/master even if it exists
  --no-gitignore   Skip updating .gitignore

This script is EL7-safe and produces a fully portable layout.
EOF
}

FORCE_MASTER=0
DO_GITIGNORE=1
for a in "$@"; do
  case "$a" in
    -a|--about) show_about; exit 0;;
    -h|--help) show_help; exit 0;;
    --force-master) FORCE_MASTER=1;;
    --no-gitignore) DO_GITIGNORE=0;;
    *) warn "Unknown option: $a";;
  esac
done

# -------- Resolve project root --------
RESOLVE_ABS(){ local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s" "$(pwd)" "$(basename -- "$p")" )
  fi
}
PRJ="$(RESOLVE_ABS "$(pwd)")"

bar
info "SALT SHAKER | Setup (runtime-first)"
bar
info "Project Root : $PRJ"

# -------- Create directories (idempotent) --------
# Only create portable layout. No legacy conf/roster/pillar at root.
# Folder perms: 700 per requirement; executables handled elsewhere.

make_dir_700(){ mkdir -p "$1" && chmod 700 "$1"; }

created=0; chmods=0

create_700(){
  local d="$1"
  if [ ! -d "$d" ]; then make_dir_700 "$d"; created=$((created+1)); chmods=$((chmods+1)); else chmod 700 "$d" 2>/dev/null || true; chmods=$((chmods+1)); fi
}

# Core
create_700 "$PRJ/logs"
create_700 "$PRJ/runtime"
create_700 "$PRJ/runtime/bin"
create_700 "$PRJ/runtime/conf"
create_700 "$PRJ/runtime/file-roots"
create_700 "$PRJ/runtime/pillar"
create_700 "$PRJ/runtime/roster"
create_700 "$PRJ/runtime/roster/data"
create_700 "$PRJ/runtime/.cache"
create_700 "$PRJ/runtime/logs"
create_700 "$PRJ/runtime/etc"
create_700 "$PRJ/runtime/etc/salt"
create_700 "$PRJ/runtime/etc/salt/pki"
# Optional trees the rest of the project expects
mkdir -p "$PRJ/offline" "$PRJ/offline/salt" "$PRJ/offline/salt/tarballs" "$PRJ/offline/salt/thin" "$PRJ/vendor" "$PRJ/tmp"
# Normalize perms where created above (not counted in stats)
chmod 700 "$PRJ/offline" "$PRJ/vendor" "$PRJ/tmp" 2>/dev/null || true

# -------- Write runtime/conf/master (safe) --------
MASTER="$PRJ/runtime/conf/master"
if [ ! -s "$MASTER" ] || [ "$FORCE_MASTER" -eq 1 ]; then
  cat > "$MASTER" <<EOF
# Portable Salt Shaker master for salt-ssh (runtime-first)
verify_env: false

cachedir: $PRJ/runtime/.cache

file_roots:
  base:
    - $PRJ/runtime/file-roots

pillar_roots:
  base:
    - $PRJ/runtime/pillar

log_file: $PRJ/runtime/logs/master
log_level: info

# Keep all controller activity inside project runtime
ssh_minion_opts:
  minion_id: shaker-controller
  minion_id_caching: False
  file_client: local

state_output: changes
state_verbose: true
hash_type: sha256
EOF
  chmod 600 "$MASTER"
  ok "wrote runtime/conf/master"
else
  ok "runtime/conf/master exists (left unchanged)"
fi

# -------- Provide CSV location (do not overwrite) --------
CSV="$PRJ/runtime/roster/data/hosts-all-pods.csv"
if [ ! -e "$CSV" ]; then
  # only header, no sample rows; Module 02 will manage population
  cat > "$CSV" <<'CSV'
pod,platform,host,port,user,auth,sudo,python2_bin,ssh_args,minion_id,groups,notes
CSV
  chmod 600 "$CSV" || true
  ok "prepared runtime/roster/data/hosts-all-pods.csv (header only)"
else
  ok "runtime/roster/data/hosts-all-pods.csv exists (left unchanged)"
fi

# -------- Harden .gitignore (idempotent) --------
if [ "$DO_GITIGNORE" -eq 1 ]; then
  GITIGNORE="$PRJ/.gitignore"
  touch "$GITIGNORE"
  add_ignore(){
    local pat="$1"
    grep -q -F "$pat" "$GITIGNORE" 2>/dev/null || echo "$pat" >> "$GITIGNORE"
  }
  add_ignore "# runtime/sensitive & generated"
  add_ignore "runtime/.cache/"
  add_ignore "runtime/logs/"
  add_ignore "runtime/etc/"
  add_ignore "runtime/roster/roster.yaml"
  add_ignore "runtime/roster/data/hosts-all-pods.csv"
  add_ignore "runtime/pillar/data.sls"
  add_ignore "logs/"
  add_ignore "tmp/"
  add_ignore "*.bak.*"
  add_ignore "*.bak.postreloc"
  ok ".gitignore hardened"
fi

# -------- Summary --------
bar
printf "✓ Setup complete.\nSummary: created=%d, chmods=%d\n" "$created" "$chmods"
bar

exit 0
