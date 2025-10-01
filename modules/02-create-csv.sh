#!/bin/bash
#===============================================================
# Script Name: modules/02-create-csv.sh
# Date: 10/01/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 2.1
# Short: Interactive, Excel-friendly roster CSV builder (with pods)
# About:
#   - Generates/updates a roster CSV teammates can edit in Excel.
#   - Adds required POD field to segment systems by pod.
#   - Minimal interactive wizard; EL7-safe Bash.
#   - Default output: roster/data/hosts-all-pods.csv
#   - Fields feed module 07 and future module 08 (generate-configs).
#   - All logs/artifacts stay inside the project root.
#===============================================================

set -e

#-------------------------------
# Config (edit if you like)
#-------------------------------
DEFAULT_CSV="roster/data/hosts-all-pods.csv"
LOG_REL="logs/salt-shaker.log"

DEFAULT_POD="pod-01"
DEFAULT_PLATFORM="el8"
DEFAULT_PORT="22"
DEFAULT_USER="root"
DEFAULT_AUTH="askpass"        # askpass|key|none
DEFAULT_SUDO="n"              # y/n (stored as true/false)
DEFAULT_PY2_BIN="/usr/bin/python"  # only relevant for el7 targets
DEFAULT_SSH_ARGS=""           # wrappers auto-tune, leave blank unless needed
DEFAULT_GROUPS=""             # if blank, we’ll default to POD
DEFAULT_CRLF="n"              # y/n
DEFAULT_HEADER_YES="y"        # include header when creating new
CSV_DELIM=","                 # Excel-friendly default

HEADER="pod,platform,host,port,user,auth,sudo,python2_bin,ssh_args,minion_id,groups,notes"

#-------------------------------
# Bootstrap: resolve PROJECT_ROOT
#-------------------------------
RESOLVE_ABS() {
  local p="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || echo "$p"
  else
    ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" )
  fi
}

SCRIPT_PATH="$(RESOLVE_ABS "$0")"
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"

if [ -n "${SALT_SHAKER_ROOT:-}" ]; then
  PROJECT_ROOT="${SALT_SHAKER_ROOT}"
elif [ -f "${SCRIPT_DIR}/../salt-shaker.sh" ] || [ -d "${SCRIPT_DIR}/../modules" ]; then
  PROJECT_ROOT="$(RESOLVE_ABS "${SCRIPT_DIR}/..")"
else
  PROJECT_ROOT="$(pwd)"
fi

LOG_FILE="${PROJECT_ROOT}/${LOG_REL}"
OUT_FILE_DEFAULT="${PROJECT_ROOT}/${DEFAULT_CSV}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

#-------------------------------
# Colors (TTY only)
#-------------------------------
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; WHITE=""; NC=""
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [02-create-csv] $*" >> "$LOG_FILE"; }
say() { echo -e "$*"; }
bar() { say "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"; }

#-------------------------------
# Help / About
#-------------------------------
show_help() {
cat <<EOF
${WHITE}02-create-csv.sh${NC} — interactive, Excel-friendly roster CSV builder (with pods)

Usage:
  ${0##*/} [--path DIR] [--dry-run] [--stdout] [-h|--help] [-a|--about]

Options:
  --path DIR   : Use DIR as project root (default: auto-detected)
  --dry-run    : Show what would be written; no file changes
  --stdout     : Print the CSV rows you'd add (no file changes)
  -h, --help   : This help
  -a, --about  : About this script

Default output:
  ${DEFAULT_CSV}

Header:
  ${HEADER}
EOF
}

show_about() {
  sed -n '1,120p' "$0" | sed -n '/^# About:/,/^#====/p' | sed '1 s/^# About: //; s/^# //'
}

#-------------------------------
# Parse args
#-------------------------------
DRY_RUN=0
STDOUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --path) shift; [ -n "${1:-}" ] || { say "${RED}Missing DIR for --path${NC}"; exit 1; }
            PROJECT_ROOT="$(RESOLVE_ABS "$1")"
            OUT_FILE_DEFAULT="${PROJECT_ROOT}/${DEFAULT_CSV}"
            LOG_FILE="${PROJECT_ROOT}/${LOG_REL}"
            ;;
    --dry-run) DRY_RUN=1;;
    --stdout) STDOUT=1;;
    -h|--help) show_help; exit 0;;
    -a|--about) show_about; exit 0;;
    *) say "${YELLOW}Ignoring unknown argument:${NC} $1";;
  esac
  shift
done

