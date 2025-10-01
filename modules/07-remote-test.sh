#!/bin/bash
#===============================================================
#Script Name: 07-remote-test.sh
#Date: 10/01/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.8
#Short: Salt-SSH remote connectivity smoke test (CSV + vendor override)
#About: Lets you choose a target from roster/data/hosts-all-pods.csv or enter it
#       manually. On-screen option to force the local vendor tree (el7/el8/el9)
#       used for salt-ssh regardless of target platform. After run, warns if the
#       declared platform (CSV/manual) mismatches the remote osmajorrelease.
#       Uses password-only SSH, disables host-key writes, and forces a fresh
#       Salt Thin (-W -w -t). All artifacts remain in the project folder.
#===============================================================

umask 077

# ---------- Colors / UI ----------
if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"
  C_RED="\033[31m"; C_GRN="\033[32m"; C_YLW="\033[33m"; C_BLU="\033[34m"; C_CYN="\033[36m"; C_MAG="\033[35m"
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_CYN=""; C_MAG=""
fi
ICON_OK="${C_GRN}✓${C_RESET}"
ICON_WARN="${C_YLW}!${C_RESET}"
ICON_ERR="${C_RED}✖${C_RESET}"
ui_hr()      { printf '%b\n' "${C_CYN}──────────────────────────────────────────────────────────────${C_RESET}"; }
ui_title()   { ui_hr; printf '%b\n' "${C_BOLD}${C_GRN}SALT SHAKER${C_RESET} ${C_CYN}|${C_RESET} ${C_BOLD}Module 07 · Remote Test${C_RESET}"; ui_hr; }
ui_section() { printf '%b\n' "${C_BOLD}${1}${C_RESET}"; }
ui_kv()      { printf '%b\n' "  ${C_BOLD}$1${C_RESET}: $2"; }
ui_ok()      { printf '%b\n' "  ${ICON_OK} $1"; }
ui_warn()    { printf '%b\n' "  ${ICON_WARN} $1"; }
ui_err()     { printf '%b\n' "  ${ICON_ERR} $1"; }

# ---------- Module constants ----------
MODULE_NAME="07-remote-test.sh"
CANON_HEADER='pod,platform,host,port,user,auth,sudo,python2_bin,ssh_args,minion_id,groups,notes'

# ---------- Defaults / CLI ----------
PLATFORM="el7"          # target platform label (CSV/manual)
HOST=""
USER="root"
PORT="22"
USE_SUDO="n"
LOG_LEVEL="info"
PY2_BIN="/usr/bin/python"
MINION_ID=""
PROJECT_ROOT=""
CSV_PICK=0
CSV_PATH=""
CSV_INDEX=""
NON_INTERACTIVE=0
FORCE_VENDOR=""         # optional override: el7|el8|el9
START_TS=$(date +%s)
RUN_TS=$(date +%Y%m%d-%H%M%S)

# Salt-SSH hardening flags:
SSH_FLAGS_COMMON="--no-host-keys --identities-only"
THIN_FLAGS="-W -w -t"   # rand-thin-dir + wipe + regen-thin

