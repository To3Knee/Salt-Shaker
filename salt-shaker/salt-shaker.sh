#!/usr/bin/env bash
#===============================================================
#Script Name: salt-shaker.sh
#Date: 09/04/2025
#Created By: To3Knee
#Version: 0.2.2
#About: Portable Salt-SSH wrapper for the "Salt Shaker" project.
#       - Air-gapped friendly (no package installs on targets)
#       - Password auth (no SSH keys required)
#       - Self-contained config/roster/file-roots/pillar in project tree
#       - Human-readable logging with smart defaults
#       - Subcommands: init, check, ping, state, cmd, build-tar, build-rpm
#       - Dry-run support: -t / --test (state.apply test=True)
#===============================================================

# ===================== BEGIN: EDIT HERE (Safe Defaults) ======================
# READ ME:
# - Do NOT rename the variable names on the left (e.g., PROJECT_DIR).
# - Only change the values on the right if needed (inside the quotes).
# - Directory *names* you set must actually exist on disk.
#
# ------------------ DEFAULT PROJECT STRUCTURE (example) ------------------
# salt-shaker/                 <-- PROJECT_DIR
# ├── salt-ssh-config/         <-- CONFIG_DIR_NAME (contains master)
# │    └── master
# ├── roster                   <-- ROSTER_FILE_NAME
# ├── file-roots/              <-- FILE_ROOTS_NAME (states live here)
# │    ├── top.sls
# │    ├── init.sls
# │    └── templates/          <-- user-friendly state templates
# │         ├── restart-host.sls
# │         ├── reset-password.sls
# │         ├── install-package.sls
# │         ├── service-manage.sls
# │         ├── run-command.sls
# │         └── combo-task.sls
# ├── pillar/                  <-- PILLAR_ROOTS_NAME (pillar data)
# │    ├── top.sls
# │    └── data.sls
# ├── .cache/                  <-- CACHE_DIR_NAME (local cache, hidden ok)
# ├── vendor/                  <-- portable salt-ssh binary
# │    └── salt/bin/salt-ssh   <-- VENDOR_SALT_SSH_PATH
# └── logs/                    <-- auto-created if you run outside /home or /srv/tmp
#     ├── salt-shaker.log
#     └── salt-ssh-transport.log
#
# If your tree looks like this, you can leave all defaults unchanged.
# ------------------------------------------------------------------------

# --- Project Location ---
# Default: the folder containing this script.
# change-me example (pin to a known location):
#   PROJECT_DIR="/srv/tmp/salt-shaker"
PROJECT_DIR="${PROJECT_DIR:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"

# --- Content Folders (relative to PROJECT_DIR) ---
# Only edit if you renamed your directories (names, not full paths).

# CONFIG directory name (contains 'master')
# change-me examples:
#   CONFIG_DIR_NAME="config"            # if you renamed salt-ssh-config -> config
#   CONFIG_DIR_NAME="salt-ssh-config"   # default
CONFIG_DIR_NAME="${CONFIG_DIR_NAME:-salt-ssh-config}"

# ROSTER file name (flat roster file at PROJECT_DIR/<name>)
# change-me examples:
#   ROSTER_FILE_NAME="hosts"            # friendlier name
#   ROSTER_FILE_NAME="roster"           # default
ROSTER_FILE_NAME="${ROSTER_FILE_NAME:-roster}"

# FILE ROOTS directory name (holds your .sls states)
# change-me examples:
#   FILE_ROOTS_NAME="states"            # if you prefer 'states/'
#   FILE_ROOTS_NAME="file-roots"        # default
FILE_ROOTS_NAME="${FILE_ROOTS_NAME:-file-roots}"

# PILLAR ROOTS directory name (holds pillar .sls)
# change-me examples:
#   PILLAR_ROOTS_NAME="pillars"         # if you prefer 'pillars/'
#   PILLAR_ROOTS_NAME="pillar"          # default
PILLAR_ROOTS_NAME="${PILLAR_ROOTS_NAME:-pillar}"

# LOCAL CACHE directory name (ok to keep hidden)
# change-me examples:
#   CACHE_DIR_NAME="cache"              # visible folder
#   CACHE_DIR_NAME=".cache"             # default (hidden)
CACHE_DIR_NAME="${CACHE_DIR_NAME:-.cache}"

