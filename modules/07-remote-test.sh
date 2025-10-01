#!/bin/bash
#===============================================================
#Script Name: 07-remote-test.sh
#Date: 10/01/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.8
#Short: Interactive salt-ssh connectivity test (CSV/manual + header fix)
#About: Tests salt-ssh reachability using project-local wrappers. Adds:
#       - On-screen "Fix CSV header now?" (repairs header only; preserves BOM/CRLF)
#       - Robust CSV parser for quoted fields and commas
#       Prints 'Cleanup: on/off' and uses -W -w when enabled. Project-local only.
#===============================================================

umask 077
set -euo pipefail

# ================== CONFIG (edit me) ==================
PROJECT_ROOT_DEFAULT=""           # auto-detect when empty
CSV_PATH_REL="roster/data/hosts-all-pods.csv"
CONF_DIR_REL="conf"
TMP_DIR_REL="tmp"
LOGS_DIR_REL="logs"

# Default wrapper preference (first found)
PREF_WRAPPERS="el8 el9 el7"

# Interactive defaults
ASK_FROM_CSV_DEFAULT="y"          # y|n
CLEANUP_DEFAULT="y"               # y|n
DEFAULT_PORT="22"
DEFAULT_USER="root"
DEFAULT_PLATFORM="el7"            # display only for manual mode
# =====================================================

# ---------- Colors/UI ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"
  C_RED="\033[31m"; C_GRN="\033[32m"; C_YLW="\033[33m"; C_CYN="\033[36m"
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GRN=""; C_YLW=""; C_CYN=""
fi
ICON_OK="${C_GRN}✓${C_RESET}"; ICON_ERR="${C_RED}✖${C_RESET}"; ICON_WARN="${C_YLW}!${C_RESET}"
ui_hr(){ printf '%b\n' "${C_CYN}──────────────────────────────────────────────────────────────${C_RESET}"; }
ui_title(){ ui_hr; printf '%b\n' "${C_BOLD}${C_GRN}SALT SHAKER${C_RESET} ${C_CYN}|${C_RESET} ${C_BOLD}Module 07 · Remote Test${C_RESET}"; ui_hr; }
ui_section(){ printf '%b\n' "${C_BOLD}$1${C_RESET}"; }
ui_kv(){ printf '%b\n' "  ${C_BOLD}$1${C_RESET}: $2"; }
ui_ok(){ printf '%b\n' "  ${ICON_OK} $1"; }
ui_err(){ printf '%b\n' "  ${ICON_ERR} $1"; }
ui_warn(){ printf '%b\n' "  ${ICON_WARN} $1"; }

stamp(){ date '+%Y-%m-%d %H:%M:%S'; }

# ---------- Project root detection ----------
RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || echo "$p"; else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd -P)" "$(basename -- "$p")" ); fi; }
DETECT_ROOT(){
  local d; d="$(dirname -- "$(RESOLVE_ABS "$0")")"; local i=6
  while [ "$i" -gt 0 ]; do
    if [ -d "$d/vendor" ] || [ -d "$d/modules" ] || [ -f "$d/salt-shaker.sh" ] || [ -f "$d/salt-shaker-el7.sh" ]; then
      echo "$d"; return 0
    fi
    d="$(dirname -- "$d")"; i=$((i-1))
  done
  pwd -P
}
PROJECT_ROOT="${PROJECT_ROOT_DEFAULT:-$(DETECT_ROOT)}"
CONF_DIR="${PROJECT_ROOT}/${CONF_DIR_REL}"
CSV_PATH="${PROJECT_ROOT}/${CSV_PATH_REL}"
TMP_DIR="${PROJECT_ROOT}/${TMP_DIR_REL}"
LOGS_DIR="${PROJECT_ROOT}/${LOGS_DIR_REL}"
mkdir -p "$TMP_DIR" "$LOGS_DIR" 2>/dev/null || true
chmod 700 "$TMP_DIR" "$LOGS_DIR" 2>/dev/null || true