[ -d "$PROJECT_ROOT" ] || { say "${RED}Project root not found:${NC} $PROJECT_ROOT"; exit 1; }

# Ensure output dir exists
mkdir -p "${PROJECT_ROOT}/roster/data" 2>/dev/null || true
mkdir -p "${PROJECT_ROOT}/tmp" 2>/dev/null || true

#-------------------------------
# Prompt helpers (EL7-safe)
#-------------------------------
ask_dflt() { # $1=prompt  $2=default
  local ans
  printf "%s [%s]: " "$1" "$2"
  IFS= read -r ans
  [ -z "$ans" ] && ans="$2"
  echo "$ans"
}

ask_yesno() { # $1=prompt  $2=default(y/n)
  local def="$2" ans
  while true; do
    printf "%s (y/n) [%s]: " "$1" "$def"
    IFS= read -r ans
    [ -z "$ans" ] && ans="$def"
    case "$ans" in
      y|Y) echo "y"; return 0;;
      n|N) echo "n"; return 0;;
    esac
    say "${YELLOW}Please enter y or n.${NC}"
  done
}

validate_platform() {
  case "$1" in el7|el8|el9) return 0;; esac
  return 1
}
validate_port() {
  [ -n "$1" ] && [ "$1" -eq "$1" ] 2>/dev/null && [ "$1" -gt 0 ] && [ "$1" -le 65535 ]
}
validate_host() {
  case "$1" in
    *[!a-zA-Z0-9._-]*|"") return 1;;
    *) return 0;;
  esac
}

maybe_quote() { # quote if contains delimiter or space or quotes
  case "$1" in
    *"$CSV_DELIM"*|*" "*|*\"*|*$'\t'*)
      local esc="${1//\"/\"\"}"
      printf "\"%s\"" "$esc"
      ;;
    *) printf "%s" "$1";;
  esac
}

#-------------------------------
# Title
#-------------------------------
bar
say "▶ ${WHITE}Create Roster CSV (with pods)${NC}"
say "Project Root: ${PROJECT_ROOT}"
bar

# Output path
OUT_FILE="$(ask_dflt "Output CSV path" "$OUT_FILE_DEFAULT")"
OUT_FILE="$(RESOLVE_ABS "$OUT_FILE")"

# New file: header?
WRITE_HEADER="n"
if [ ! -f "$OUT_FILE" ]; then
  WRITE_HEADER="$(ask_yesno "CSV does not exist. Write header row?" "$DEFAULT_HEADER_YES")"
else
  say "${GREEN}✓ Using existing CSV:${NC} ${OUT_FILE}"
fi

# Append or overwrite?
MODE="append"
if [ -f "$OUT_FILE" ]; then
  local_choice="$(ask_dflt "Append or overwrite? (append/overwrite)" "append")"
  case "$local_choice" in
    overwrite|OVERWRITE) MODE="overwrite";;
    *) MODE="append";;
  esac
fi

# Excel CRLF lines?
CRLF="$(ask_yesno "Use Excel CRLF line endings" "$DEFAULT_CRLF")"

# Delimiter (keep comma for Excel)
CSV_DELIM="$(ask_dflt "CSV delimiter" ",")"

#-------------------------------
# Row entry loop
#-------------------------------
say
bar
say "${WHITE}Enter hosts (Ctrl+C to stop at any time)${NC}"

ROWBUF=""
COUNT_ADDED=0