# --- Salt-SSH Binary (portable) ---
# Relative to PROJECT_DIR; preferred to bundle. Fallback: PATH.
# change-me examples:
#   VENDOR_SALT_SSH_PATH="bin/salt-ssh"               # PROJECT_DIR/bin/salt-ssh
#   VENDOR_SALT_SSH_PATH="vendor/salt/bin/salt-ssh"   # default layout
VENDOR_SALT_SSH_PATH="${VENDOR_SALT_SSH_PATH:-vendor/salt/bin/salt-ssh}"

# --- Behavior Toggles (safe defaults) ---
# Max parallel SSH connections (keep modest for first runs)
MAX_PROCS="${MAX_PROCS:-5}"

# Prompt for SSH password? 1=yes (safe), 0=no (use -P)
PROMPT_PASSWORD="${PROMPT_PASSWORD:-1}"

# Ignore unknown host keys? 1=yes (convenient in labs), 0=no (safer)
IGNORE_UNKNOWN_HOST_KEYS="${IGNORE_UNKNOWN_HOST_KEYS:-0}"

# Global dry-run default (same as -t/--test). 1=on, 0=off
TEST_MODE_DEFAULT="${TEST_MODE_DEFAULT:-0}"

# --- Logging (smart defaults) ---
# If you RUN this script from /home/* or /srv/tmp/*, logs go THERE.
# Otherwise logs go under PROJECT_DIR/logs.
# You can force a location by setting LOG_DIR explicitly, e.g.:
#   LOG_DIR="/home/user4749/salt-shaker-logs"
LOG_BASENAME_MAIN="salt-shaker.log"
LOG_BASENAME_TRANSPORT="salt-ssh-transport.log"
# ====================== END: EDIT HERE (Safe Defaults) ======================

# ---------- DO NOT EDIT BELOW UNLESS YOU KNOW WHAT YOU'RE DOING ----------
set -euo pipefail

# Resolve core paths (no underscores in folder/file names we create)
CONFIG_DIR="$PROJECT_DIR/$CONFIG_DIR_NAME"
ROSTER_FILE="$PROJECT_DIR/$ROSTER_FILE_NAME"
FILE_ROOTS_DIR="$PROJECT_DIR/$FILE_ROOTS_NAME"
PILLAR_ROOTS_DIR="$PROJECT_DIR/$PILLAR_ROOTS_NAME"
CACHE_DIR="$PROJECT_DIR/$CACHE_DIR_NAME"

