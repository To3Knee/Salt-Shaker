#!/bin/bash
#===============================================================
#Script Name: 07-remote-test.sh
#Date: 09/29/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.2
#Short: Wizard/CLI remote smoke test via salt-ssh
#About: Builds a temp config & roster, auto-picks controller wrapper,
#About: wires EL7-friendly options (ssh_ext_alternatives 2019.2.3,
#About: python2-bin), uses project .cache, and runs test.ping and
#About: grains.item osfinger pythonversion. EL7-safe Bash.
#===============================================================

set -e -o pipefail
LC_ALL=C

# Colors
if [ -t 1 ]; then G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; C='\033[0;36m'; N='\033[0m'; else G="";Y="";R="";C="";N=""; fi
ok(){ printf -- "%b✓ %s%b\n" "$G" "$*" "$N"; }
warn(){ printf -- "%b⚠ %s%b\n" "$Y" "$*" "$N"; }
err(){ printf -- "%b✖ %s%b\n" "$R" "$*" "$N"; }
info(){ printf -- "%b%s%b\n" "$C" "$*" "$N"; }
bar(){ printf -- "%b%s%b\n" "$C" "══════════════════════════════════════════════════════════════════════" "$N"; }

# Root detection
RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || ( cd "$(dirname -- "$p")" && printf -- "%s/%s" "$(pwd)" "$(basename -- "$p")" ); else ( cd "$(dirname -- "$p")" && printf -- "%s/%s" "$(pwd)" "$(basename -- "$p")" ); fi; }
FIND_ROOT_UP(){ local d="$1" i=8; while [ "$i" -gt 0 ] && [ -n "$d" ] && [ "$d" != "/" ]; do if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then echo "$d"; return 0; fi; d="$(dirname -- "$d")"; i=$((i-1)); done; return 1; }
SCRIPT_ABS="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_ABS")"
if [ -n "${SALT_SHAKER_ROOT:-}" ] && [ -d "${SALT_SHAKER_ROOT}" ]; then PROJECT_ROOT="$(RESOLVE_ABS "$SALT_SHAKER_ROOT")"; else PROJECT_ROOT="$(FIND_ROOT_UP "$SCRIPT_DIR" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(FIND_ROOT_UP "$(pwd)" || true)"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(RESOLVE_ABS "$(pwd)")"; fi
short(){ printf -- "%s" "$1" | sed "s#^${PROJECT_ROOT}/##"; }

LOG_DIR="${PROJECT_ROOT}/logs"; mkdir -p "$LOG_DIR" 2>/dev/null || true
MAIN_LOG="${LOG_DIR}/salt-shaker.log"; ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
BIN_DIR="${PROJECT_ROOT}/bin"
CACHE_DIR="${PROJECT_ROOT}/.cache/salt-ssh"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

logi(){ printf -- "[%s] [INFO] %s\n" "$(date +'%F %T')" "$*" >>"$MAIN_LOG" 2>/dev/null || true; }
loge(){ printf -- "[%s] [ERROR] %s\n" "$(date +'%F %T')" "$*" | tee -a "$ERROR_LOG" >>"$MAIN_LOG" 2>/dev/null || true; }

# Defaults
PLAT=""; HOST=""; USER="root"; PORT="22"; SUDO=0; ASKPASS=0; SSHARGS=""; VERBOSE=0
TIMEOUT="30"; PY3_BIN="/usr/bin/python3"; PY2_BIN="/usr/bin/python"
FUNC1="test.ping"; FUNC2="grains.item osfinger pythonversion"
FORCE_WRAPPER=""
NONINTERACTIVE=0

usage(){
cat <<EOF
Usage: modules/07-remote-test.sh [options]
  -t, --target {el7|el8|el9}   Target platform hint
  -H, --host HOST              Target host/IP (accepts host:port)
  -u, --user USER              SSH username (default: root)
  -p, --port PORT              SSH port (default: 22)
  --sudo                       Use sudo with tty
  --ask-pass                   Add --askpass (password prompt by salt-ssh)
  --ssh-args "OPTS"            Extra ssh options
  --timeout SEC                Timeout (default: 30)
  --python3-bin PATH           For el8/9 targets (default: /usr/bin/python3)
  --python2-bin PATH           For el7 targets (default: /usr/bin/python)
  -w, --wrapper NAME           Force wrapper (salt-ssh-el7|salt-ssh-el8)
  -v, --verbose                Show command invoked
  -y, --yes                    Non-interactive; use provided flags
  -h, --help                   This help

Wizard: If flags omitted, prompts for platform, host, username, and auth mode.
EOF
}