while true; do
  say
  say "${CYAN}— New system —${NC}"

  pod="$(ask_dflt "Pod name" "$DEFAULT_POD")"
  [ -n "$pod" ] || { say "${RED}Pod cannot be empty. Skipping entry.${NC}"; continue; }

  plat="$(ask_dflt "Platform (el7/el8/el9)" "$DEFAULT_PLATFORM")"
  validate_platform "$plat" || { say "${YELLOW}Using default:${NC} $DEFAULT_PLATFORM"; plat="$DEFAULT_PLATFORM"; }

  host="$(ask_dflt "Host or IP" "")"
  if ! validate_host "$host"; then
    say "${RED}Invalid host. Skipping entry.${NC}"
    continue
  fi

  port="$(ask_dflt "SSH port" "$DEFAULT_PORT")"
  validate_port "$port" || { say "${YELLOW}Using default port:${NC} $DEFAULT_PORT"; port="$DEFAULT_PORT"; }

  user="$(ask_dflt "SSH user" "$DEFAULT_USER")"

  auth="$(ask_dflt "Auth (askpass/key/none)" "$DEFAULT_AUTH")"
  case "$auth" in askpass|key|none) : ;; *) auth="$DEFAULT_AUTH";; esac

  sudo_ans="$(ask_yesno "Use sudo for commands" "$DEFAULT_SUDO")"
  [ "$sudo_ans" = "y" ] && sudo_flag="true" || sudo_flag="false"

  py2="$(ask_dflt "Python2 path (el7 targets) [blank ok]" "$DEFAULT_PY2_BIN")"
  [ "$plat" != "el7" ] && py2=""

  sshargs="$(ask_dflt "Extra ssh_args [blank ok]" "$DEFAULT_SSH_ARGS")"
  mid="$(ask_dflt "Minion ID [blank ok]" "")"

  groups_guess="$DEFAULT_GROUPS"
  [ -z "$groups_guess" ] && groups_guess="$pod"
  groups="$(ask_dflt "Groups (comma-separated) [default: pod]" "$groups_guess")"

  notes="$(ask_dflt "Notes [blank ok]" "")"

  # Build CSV line
  line="$(maybe_quote "$pod")${CSV_DELIM}$(maybe_quote "$plat")${CSV_DELIM}$(maybe_quote "$host")${CSV_DELIM}$(maybe_quote "$port")${CSV_DELIM}$(maybe_quote "$user")${CSV_DELIM}$(maybe_quote "$auth")${CSV_DELIM}$(maybe_quote "$sudo_flag")${CSV_DELIM}$(maybe_quote "$py2")${CSV_DELIM}$(maybe_quote "$sshargs")${CSV_DELIM}$(maybe_quote "$mid")${CSV_DELIM}$(maybe_quote "$groups")${CSV_DELIM}$(maybe_quote "$notes")"

  if [ -z "$ROWBUF" ]; then ROWBUF="$line"; else ROWBUF="${ROWBUF}
${line}"; fi
  COUNT_ADDED=$((COUNT_ADDED+1))

  cont="$(ask_yesno "Add another host" "y")"
  [ "$cont" = "y" ] || break
done

say
bar

# Nothing to add?
if [ -z "$ROWBUF" ]; then
  say "${YELLOW}No rows to write. Nothing changed.${NC}"
  exit 0
fi

TMPFILE="$(mktemp "${PROJECT_ROOT}/tmp/create-csv.$$XXXXXXXX" 2>/dev/null || echo "${PROJECT_ROOT}/tmp/create-csv.$$")"

if [ "$MODE" = "overwrite" ]; then
  : > "$TMPFILE"
  [ "$WRITE_HEADER" = "y" ] && echo "$HEADER" >> "$TMPFILE"
  echo "$ROWBUF" >> "$TMPFILE"
else
  : > "$TMPFILE"
  if [ ! -f "$OUT_FILE" ]; then
    [ "$WRITE_HEADER" = "y" ] && echo "$HEADER" >> "$TMPFILE"
    echo "$ROWBUF" >> "$TMPFILE"
  else
    cat "$OUT_FILE" >> "$TMPFILE"
    echo "$ROWBUF" >> "$TMPFILE"
  fi
fi

# CRLF for Excel?
if [ "$CRLF" = "y" ]; then
  if command -v unix2dos >/dev/null 2>&1; then
    unix2dos "$TMPFILE" >/dev/null 2>&1 || true
  else
    sed -i 's/$/\r/' "$TMPFILE"
  fi
fi

# Dry-run / stdout
if [ $STDOUT -eq 1 ]; then
  say "${CYAN}— CSV (stdout) —${NC}"
  cat "$TMPFILE"
  rm -f "$TMPFILE"
  exit 0
fi

if [ $DRY_RUN -eq 1 ]; then
  say "${YELLOW}DRY-RUN:${NC} would write ${COUNT_ADDED} row(s) to ${OUT_FILE}"
  rm -f "$TMPFILE"
  exit 0
fi

# Ensure parent dir exists and write
mkdir -p "$(dirname "$OUT_FILE")" 2>/dev/null || true
mv -f "$TMPFILE" "$OUT_FILE"
log "Wrote ${COUNT_ADDED} row(s) → ${OUT_FILE}"

# Summary
say "${GREEN}✓ CSV updated:${NC} ${OUT_FILE}"
say "${CYAN}Rows added:${NC} ${COUNT_ADDED}"
say
say "${WHITE}Tip:${NC} Column order:"
say "  ${HEADER}"
say "Module 08 can group by pod or by groups (which defaults to your pod)."
say
exit 0