# ---------- CLI ----------
SHOW_ABOUT=0; SHOW_HELP=0
FORCE_VENDOR_TEST=0
TARGETS_FROM_CSV=0
CLEANUP_CHOICE=""           # on|off
FIX_CSV_HEADER_FLAG=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) SHOW_HELP=1 ;;
    -a|--about) SHOW_ABOUT=1 ;;
    --force-vendor-test) FORCE_VENDOR_TEST=1 ;;
    --targets-from-csv) TARGETS_FROM_CSV=1 ;;
    --cleanup) shift || true; CLEANUP_CHOICE="${1:-}";;
    --fix-csv-header) FIX_CSV_HEADER_FLAG=1 ;;
    *) ui_err "Unknown option: $1"; SHOW_HELP=1 ;;
  esac
  shift || true
done

print_help(){
  ui_title
  ui_section "Usage"
  echo "  modules/07-remote-test.sh [--targets-from-csv] [--force-vendor-test]"
  echo "                             [--cleanup on|off] [--fix-csv-header]"
  ui_section "Notes"
  echo "  - Uses project-local wrappers; never writes outside the project."
  echo "  - 'Fix CSV header' rewrites the first line only (preserves BOM/CRLF)."
  echo "  - When cleanup is on, remote thin dirs are randomized and wiped (-W -w)."
  ui_hr
}
print_about(){
  ui_title
  ui_section "About"
  echo "Interactive salt-ssh test. Choose a CSV row or enter manually."
  echo "CSV header can be fixed in-place if Excel/edits broke it."
  ui_hr
}
[ "$SHOW_HELP" -eq 1 ] && { print_help; exit 0; }
[ "$SHOW_ABOUT" -eq 1 ] && { print_about; exit 0; }

# ---------- TTY prompts ----------
HAS_TTY=0; if [ -r /dev/tty ] && [ -w /dev/tty ]; then exec 3<> /dev/tty; HAS_TTY=1; fi
ask_yn(){ local q="$1" def="$2" ans=""; if [ "$HAS_TTY" -eq 1 ]; then /bin/echo -en "${C_BOLD}${q}${C_RESET} [${def}]: " >&3; IFS= read -r ans <&3 || ans=""; fi; [ -z "$ans" ] && ans="$def"; case "$ans" in y|Y) return 0;; *) return 1;; esac; }
ask_line(){ local q="$1" def="$2" ans=""; if [ "$HAS_TTY" -eq 1 ]; then /bin/echo -en "${C_BOLD}${q}${C_RESET} [${def}]: " >&3; IFS= read -r ans <&3 || ans=""; fi; [ -z "$ans" ] && ans="$def"; printf '%s' "$ans"; }

# ---------- Wrapper pick ----------
pick_wrapper(){
  local p
  for p in $PREF_WRAPPERS; do
    if [ -x "${PROJECT_ROOT}/bin/salt-ssh-${p}" ]; then echo "${PROJECT_ROOT}/bin/salt-ssh-${p}"; return 0; fi
  done
  for p in el8 el9 el7; do
    if [ -x "${PROJECT_ROOT}/vendor/${p}/salt/salt-ssh" ]; then echo "${PROJECT_ROOT}/vendor/${p}/salt/salt-ssh"; return 0; fi
  done
  command -v salt-ssh 2>/dev/null || true
}