# ---------- Logging (project-only) ----------
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
LOG_FILE=""
TMP_ROSTER=""
GR_TMP=""
log_init_done=0
log_init() {
  [ $log_init_done -eq 1 ] && return 0
  [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
  mkdir -p "${PROJECT_ROOT}/logs" 2>/dev/null
  chmod 700 "${PROJECT_ROOT}/logs" 2>/dev/null
  LOG_FILE="${PROJECT_ROOT}/logs/salt-shaker.log"
  log_init_done=1
}
log()  { log_init; printf '%s [%s] (%s) %s\n' "$(stamp)" "$1" "$MODULE_NAME" "$2" | tee -a "$LOG_FILE" >/dev/null; }
info() { log "INFO"  "$1"; }
warn() { log "WARN"  "$1"; }
error(){ log "ERROR" "$1"; }

# ---------- Temp (project-only) ----------
mk_local_tmpfile() {
  mkdir -p "${PROJECT_ROOT}/tmp" 2>/dev/null
  chmod 700 "${PROJECT_ROOT}/tmp" 2>/dev/null
  local f="${PROJECT_ROOT}/tmp/remote-test.${RUN_TS}.$$.$RANDOM.roster.yaml"
  : > "$f" || { error "Failed to create temp roster in project tmp"; exit 1; }
  TMP_ROSTER="$f"
  echo "$f"
}
mk_grains_tmpfile() {
  mkdir -p "${PROJECT_ROOT}/tmp" 2>/dev/null
  chmod 700 "${PROJECT_ROOT}/tmp" 2>/dev/null
  local f="${PROJECT_ROOT}/tmp/remote-test.${RUN_TS}.$$.$RANDOM.grains.txt"
  : > "$f" || { error "Failed to create grains temp file"; exit 1; }
  GR_TMP="$f"
  echo "$f"
}

# ---------- TTY helpers ----------
HAS_TTY=0
open_tty() {
  if [ -r /dev/tty ] && [ -w /dev/tty ] ; then exec 3<> /dev/tty; HAS_TTY=1; else HAS_TTY=0; fi
}
close_tty() { [ "$HAS_TTY" -eq 1 ] && exec 3<&- 3>&-; }
prompt_tty() {
  # $1 prompt, $2 default, $3 "req"
  local p="$1"; local d="$2"; local req="$3"; local ans=""
  if [ "$HAS_TTY" -eq 1 ] && [ $NON_INTERACTIVE -eq 0 ]; then
    /bin/echo -en "${C_BOLD}${p}${C_RESET} [${d}]: " >&3
    IFS= read -r ans <&3; [ -z "$ans" ] && ans="$d"
  else
    ans="$d"
  fi
  if [ -z "$ans" ] && [ "$req" = "req" ]; then ui_err "$p is required. Supply via CLI."; exit 2; fi
  echo "$ans"
}

# ---------- CSV helpers (BOM-safe) ----------
csv_list_rows() {
  sed $'1s/^\xEF\xBB\xBF//' "$1" | awk -v max="$2" -v hdr="$CANON_HEADER" '
    BEGIN{ FPAT="([^,]*)|(\"[^\"]*\")"; row=0; }
    NR==1 { line=$0; sub(/\r$/,"",line); if(line!=hdr){ print "HEADER_MISMATCH"; exit 0 } next }
    { n=NF; if(n<12) next
      for(i=1;i<=12;i++){ gsub(/^[ \t]+|[ \t]+$/, "", $i); if($i ~ /^\".*\"$/){ sub(/^\"/,"",$i); sub(/\"$/,"",$i) } }
      row++; if(row<=max){ printf("%d\t%s\t%s\t%s\t%s\t%s\t%s\n", row, $2, $3, $5, $4, $7, ($10==""?$3:$10)); }
    }'
}
csv_get_row() {
  sed $'1s/^\xEF\xBB\xBF//' "$1" | awk -v idx="$2" -v hdr="$CANON_HEADER" '
    BEGIN{ FPAT="([^,]*)|(\"[^\"]*\")"; row=0; found=0 }
    NR==1 { line=$0; sub(/\r$/,"",line); if(line!=hdr){ print "HEADER_MISMATCH"; exit 0 } next }
    { n=NF; if(n<12) next
      for(i=1;i<=12;i++){ gsub(/^[ \t]+|[ \t]+$/, "", $i); if($i ~ /^\".*\"$/){ sub(/^\"/,"",$i); sub(/\"$/,"",$i) } }
      row++; if(row==idx){ for(i=1;i<=12;i++){ printf("%s%s",$i,(i<12?"\t":"\n")) } found=1; exit 0 }
    }'
}
emit_ssh_options_from_args() {
  RAW="$1"; [ -z "$RAW" ] && return 0
  JUMP="$(printf '%s\n' "$RAW" | sed -n 's/.*-J[[:space:]]\+\([^[:space:]]\+\).*/\1/p' | head -n1)"
  [ -n "$JUMP" ] && echo "    - ProxyJump ${JUMP}"
  printf '%s\n' "$RAW" | tr ' ' '\n' | awk '/^-o/ { s=$0; sub(/^-o/,"",s); if(s!=""){ print "    - " s } }'
}

# ---------- Help / About ----------
print_help() {
  ui_title; ui_section "Usage"; echo "  $MODULE_NAME [options]"; echo
  ui_section "Options"
  echo "  -h, --help                Show help"
  echo "  -a, --about               About module"
  echo "  -d, --dir <path>          Project root override"
  echo "  -p, --platform <elX>      Target platform label (el7|el8|el9) [el7]"
  echo "  -t, --host <host/ip>      Target host or IP"
  echo "  -u, --user <name>         SSH username [root]"
  echo "  -P, --port <num>          SSH port [22]"
  echo "  -S, --sudo <y|n>          Use sudo [n]"
  echo "  -i, --id <minion_id>      Minion id (default: host)"
  echo "  -L, --log-level <lvl>     info|debug [info]"
  echo "      --python2-bin <p>     EL7 remote python path [/usr/bin/python]"
  echo "      --non-interactive     No prompts; fail if missing args"
  echo "      --targets-from-csv    Pick row from roster CSV (also auto-prompted)"
  echo "      --csv <path>          CSV path (default: roster/data/hosts-all-pods.csv)"
  echo "      --index <N>           CSV row index (1-based, excluding header)"
  echo "      --force-vendor <elX>  Force local vendor used (el7|el8|el9)"
  ui_hr
}
print_about() {
  ui_title; ui_section "About"
  echo "Portable salt-ssh smoke test. Choose from CSV or enter manually."
  echo "You can also force which local vendor tree is used for salt-ssh."
  ui_hr
}

# ---------- CLI parsing ----------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help; exit 0 ;;
    -a|--about) print_about; exit 0 ;;
    -d|--dir) shift; PROJECT_ROOT="$1" ;;
    -p|--platform) shift; PLATFORM="$1" ;;
    -t|--host) shift; HOST="$1" ;;
    -u|--user) shift; USER="$1" ;;
    -P|--port) shift; PORT="$1" ;;
    -S|--sudo) shift; USE_SUDO="$1" ;;
    -i|--id) shift; MINION_ID="$1" ;;
    -L|--log-level) shift; LOG_LEVEL="$1" ;;
    --python2-bin) shift; PY2_BIN="$1" ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    --targets-from-csv) CSV_PICK=1 ;;
    --csv) shift; CSV_PATH="$1" ;;
    --index) shift; CSV_INDEX="$1" ;;
    --force-vendor) shift; FORCE_VENDOR="$1" ;;
    *) warn "Unknown argument: $1"; print_help; exit 2 ;;
  esac; shift