# Pick a log directory (based on where you run):
RUN_DIR="$(pwd)"
case "$RUN_DIR" in
  /home/*|/srv/tmp/*) DEFAULT_LOG_DIR="$RUN_DIR" ;;
  *)                  DEFAULT_LOG_DIR="$PROJECT_DIR/logs" ;;
esac
LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
mkdir -p "$LOG_DIR" "$CACHE_DIR"

RAW_LOG="$LOG_DIR/$LOG_BASENAME_MAIN"
SSH_TRANSPORT_LOG="$LOG_DIR/$LOG_BASENAME_TRANSPORT"

# salt-ssh binary: prefer vendor, fallback to PATH
SALT_SSH_BIN_DEFAULT="$PROJECT_DIR/$VENDOR_SALT_SSH_PATH"
if [[ -x "$SALT_SSH_BIN_DEFAULT" ]]; then
  SALT_SSH_BIN="$SALT_SSH_BIN_DEFAULT"
elif command -v salt-ssh >/dev/null 2>&1; then
  SALT_SSH_BIN="$(command -v salt-ssh)"
else
  echo "ERROR: salt-ssh not found. Place it at $SALT_SSH_BIN_DEFAULT or add to PATH." >&2
  exit 1
fi

# Logging helpers
log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$RAW_LOG" >&2; }
die()  { log "ERROR: $*"; exit 1; }

cleanup() {
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    log "Script terminated with non-zero exit code: $rc"
  else
    log "Completed successfully."
  fi
  exit $rc
}
trap cleanup EXIT
trap 'die "Interrupted by user (SIGINT)."' INT
trap 'die "Terminated (SIGTERM)."' TERM

print_about() {
cat <<'EOF'
#===============================================================
#Script Name: salt-shaker.sh
#Date: 09/04/2025
#Created By: To3Knee
#Version: 0.2.2
#About: Portable Salt-SSH wrapper for the "Salt Shaker" project.
#===============================================================
EOF
}

print_help() {
cat <<EOF
Usage: $(basename "$0") [options] <subcommand> [args]

Subcommands:
  init                     Initialize project skeleton (safe to re-run).
  check                    Validate environment, paths, and salt-ssh presence.
  ping <target>            Run test.ping on target(s).
  state <target> <state>   Apply a state (e.g., 'templates.install-package').
  cmd <target> "<shell>"   Run a raw shell command on target(s).
  build-tar                Create a portable tarball of the project.
  build-rpm                Build an RPM (if rpmbuild is available).

Options:
  -a                Show About information and exit.
  -h                Show this help and exit.
  -C <dir>          Override CONFIG_DIR (default: $CONFIG_DIR).
  -m <N>            Set max parallel connections (default: $MAX_PROCS).
  -A                Prompt for SSH password (default on).
  -P <password>     Provide SSH password non-interactively (security risk).
  -i                Ignore unknown host keys (-i).
  -L <logdir>       Override log output directory.
  -t, --test        Dry-run for states (test=True). (Env alt: SSKR_TEST=1)

Examples:
  $(basename "$0") -t state 'web*' templates.install-package
  SSKR_TEST=1 $(basename "$0") state db1 templates.service-manage
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
for c in bash ssh tar awk sed grep printf date tee; do require_cmd "$c"; done

# Initial test mode (can be overridden by -t/--test)
TEST_MODE="${SSKR_TEST:-$TEST_MODE_DEFAULT}"

# Build base salt-ssh flags (others appended after option parsing)
salt_common_flags=(
  -c "$CONFIG_DIR"
  --roster-file "$ROSTER_FILE"
  --max-procs "$MAX_PROCS"
)

# Auth & host-key behavior (defaults)
if [[ "${PROMPT_PASSWORD}" -eq 1 ]]; then
  salt_common_flags+=(--askpass)
fi
if [[ "${IGNORE_UNKNOWN_HOST_KEYS}" -eq 1 ]]; then
  salt_common_flags+=(-i)
fi

# Parse top-level options (including -t/--test) before subcommand
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    -a) print_about; exit 0 ;;
    -h) print_help; exit 0 ;;
    -C) CONFIG_DIR="${2:-}"; shift 2 ;;
    -m) MAX_PROCS="${2:-}"; shift 2 ; salt_common_flags=( -c "$CONFIG_DIR" --roster-file "$ROSTER_FILE" --max-procs "$MAX_PROCS" );;
    -A) PROMPT_PASSWORD=1; salt_common_flags+=(--askpass); shift ;;
    -P) PROMPT_PASSWORD=0; PW_ARG=(--passwd "${2:-}"); shift 2 ;;
    -i) IGNORE_UNKNOWN_HOST_KEYS=1; salt_common_flags+=(-i); shift ;;
    -L) LOG_DIR="${2:-}"; mkdir -p "$LOG_DIR"; RAW_LOG="$LOG_DIR/$LOG_BASENAME_MAIN"; SSH_TRANSPORT_LOG="$LOG_DIR/$LOG_BASENAME_TRANSPORT"; shift 2 ;;
    -t|--test) TEST_MODE=1; shift ;;
    init|check|ping|state|cmd|build-tar|build-rpm) break ;;
    *) die "Unknown option: $1 (use -h)" ;;
  esac
done

sub="${1:-}"; [[ -n "${sub}" ]] && shift || true

need_core_paths() {
  [[ -d "$FILE_ROOTS_DIR" ]] || die "Missing file roots: $FILE_ROOTS_DIR"
  [[ -d "$PILLAR_ROOTS_DIR" ]] || die "Missing pillar roots: $PILLAR_ROOTS_DIR"
  [[ -f "$ROSTER_FILE"      ]] || die "Missing roster file: $ROSTER_FILE"
  [[ -f "$CONFIG_DIR/master" ]] || die "Missing master config: $CONFIG_DIR/master"
}

cmd_init() {
  log "Initializing project skeleton under: $PROJECT_DIR"
  mkdir -p "$FILE_ROOTS_DIR/templates" "$PILLAR_ROOTS_DIR" "$CONFIG_DIR" "tools" "SPECS" "vendor/salt/bin" "$CACHE_DIR" "$PROJECT_DIR/logs"

  # master config
  if [[ ! -f "$CONFIG_DIR/master" ]]; then
cat > "$CONFIG_DIR/master" <<EOF
# Portable Salt Shaker master config
ssh_log_file: $SSH_TRANSPORT_LOG

file_roots:
  base:
    - $FILE_ROOTS_DIR

pillar_roots:
  base:
    - $PILLAR_ROOTS_DIR

roster_file: $ROSTER_FILE
cachedir: $CACHE_DIR
EOF
    log "Wrote $CONFIG_DIR/master"
  else
    log "Keeping existing $CONFIG_DIR/master"
  fi

  # roster (no stored passwords by default)
  if [[ ! -f "$ROSTER_FILE" ]]; then
cat > "$ROSTER_FILE" <<'EOF'
# Salt Shaker roster (flat). Prefer interactive --askpass over storing passwords.
web1:
  host: 192.0.2.10
  user: root
  tty: True
  sudo: False

db1:
  host: 192.0.2.20
  user: root
  tty: True
  sudo: False
EOF
    log "Wrote $ROSTER_FILE"
  else
    log "Keeping existing $ROSTER_FILE"
  fi

  # states root
  [[ -f "$FILE_ROOTS_DIR/top.sls" ]] || cat > "$FILE_ROOTS_DIR/top.sls" <<'EOF'
base:
  '*':
    - init
EOF

  [[ -f "$FILE_ROOTS_DIR/init.sls" ]] || cat > "$FILE_ROOTS_DIR/init.sls" <<'EOF'
test.echo:
  - text: "Salt Shaker baseline state executed."
EOF

  # seed intuitive templates
  for tmpl in restart-host reset-password install-package service-manage run-command combo-task; do
    [[ -f "$FILE_ROOTS_DIR/templates/${tmpl}.sls" ]] && continue
    case "$tmpl" in
      restart-host)
cat > "$FILE_ROOTS_DIR/templates/restart-host.sls" <<'EOF'
{#=============================================================
  Salt State: restart-host.sls
  About: Safely restart a RHEL/CentOS host (6+).
  CONFIG BLOCK (edit values below or via pillar templates:restart:*)
==============================================================#}
{% set ENABLE_REBOOT = salt['pillar.get']('templates:restart:enable', True) %}
{% set REBOOT_MESSAGE = salt['pillar.get']('templates:restart:message', 'Reboot initiated by Salt Shaker') %}
{% set REBOOT_DELAY  = salt['pillar.get']('templates:restart:delay', 1) %}

restart_host_echo_intent:
  test.show_notification:
    - text: "Intent: system will reboot in {{ REBOOT_DELAY }} minute(s). Message: {{ REBOOT_MESSAGE }}"

{% if ENABLE_REBOOT %}
restart_host_now:
  cmd.run:
    - name: "/sbin/shutdown -r +{{ REBOOT_DELAY }} '{{ REBOOT_MESSAGE }}'"
{% else %}
restart_host_skip:
  test.show_notification:
    - text: "ENABLE_REBOOT is False: reboot skipped."
{% endif %}
EOF
      ;;
      reset-password)
cat > "$FILE_ROOTS_DIR/templates/reset-password.sls" <<'EOF'
{#=============================================================
  Salt State: reset-password.sls
  About: Reset a local user password using a SHA-512 hash (RHEL/CentOS).
  Create a hash on a secure box:
    python - <<'PY'
import crypt, getpass, os
pw = getpass.getpass('New password: ')
salt = '$6$' + os.urandom(8).hex()
print(crypt.crypt(pw, salt))
PY
  CONFIG BLOCK
==============================================================#}
{% set TARGET_USER       = salt['pillar.get']('templates:passwd:user', 'testuser') %}
{% set HASHED_PASSWORD   = salt['pillar.get']('templates:passwd:hash',  '$6$EXAMPLE$UseARealHashHere...') %}

ensure_user_present:
  user.present:
    - name: "{{ TARGET_USER }}"
    - createhome: True

set_password_hash:
  cmd.run:
    - name: "echo '{{ TARGET_USER }}:{{ HASHED_PASSWORD }}' | /usr/sbin/chpasswd -e"
    - require:
      - user: ensure_user_present

notify_done:
  test.show_notification:
    - text: "Password reset applied for {{ TARGET_USER }}."
EOF
      ;;
      install-package)
cat > "$FILE_ROOTS_DIR/templates/install-package.sls" <<'EOF'
{#=============================================================
  Salt State: install-package.sls
  About: Install one or more RPM packages (RHEL/CentOS 6+).
  CONFIG BLOCK
==============================================================#}
{% set PACKAGES = salt['pillar.get']('templates:pkg:names', ['vim-enhanced']) %}
{% set HOLD_REFRESH = salt['pillar.get']('templates:pkg:refresh', False) %}

install_selected_packages:
  pkg.installed:
    - pkgs: {{ PACKAGES }}
    - refresh: {{ HOLD_REFRESH|lower }}
    - failhard: True

notify_packages:
  test.show_notification:
    - text: "Ensured packages installed: {{ PACKAGES|join(', ') }}"
EOF
      ;;
      service-manage)
cat > "$FILE_ROOTS_DIR/templates/service-manage.sls" <<'EOF'
{#=============================================================
  Salt State: service-manage.sls
  About: Manage a service's running/enable state (RHEL/CentOS 6+).
  CONFIG BLOCK
==============================================================#}
{% set SERVICE_NAME = salt['pillar.get']('templates:svc:name', 'crond') %}
{% set ENABLE       = salt['pillar.get']('templates:svc:enable', True) %}
{% set RUNNING      = salt['pillar.get']('templates:svc:running', True) %}

service_manage_state:
  service.{{ 'running' if RUNNING else 'dead' }}:
    - name: "{{ SERVICE_NAME }}"
    - enable: {{ ENABLE|lower }}
    - failhard: True

notify_service:
  test.show_notification:
    - text: "Service {{ SERVICE_NAME }} set to running={{ RUNNING }}, enable={{ ENABLE }}."
EOF
      ;;
      run-command)
cat > "$FILE_ROOTS_DIR/templates/run-command.sls" <<'EOF'
{#=============================================================
  Salt State: run-command.sls
  About: Execute a one-off shell command (RHEL/CentOS 6+).
  CONFIG BLOCK
==============================================================#}
{% set SHELL_COMMAND = salt['pillar.get']('templates:cmd:command', 'echo Hello from Salt Shaker') %}
{% set RUN_IF        = salt['pillar.get']('templates:cmd:onlyif',   '') %}
{% set UNLESS        = salt['pillar.get']('templates:cmd:unless',   '') %}

run_arbitrary_command:
  cmd.run:
    - name: "{{ SHELL_COMMAND }}"
{% if RUN_IF %}
    - onlyif: "{{ RUN_IF }}"
{% endif %}
{% if UNLESS %}
    - unless: "{{ UNLESS }}"
{% endif %}

notify_cmd:
  test.show_notification:
    - text: "Command executed: {{ SHELL_COMMAND }}"
EOF
      ;;
      combo-task)
cat > "$FILE_ROOTS_DIR/templates/combo-task.sls" <<'EOF'
{#=============================================================
  Salt State: combo-task.sls
  About: Combine multiple template states into one orchestrated task.
  CONFIG BLOCK
==============================================================#}
{% set PKGS     = salt['pillar.get']('templates:combo:pkgs', ['vim-enhanced']) %}
{% set SVC_NAME = salt['pillar.get']('templates:combo:service', 'crond') %}
{% set CMD      = salt['pillar.get']('templates:combo:cmd', 'uname -a') %}

include:
  - templates.install-package
  - templates.service-manage
  - templates.run-command

extend:
  install_selected_packages:
    pkg.installed:
      - pkgs: {{ PKGS }}

  service_manage_state:
    service.running:
      - name: "{{ SVC_NAME }}"
      - enable: True

  run_arbitrary_command:
    cmd.run:
      - name: "{{ CMD }}"
      - require:
        - pkg: install_selected_packages
        - service: service_manage_state

combo_notify:
  test.show_notification:
    - text: "Combo done. Installed={{ PKGS|join(', ') }}, Service={{ SVC_NAME }}, Cmd='{{ CMD }}'"
EOF
      ;;
    esac
  done

  # pillar
  [[ -f "$PILLAR_ROOTS_DIR/top.sls" ]] || cat > "$PILLAR_ROOTS_DIR/top.sls" <<'EOF'
base:
  '*':
    - data
EOF

  [[ -f "$PILLAR_ROOTS_DIR/data.sls" ]] || cat > "$PILLAR_ROOTS_DIR/data.sls" <<'EOF'
# Example pillar data for templates:
templates:
  pkg:
    names: ['vim-enhanced','lsof']
  svc:
    name: 'crond'
    enable: true
    running: true
  cmd:
    command: 'cat /etc/redhat-release'
  restart:
    enable: false
    delay: 2
    message: 'Scheduled reboot from Salt Shaker'
  combo:
    pkgs: ['vim-enhanced','screen']
    service: 'crond'
    cmd: 'uname -r'
EOF

  log "Initialization complete."
}

cmd_check() {
  log "Validating environment and paths..."
  [[ -x "$SALT_SSH_BIN" ]] || die "salt-ssh not executable: $SALT_SSH_BIN"
  log "Project dir: $PROJECT_DIR"
  log "Config dir : $CONFIG_DIR"
  log "Roster file: $ROSTER_FILE"
  log "File roots : $FILE_ROOTS_DIR"
  log "Pillar root: $PILLAR_ROOTS_DIR"
  log "Cache dir  : $CACHE_DIR"
  log "Log dir    : $LOG_DIR"
  log "Main log   : $RAW_LOG"
  log "SSH log    : $SSH_TRANSPORT_LOG"
  "$SALT_SSH_BIN" --version || log "Warning: could not query salt-ssh version."
  log "OK"
}

cmd_ping() {
  need_core_paths
  local tgt="${1:-}"; [[ -n "$tgt" ]] || die "Usage: $(basename "$0") ping <target>"
  log "Pinging: $tgt"
  "$SALT_SSH_BIN" "${salt_common_flags[@]}" ${PW_ARG[@]:-} "$tgt" test.ping
}

cmd_state() {
  need_core_paths
  local tgt="${1:-}"; local st="${2:-}"
  [[ -n "$tgt" && -n "$st" ]] || die "Usage: $(basename "$0") state <target> <state>"
  log "Applying state '$st' to: $tgt  (dry-run: $TEST_MODE)"
  if [[ "${TEST_MODE}" -eq 1 ]]; then
    "$SALT_SSH_BIN" "${salt_common_flags[@]}" ${PW_ARG[@]:-} "$tgt" state.apply "$st" test=True
  else
    "$SALT_SSH_BIN" "${salt_common_flags[@]}" ${PW_ARG[@]:-} "$tgt" state.apply "$st"
  fi
}

cmd_cmd() {
  need_core_paths
  local tgt="${1:-}"; shift || true
  local raw="${1:-}"
  [[ -n "$tgt" && -n "$raw" ]] || die "Usage: $(basename "$0") cmd <target> \"<shell>\""
  log "Running raw shell on '$tgt': $raw"
  "$SALT_SSH_BIN" "${salt_common_flags[@]}" ${PW_ARG[@]:-} "$tgt" -r "$raw"
}

cmd_build_tar() {
  if [[ -x "$PROJECT_DIR/tools/build-tar.sh" ]]; then
    "$PROJECT_DIR/tools/build-tar.sh"
  else
    die "Missing tools/build-tar.sh"
  fi
}

cmd_build_rpm() {
  if [[ -x "$PROJECT_DIR/tools/build-rpm.sh" ]]; then
    "$PROJECT_DIR/tools/build-rpm.sh"
  else
    die "Missing tools/build-rpm.sh"
  fi
}

case "${sub:-}" in
  init)       cmd_init ;;
  check)      cmd_check ;;
  ping)       cmd_ping "$@" ;;
  state)      cmd_state "$@" ;;
  cmd)        cmd_cmd "$@" ;;
  build-tar)  cmd_build_tar ;;
  build-rpm)  cmd_build_rpm ;;
  ""|help|-h|--help) print_help ;;
  *) die "Unknown subcommand: $sub (use -h)" ;;
esac