# Parse CLI
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--target) shift; PLAT="$1";;
    -H|--host) shift; HOST="$1";;
    -u|--user) shift; USER="$1";;
    -p|--port) shift; PORT="$1";;
    --sudo) SUDO=1;;
    --ask-pass) ASKPASS=1;;
    --ssh-args) shift; SSHARGS="$1";;
    --timeout) shift; TIMEOUT="$1";;
    --python3-bin) shift; PY3_BIN="$1";;
    --python2-bin) shift; PY2_BIN="$1";;
    -w|--wrapper) shift; FORCE_WRAPPER="$1";;
    -v|--verbose) VERBOSE=1;;
    -y|--yes) NONINTERACTIVE=1;;
    -h|--help) usage; exit 0;;
  esac; shift || true
done

bar; info "▶ Remote Test"; info "Project Root : ${PROJECT_ROOT}"

# --- Wizard with robust defaults & sanitization ---
if [ "$NONINTERACTIVE" -eq 0 ]; then
  # Platform (default el7 if blank)
  printf -- "Target platform (el7/el8/el9) [el7]: "
  read -r ans || true
  [ -z "$ans" ] && ans="el7"
  case "$ans" in
    el7|EL7) PLAT="el7";;
    el8|EL8) PLAT="el8";;
    el9|EL9) PLAT="el9";;
    *) warn "Invalid platform '$ans', using el7"; PLAT="el7";;
  esac

  # Host/IP (sanitize control chars like ^H; allow host:port)
  printf -- "Target host/IP: "
  read -r raw || true
  # strip non-printables
  clean="$(printf "%s" "$raw" | tr -cd '[:print:]')"
  # allow alnum, dot, dash, colon, underscore (underscore for some envs)
  clean="$(printf "%s" "$clean" | sed 's/[^A-Za-z0-9._:-]//g')"
  if [ -n "$raw" ] && [ "$clean" != "$raw" ]; then
    warn "Sanitized host input: '$raw' → '$clean'"
  fi
  HOST="$clean"
  # Extract :port if provided
  if printf "%s" "$HOST" | grep -q ':'; then
    hp_host="$(printf "%s" "$HOST" | cut -d: -f1)"
    hp_port="$(printf "%s" "$HOST" | cut -d: -f2)"
    if printf "%s" "$hp_port" | grep -Eq '^[0-9]+$'; then
      HOST="$hp_host"; PORT="$hp_port"
    fi
  fi

  # Username (default root)
  printf -- "SSH username [root]: "
  read -r ans || true
  [ -n "$ans" ] && USER="$ans"

  # Sudo prompt
  printf -- "Use sudo? (y/N): "
  read -r ans || true
  case "${ans,,}" in y|yes) SUDO=1;; *) :;; esac

  # Askpass prompt (default Yes)
  printf -- "Password auth (--askpass)? (Y/n): "
  read -r ans || true
  case "${ans,,}" in n|no) ASKPASS=0;; *) ASKPASS=1;; esac
fi

# Validate final inputs, set default platform if still blank
[ -z "$PLAT" ] && PLAT="el7"
case "$PLAT" in el7|el8|el9) : ;; *) err "Invalid --target '$PLAT'"; exit 1;; esac
[ -z "$HOST" ] && { err "Missing --host"; exit 1; }

# Pick wrapper (controller) — prefer el8, then el9, else el7; allow override; use el7 wrapper for el7 targets if present
WRAPPER=""
if [ -n "$FORCE_WRAPPER" ]; then
  WRAPPER="$FORCE_WRAPPER"
else
  if [ "$PLAT" = "el7" ] && [ -x "${BIN_DIR}/salt-ssh-el7" ]; then WRAPPER="salt-ssh-el7"
  elif [ -x "${BIN_DIR}/salt-ssh-el8" ]; then WRAPPER="salt-ssh-el8"
  elif [ -x "${BIN_DIR}/salt-ssh-el9" ]; then WRAPPER="salt-ssh-el9"
  else WRAPPER="salt-ssh-el7"
  fi