done

# ---------- Project root ----------
if [ -z "$PROJECT_ROOT" ]; then
  THIS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  PARENT="$(cd "$THIS_DIR/.." 2>/dev/null && pwd)"
  if [ -d "$PARENT/modules" ] && [ -d "$PARENT/offline" ]; then PROJECT_ROOT="$PARENT"; else PROJECT_ROOT="$(pwd)"; fi
fi
log_init; open_tty

# ---------- Title ----------
ui_title; ui_section "Remote Test"; printf "Project Root : %s\n" "$PROJECT_ROOT"

# ---------- Offer CSV picker (interactive) ----------
if [ $NON_INTERACTIVE -eq 0 ] && [ $CSV_PICK -eq 0 ] && [ "$HAS_TTY" -eq 1 ]; then
  CHOICE="$(prompt_tty 'Load target from CSV? (Y/n)' 'Y')"
  case "$CHOICE" in n|N) CSV_PICK=0 ;; *) CSV_PICK=1 ;; esac
fi

# ---------- CSV selection ----------
if [ $CSV_PICK -eq 1 ]; then
  [ -n "$CSV_PATH" ] || CSV_PATH="${PROJECT_ROOT}/roster/data/hosts-all-pods.csv"
  if [ ! -f "$CSV_PATH" ]; then ui_warn "CSV not found: $CSV_PATH — using manual prompts"; CSV_PICK=0; fi