# ---------- CSV header normalization / fix ----------
expected_header_raw='pod,platform,host,port,user,auth,sudo,python2_bin,ssh_args,minion_id,groups,notes'
normalize_header(){
  # $1: line (may include CR / quotes / mixed case)
  local line="$1" BOM=$'\357\273\277'
  line="${line#$BOM}"; line="${line//$'\r'/}"
  line="${line//\"/}"
  line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  line="${line//-/_}"
  line="${line//[[:space:]]/}"
  printf '%s' "$line"
}
header_ok(){
  [ -f "$CSV_PATH" ] || return 1
  local first; first="$(head -n1 "$CSV_PATH" 2>/dev/null || true)"
  [ -n "$first" ] || return 1
  [ "$(normalize_header "$first")" = "$expected_header_raw" ]
}
fix_csv_header_in_place(){
  [ -f "$CSV_PATH" ] || return 1
  local bom_has=0 eol_crlf=0
  local BOM3; BOM3="$(head -c 3 "$CSV_PATH" 2>/dev/null || true)"
  if [ "$BOM3" = $'\357\273\277' ]; then bom_has=1; fi
  local header1; header1="$(head -n1 "$CSV_PATH" 2>/dev/null || true)"
  case "$header1" in *$'\r') eol_crlf=1 ;; esac

  local tmp="${CSV_PATH}.tmp.$$"
  {
    if [ $bom_has -eq 1 ]; then printf '%b' "$BOM3"; fi
    printf '%s' "$expected_header_raw"
    if [ $eol_crlf -eq 1 ]; then printf '\r\n'; else printf '\n'; fi
    tail -n +2 "$CSV_PATH"
  } > "$tmp"

  local mode; mode="$(stat -c '%a' "$CSV_PATH" 2>/dev/null || echo '')"
  mv -f "$tmp" "$CSV_PATH"
  [ -n "$mode" ] && chmod "$mode" "$CSV_PATH" 2>/dev/null || true
  return 0
}

# ---------- CSV robust row parser ----------
SEP=$'\037'  # US separator
parse_csv_line(){
  # $1 line -> echo fields joined by $SEP
  awk -v S="$1" -v SEP="$SEP" '
  function emit(f) { if (out != "") out = out SEP; out = out f; }
  BEGIN{
    s=S; inq=0; f=""; out="";
    len=length(s);
    for (i=1; i<=len; i++) {
      c=substr(s,i,1);
      if (inq) {
        if (c=="\"") {
          if (i<len && substr(s,i+1,1)=="\"") { f=f "\""; i++; }
          else { inq=0; }
        } else { f=f c; }
      } else {
        if (c=="\"") { inq=1; }
        else if (c==",") { emit(f); f=""; }
        else { f=f c; }
      }
    }
    emit(f);
    print out;
  }'
}
csv_row_read(){
  local idx="$1" line joined
  line="$(tail -n +2 "$CSV_PATH" 2>/dev/null | sed '/^[[:space:]]*$/d' | sed -n "${idx}p" || true)" || true
  [ -n "$line" ] || return 1
  line="${line%$'\r'}"
  joined="$(parse_csv_line "$line")"
  IFS="$SEP" read -r pod platform host port user auth sudo py2 ssh_args minion groups notes <<<"$joined"
  CSV_POD="${pod:-}"; CSV_PLATFORM="${platform:-}"; CSV_HOST="${host:-}"
  CSV_PORT="${port:-}"; CSV_USER="${user:-}"; CSV_AUTH="${auth:-}"
  CSV_SUDO="${sudo:-}"; CSV_PY2="${py2:-}"; CSV_SSH_ARGS="${ssh_args:-}"
  CSV_MINION="${minion:-}"; CSV_GROUPS="${groups:-}"; CSV_NOTES="${notes:-}"
  return 0
}
csv_count_rows(){ tail -n +2 "$CSV_PATH" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | awk '{print $1}'; }

# ---------- Main ----------
ui_title
ui_section "Remote Test"
ui_kv "Project Root" "$PROJECT_ROOT"

# Decide CSV or manual
if [ "${TARGETS_FROM_CSV:-0}" -eq 1 ]; then
  use_csv=1
else
  if ask_yn "Load target from CSV?" "$ASK_FROM_CSV_DEFAULT"; then use_csv=1; else use_csv=0; fi
fi

target_host=""; target_user="$DEFAULT_USER"; target_port="$DEFAULT_PORT"
target_platform="$DEFAULT_PLATFORM"; target_minion_id=""
target_sudo="n"; target_auth="askpass"; target_notes=""