fi
[ ! -x "${BIN_DIR}/${WRAPPER}" ] && { err "Wrapper not found: $(short "${BIN_DIR}/${WRAPPER}")"; exit 2; }

info "Wrapper      : $(short "${BIN_DIR}/${WRAPPER}")"
info "Platform     : ${PLAT}"
info "Target       : ${USER}@${HOST}:${PORT}"
info "Sudo/TTY     : $([ "$SUDO" -eq 1 ] && echo true || echo false)/true"

# Temp conf + roster
TS="$(date +%Y%m%d_%H%M%S)"
CONF_TMP="${PROJECT_ROOT}/tmp/rt-${TS}"
mkdir -p "${CONF_TMP}" "${PROJECT_ROOT}/roster" 2>/dev/null || true

# Minimal persistent roster/hosts.yml if missing
if [ ! -f "${PROJECT_ROOT}/roster/hosts.yml" ]; then
  cat > "${PROJECT_ROOT}/roster/hosts.yml" <<'YAML'
# roster/hosts.yml (auto-created)
# Example host entry (edit and reuse for bulk runs)
example:
  host: 192.0.2.10
  user: root
  port: 22
  sudo: False
  tty: True
YAML
  ok "Created template: $(short "${PROJECT_ROOT}/roster/hosts.yml")"
fi

# Master config (controller)
MASTER="${CONF_TMP}/master"
mkdir -p "${CONF_TMP}" 2>/dev/null || true
{
  echo "cachedir: ${CACHE_DIR}"
  echo "ssh_config: True"
  echo "roster: flat"
  echo "roster_file: ${CONF_TMP}/roster"
  echo "ssh_max_procs: 10"
  echo "ssh_wipe: True"
  echo "thin_dir: /tmp/.salt-thin"
  if [ "$PLAT" = "el7" ]; then
    echo "ssh_ext_alternatives: 2019.2.3"
  fi
} > "$MASTER"

# Roster for this run
ROSTER="${CONF_TMP}/roster"
{
  echo "target:"
  echo "  host: ${HOST}"
  echo "  user: ${USER}"
  echo "  port: ${PORT}"
  echo "  tty: True"
  echo "  sudo: $([ "$SUDO" -eq 1 ] && echo True || echo False)"
} > "$ROSTER"

# Build salt-ssh command
CMD=("${BIN_DIR}/${WRAPPER}" "-c" "$CONF_TMP" "-i" "-t" "$TIMEOUT" "-w" "2" "target")
[ "$ASKPASS" -eq 1 ] && CMD+=("--askpass")
[ -n "$SSHARGS" ] && CMD+=("--ssh-option" "$SSHARGS")
case "$PLAT" in
  el7) CMD+=("--python2-bin" "$PY2_BIN");;
  el8|el9) CMD+=("--python3-bin" "$PY3_BIN");;
esac

bar
printf -- "• %s ... " "$FUNC1"
if [ "$VERBOSE" -eq 1 ]; then echo; printf "  "; printf -- "%q " "${CMD[@]}" "$FUNC1"; echo; fi
if "${CMD[@]}" "$FUNC1" >/dev/null 2>>"$ERROR_LOG"; then ok "$FUNC1"; T1=0; else err "$FUNC1"; T1=1; fi

printf -- "• %s ... " "$FUNC2"
if [ "$VERBOSE" -eq 1 ]; then echo; printf "  "; printf -- "%q " "${CMD[@]}" $FUNC2; echo; fi
if "${CMD[@]}" $FUNC2 >/dev/null 2>>"$ERROR_LOG"; then ok "$FUNC2"; T2=0; else warn "$FUNC2"; T2=1; fi

if [ $T1 -eq 0 ] && [ $T2 -eq 0 ]; then
  ok "Remote test PASSED"
  exit 0
elif [ $T1 -eq 0 ]; then
  warn "Remote test PARTIAL (grains failed/warned)"
  exit 1
else
  err "Remote test FAILED"
  exit 2
fi