fi
if [ $CSV_PICK -eq 1 ]; then
  if [ -z "$CSV_INDEX" ] && [ "$HAS_TTY" -eq 1 ] && [ $NON_INTERACTIVE -eq 0 ]; then
    /bin/echo -e "${C_BOLD}Select a target from CSV:${C_RESET}" >&3
    LIST="$(csv_list_rows "$CSV_PATH" 50)"
    if echo "$LIST" | head -n1 | grep -q '^HEADER_MISMATCH'; then ui_err "CSV header mismatch. Run module 02."; exit 2; fi
    printf "%b\n" "  Id  Platform  Host               User   Port  Sudo  MinionId"
    printf "%b\n" "  --  --------  -----------------  -----  ----  ----  --------"
    echo "$LIST" | while IFS=$'\t' read -r idx plat host user port sudo mid; do
      printf "  %-3s %-8s %-18s %-6s %-5s %-5s %s\n" "$idx" "$plat" "$host" "$user" "$port" "$sudo" "$mid"
    done
    CSV_INDEX="$(prompt_tty 'Enter index' '' 'req')"
  fi
  ROW="$(csv_get_row "$CSV_PATH" "$CSV_INDEX")"
  if printf '%s' "$ROW" | grep -q '^HEADER_MISMATCH'; then ui_err "CSV header mismatch. Run module 02."; exit 2; fi
  [ -n "$ROW" ] || { ui_err "Index not found in CSV: $CSV_INDEX"; exit 2; }
  POD="$(printf '%s' "$ROW" | awk -F'\t' '{print $1}')"
  PLATFORM="$(printf '%s' "$ROW" | awk -F'\t' '{print $2}')"
  HOST="$(printf '%s' "$ROW" | awk -F'\t' '{print $3}')"
  PORT="$(printf '%s' "$ROW" | awk -F'\t' '{print $4}')"
  USER="$(printf '%s' "$ROW" | awk -F'\t' '{print $5}')"
  AUTHMODE="$(printf '%s' "$ROW" | awk -F'\t' '{print $6}')"
  SUDOFLAG="$(printf '%s' "$ROW" | awk -F'\t' '{print $7}')"
  PY2_BIN_CSV="$(printf '%s' "$ROW" | awk -F'\t' '{print $8}')"
  SSH_ARGS_CSV="$(printf '%s' "$ROW" | awk -F'\t' '{print $9}')"
  MINION_ID_CSV="$(printf '%s' "$ROW" | awk -F'\t' '{print $10}')"
  [ -z "$PORT" ] && PORT="22"; [ -z "$USER" ] && USER="root"
  if [ "$SUDOFLAG" = "y" ] || [ "$SUDOFLAG" = "Y" ]; then USE_SUDO="y"; else USE_SUDO="n"; fi
  [ -n "$MINION_ID_CSV" ] && MINION_ID="$MINION_ID_CSV"
  if [ "$PLATFORM" = "el7" ] && [ -n "$PY2_BIN_CSV" ]; then PY2_BIN="$PY2_BIN_CSV"; fi
fi

# ---------- Manual prompts ----------
if [ $CSV_PICK -eq 0 ]; then
  case "$PLATFORM" in el7|el8|el9) : ;; *) PLATFORM="$(prompt_tty 'Target platform (el7/el8/el9)' 'el7' 'req')";; esac
  [ -n "$HOST" ] || HOST="$(prompt_tty 'Target host/IP' '' 'req')"
  USER="$(prompt_tty 'SSH username' "$USER")"
  PORT="$(prompt_tty 'SSH port' "$PORT")"
  if [ "$USE_SUDO" != "y" ] && [ "$USE_SUDO" != "n" ]; then USE_SUDO="$(prompt_tty 'Use sudo? (y/N)' 'n')"; fi
fi