if [ "$use_csv" -eq 1 ]; then
  if ! header_ok; then
    ui_warn "CSV header mismatch detected."
    if [ "$FIX_CSV_HEADER_FLAG" -eq 1 ] || ask_yn "Fix CSV header in place now?" "y"; then
      if fix_csv_header_in_place && header_ok; then
        ui_ok "CSV header fixed."
      else
        ui_err "CSV header could not be fixed automatically."
        exit 2
      fi
    else
      ui_err "CSV header mismatch or file missing. Run module 02 to normalize."
      exit 2
    fi
  fi

  count="$(csv_count_rows)"
  if [ "$count" -lt 1 ]; then ui_err "CSV has no data rows."; exit 2; fi

  echo "Select a target from CSV:"
  printf '%s\n' "  Id  Platform  Host                      User   Port  Sudo  MinionId"
  printf '%s\n' "  --  --------  ------------------------  -----  ----  ----  ----------------"
  i=1
  while [ $i -le "$count" ]; do
    csv_row_read "$i" || { i=$((i+1)); continue; }
    printf '  %-2s  %-8s  %-24s  %-5s  %-4s  %-4s  %s\n' \
      "$i" "${CSV_PLATFORM}" "${CSV_HOST}" "${CSV_USER}" "${CSV_PORT}" "${CSV_SUDO}" "${CSV_MINION}"
    i=$((i+1))
  done
  idx="$(ask_line "Enter index" "")"
  [ -z "$idx" ] && { ui_err "No selection."; exit 2; }
  csv_row_read "$idx" || { ui_err "Invalid selection."; exit 2; }

  target_host="$CSV_HOST"; target_user="$CSV_USER"; target_port="${CSV_PORT:-$DEFAULT_PORT}"
  target_platform="$CSV_PLATFORM"; target_minion_id="${CSV_MINION:-$CSV_HOST}"
  target_sudo="$CSV_SUDO"; target_auth="$CSV_AUTH"; target_notes="$CSV_NOTES"
else
  target_host="$(ask_line "Target host/IP" "")"
  target_user="$(ask_line "SSH username" "$DEFAULT_USER")"
  target_port="$(ask_line "SSH port" "$DEFAULT_PORT")"
  target_platform="$DEFAULT_PLATFORM"
  target_minion_id="$target_host"
  target_sudo="n"
  target_auth="askpass"
fi

# Cleanup decision
cleanup="on"
if [ -n "$CLEANUP_CHOICE" ]; then
  case "$CLEANUP_CHOICE" in on|ON|On) cleanup="on" ;; off|OFF|Off) cleanup="off" ;; esac
else
  if ask_yn "Force cleanup of remote thin (recommended)?" "$CLEANUP_DEFAULT"; then cleanup="on"; else cleanup="off"; fi
fi

# Build temp roster for this single run
ts="$(date +%Y%m%d-%H%M%S).$$.$RANDOM"
ROSTER_FILE="${TMP_DIR}/remote-test.${ts}.roster.yaml"
{
  echo "${target_minion_id}:"
  echo "  host: ${target_host}"
  echo "  user: ${target_user}"
  echo "  port: ${target_port}"
  if [ "$target_sudo" = "y" ] || [ "$target_sudo" = "Y" ]; then
    echo "  sudo: True"
    echo "  tty: True"
  else
    echo "  sudo: False"
    echo "  tty: False"
  fi
} > "$ROSTER_FILE"
chmod 600 "$ROSTER_FILE" 2>/dev/null || true