# ---------- On-screen vendor override ----------
if [ $NON_INTERACTIVE -eq 0 ] && [ "$HAS_TTY" -eq 1 ] && [ -z "$FORCE_VENDOR" ]; then
  VCHOICE="$(prompt_tty 'Force local vendor (n/el7/el8/el9)' 'n')"
  case "$VCHOICE" in el7|el8|el9) FORCE_VENDOR="$VCHOICE" ;; *) FORCE_VENDOR="" ;; esac
fi
VENDOR_PLAT="${FORCE_VENDOR:-$PLATFORM}"

# ---------- Resolve salt-ssh binary ----------
VENDOR_DIR="${PROJECT_ROOT}/vendor/${VENDOR_PLAT}"
SSSH_BIN="${VENDOR_DIR}/bin/salt-ssh"
if [ ! -x "$SSSH_BIN" ] && [ -x "${PROJECT_ROOT}/bin/salt-ssh-${VENDOR_PLAT}" ]; then
  SSSH_BIN="${PROJECT_ROOT}/bin/salt-ssh-${VENDOR_PLAT}"
fi
[ -x "$SSSH_BIN" ] || { ui_err "salt-ssh not found for local vendor ${VENDOR_PLAT}. Run module 04."; exit 2; }

# ---------- Portable env ----------
export PATH="${VENDOR_DIR}/bin:${PATH}"
export PYTHONHOME="${VENDOR_DIR}"
if [ -d "${VENDOR_DIR}/lib" ]; then export LD_LIBRARY_PATH="${VENDOR_DIR}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; fi

# ---------- Compose flags ----------
SUDO_FLAG=""; [ "$USE_SUDO" = "y" ] && SUDO_FLAG="--sudo"
[ -z "$MINION_ID" ] && MINION_ID="$HOST"
LOG_RUN_FILE="${PROJECT_ROOT}/logs/ssh-${RUN_TS}.log"

# ---------- Build temp roster ----------
TMP_ROSTER="$(mk_local_tmpfile)"
{
  echo "${MINION_ID}:"
  echo "  host: ${HOST}"
  echo "  user: ${USER}"
  echo "  port: ${PORT}"
  if [ "$USE_SUDO" = "y" ]; then echo "  sudo: True"; echo "  tty: True"; else echo "  sudo: False"; echo "  tty: False"; fi
  echo "  ignore_host_keys: True"
  echo "  ssh_options:"
  echo "    - PreferredAuthentications=password"
  echo "    - PasswordAuthentication=yes"
  echo "    - PubkeyAuthentication=no"
  echo "    - KbdInteractiveAuthentication=no"
  echo "    - GSSAPIAuthentication=no"
  echo "    - IdentitiesOnly=yes"
  echo "    - NumberOfPasswordPrompts=1"
  echo "    - StrictHostKeyChecking=no"
  echo "    - UserKnownHostsFile=/dev/null"
  if [ $CSV_PICK -eq 1 ] && [ -n "$SSH_ARGS_CSV" ]; then emit_ssh_options_from_args "$SSH_ARGS_CSV"; fi
  if [ "$PLATFORM" = "el7" ]; then echo "  python2_bin: ${PY2_BIN}"; fi
} >> "$TMP_ROSTER"

# ---------- Preflight ----------
ui_kv "Wrapper"     "$(basename "$SSSH_BIN")"
ui_kv "Platform"    "$PLATFORM"
ui_kv "Vendor Local" "$VENDOR_PLAT"
ui_kv "Target"      "${USER}@${HOST}:${PORT}"
ui_kv "Sudo/TTY"    "$( [ "$USE_SUDO" = "y" ] && echo true || echo false )/$( [ "$USE_SUDO" = "y" ] && echo true || echo false )"
ui_kv "Roster"      "$TMP_ROSTER"
ui_kv "SSH Log"     "$LOG_RUN_FILE"
ui_hr

# ---------- Execute tests ----------
printf '• test.ping ... '
"$SSSH_BIN" \
  $SSH_FLAGS_COMMON \
  $THIN_FLAGS \
  --roster=flat \
  --roster-file "$TMP_ROSTER" \
  --askpass \
  $SUDO_FLAG \
  -l "$LOG_LEVEL" \
  --log-file "$LOG_RUN_FILE" \
  "$MINION_ID" test.ping
TP_RC=$?
[ $TP_RC -eq 0 ] && printf '%b\n' "${ICON_OK} test.ping" || printf '%b\n' "${ICON_ERR} test.ping"

# Capture grains for post-run analysis
GR_TMP="$(mk_grains_tmpfile)"
printf '• grains.item osfinger osmajorrelease pythonversion ... '
"$SSSH_BIN" \
  $SSH_FLAGS_COMMON \
  $THIN_FLAGS \
  --roster=flat \
  --roster-file "$TMP_ROSTER" \
  --askpass \
  $SUDO_FLAG \
  -l "$LOG_LEVEL" \
  --log-file "$LOG_RUN_FILE" \
  "$MINION_ID" grains.item osfinger osmajorrelease pythonversion | tee "$GR_TMP"
GR_RC=${PIPESTATUS[0]}
[ $GR_RC -eq 0 ] && printf '%b\n' "${ICON_OK} grains.item" || printf '%b\n' "${ICON_WARN} grains.item"

# ---------- Parse grains for mismatch warning ----------
parse_grain_val() {
  # $1 file, $2 key -> prints first scalar value following "key:"
  awk -v key="$2" '
    BEGIN{show=0}
    { sub(/\r$/,"",$0) }
    $1 ~ key":" { show=1; next }
    show==1 && $0 ~ /^[[:space:]]*[^[:space:]]/ { s=$0; sub(/^[[:space:]]+/,"",s); print s; exit }
  ' "$1"
}
REMOTE_OSFINGER="$(parse_grain_val "$GR_TMP" "osfinger")"
REMOTE_OSMAJOR="$(parse_grain_val "$GR_TMP" "osmajorrelease")"
# Fallback: derive major from osfinger if osmajorrelease empty
if [ -z "$REMOTE_OSMAJOR" ] && [ -n "$REMOTE_OSFINGER" ]; then
  REMOTE_OSMAJOR="$(printf '%s' "$REMOTE_OSFINGER" | grep -o '[0-9]\+' | head -n1)"
fi
# Expected major from declared platform
case "$PLATFORM" in el7) EXPECT_MAJOR="7" ;; el8) EXPECT_MAJOR="8" ;; el9) EXPECT_MAJOR="9" ;; *) EXPECT_MAJOR="" ;; esac

if [ -n "$EXPECT_MAJOR" ] && [ -n "$REMOTE_OSMAJOR" ] && [ "$EXPECT_MAJOR" != "$REMOTE_OSMAJOR" ]; then
  ui_warn "Platform mismatch: declared ${PLATFORM} (expect ${EXPECT_MAJOR}) vs remote ${REMOTE_OSFINGER:-unknown} (major ${REMOTE_OSMAJOR})."
  ui_warn "Local vendor used: ${VENDOR_PLAT}. If incorrect, rerun and force vendor accordingly."
fi

# ---------- Final status ----------
if [ $TP_RC -eq 0 ] && [ $GR_RC -eq 0 ]; then
  ui_ok "Remote test PASSED"
  ui_hr; printf '%b\n' "${C_BOLD}${C_GRN}✓ Done${C_RESET}"; ui_hr
  exit 0
fi

ui_err "Remote test FAILED"
ui_section "Hints"
echo "  - Check ${LOG_RUN_FILE} for full trace."
echo "  - Verify password and server PasswordAuthentication policy."
echo "  - EL7: ensure remote python exists (${PY2_BIN})."
echo "  - You can force the local vendor via on-screen prompt or --force-vendor."
ui_hr
printf '%b\n' "${C_BOLD}${C_RED}✗ Module 07 - remote-test execution failed${C_RESET}"
ui_hr
[ $TP_RC -ne 0 ] && exit 2 || exit 3