# Wrapper pick & logging
pick_wrapper(){
  local p
  for p in $PREF_WRAPPERS; do
    if [ -x "${PROJECT_ROOT}/bin/salt-ssh-${p}" ]; then echo "${PROJECT_ROOT}/bin/salt-ssh-${p}"; return 0; fi
  done
  for p in el8 el9 el7; do
    if [ -x "${PROJECT_ROOT}/vendor/${p}/salt/salt-ssh" ]; then echo "${PROJECT_ROOT}/vendor/${p}/salt/salt-ssh"; return 0; fi
  done
  command -v salt-ssh 2>/dev/null || true
}
WRAPPER="$(pick_wrapper)"
[ -n "${WRAPPER:-}" ] || { ui_err "salt-ssh wrapper not found (bin/salt-ssh-el7|el8|el9)."; exit 2; }
SSH_LOG="${LOGS_DIR}/ssh-$(date +%Y%m%d-%H%M%S).log"

# Auth flags
ASKPASS_FLAG=()
case "$target_auth" in
  askpass|password|passwd|pass) ASKPASS_FLAG=( --askpass ) ;;
  *) ASKPASS_FLAG=() ;;
esac

# Cleanup handling for wrappers vs direct salt-ssh
IS_WRAPPER=0
case "$WRAPPER" in */bin/salt-ssh-*) IS_WRAPPER=1 ;; esac
COMMON_ARGS=( --config-dir "$CONF_DIR" --roster-file "$ROSTER_FILE" )
EXTRA_CLEANUP_ARGS=()
if [ $IS_WRAPPER -eq 0 ] && [ "$cleanup" = "on" ]; then EXTRA_CLEANUP_ARGS=( -W -w ); fi
if [ $IS_WRAPPER -eq 1 ]; then
  if [ "$cleanup" = "on" ]; then export SALT_SSH_CLEANUP=1; else export SALT_SSH_CLEANUP=0; fi
fi

ui_kv "Wrapper" "$(basename "$WRAPPER")"
ui_kv "Platform" "$target_platform"
ui_kv "Target"   "${target_user}@${target_host}:${target_port}"
ui_kv "Sudo/TTY" "$( [ "$target_sudo" = "y" ] || [ "$target_sudo" = "Y" ] && echo true/true || echo false/false )"
ui_kv "Cleanup"  "$cleanup"
ui_kv "Roster"   "$ROSTER_FILE"
ui_kv "SSH Log"  "$SSH_LOG"
ui_hr

# --- test.ping ---
printf '%b' "• test.ping ... "
set +e
"$WRAPPER" "${COMMON_ARGS[@]}" "${EXTRA_CLEANUP_ARGS[@]}" \
  "${ASKPASS_FLAG[@]}" -l quiet "$target_minion_id" test.ping 2>&1 | tee "$SSH_LOG"
rc1=${PIPESTATUS[0]}
set -e
if [ $rc1 -eq 0 ]; then echo -e "${ICON_OK} test.ping"; else echo -e "${ICON_ERR} test.ping"; fi

# --- grains.item osfinger pythonversion ---
printf '%b' "• grains.item osfinger pythonversion ... "
set +e
"$WRAPPER" "${COMMON_ARGS[@]}" "${EXTRA_CLEANUP_ARGS[@]}" \
  "${ASKPASS_FLAG[@]}" -l quiet "$target_minion_id" grains.item osfinger pythonversion 2>&1 | tee -a "$SSH_LOG"
rc2=${PIPESTATUS[0]}
set -e
if [ $rc2 -eq 0 ]; then echo -e "${ICON_OK} grains.item"; else echo -e "${ICON_ERR} grains.item"; fi

ok=0
if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]; then ok=1; fi

if [ $ok -eq 1 ]; then
  ui_ok "Remote test PASSED"
  ui_hr; printf '%b\n' "${C_BOLD}${C_GRN}✓ Done${C_RESET}"; ui_hr; exit 0
else
  ui_warn "Remote test FAILED"
  echo "Hints"
  echo "  - Run module 02 if header mismatch persists."
  echo "  - Verify credentials and password auth on server."
  echo "  - EL7: ensure remote python exists (/usr/bin/python)."
  echo "  - Sudo requires TTY and password; we set both when enabled."
  echo "  - Check ${SSH_LOG} for full trace."
  ui_hr; exit 2
fi

