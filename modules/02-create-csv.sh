#!/bin/bash
#===============================================================
#Script Name: 02-create-csv.sh
#Date: 10/01/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.8
#Short: Generate roster CSV template
#About: Creates/repairs roster/data/hosts-all-pods.csv with a canonical header.
#       New files default to UTF-8 BOM + CRLF (Excel-friendly). Existing files
#       preserve encoding unless normalization is explicitly requested.
#       Adds --validate to check per-row correctness. 100% portable: all logs/
#       temp/artifacts stay inside the project folder (EL7/EL8/EL9-safe).
#===============================================================

umask 077

# ---------- Colors / UI (EL7-safe, auto-disable if not a TTY) ----------
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
ui_title()   { ui_hr; printf '%b\n' "${C_BOLD}${C_GRN}SALT SHAKER${C_RESET} ${C_CYN}|${C_RESET} ${C_BOLD}Module 02 · Create CSV${C_RESET}"; ui_hr; }
ui_section() { printf '%b\n' "${C_BOLD}${1}${C_RESET}"; }
ui_kv()      { printf '%b\n' "  ${C_BOLD}$1${C_RESET}: $2"; }
ui_ok()      { printf '%b\n' "  ${ICON_OK} $1"; }
ui_warn()    { printf '%b\n' "  ${ICON_WARN} $1"; }
ui_err()     { printf '%b\n' "  ${ICON_ERR} $1"; }

# ---------- Module constants ----------
MODULE_NAME="02-create-csv.sh"
CSV_NAME="hosts-all-pods.csv"             # mandatory hyphenated naming
LEGACY_UNDERSCORE_NAME="hosts_all_pods.csv"
CANON_HEADER='pod,platform,host,port,user,auth,sudo,python2_bin,ssh_args,minion_id,groups,notes'
SAMPLE_EL7='pod-01,el7,el7-host,22,root,askpass,y,/usr/bin/python,,"minion-el7-01","linux,legacy","example el7 target"'
SAMPLE_EL8='pod-01,el8,el8-host,22,root,askpass,y,,,"minion-el8-01","linux","example el8 target"'

# ---------- Defaults ----------
PROJECT_ROOT=""
OUTFILE=""
ADD_SAMPLE=0
FORCE=0
VALIDATE=0
# New files default to Excel-friendly encoding
DEFAULT_BOM_NEW=1
DEFAULT_CRLF_NEW=1
# Existing files normalization (only when explicitly requested)
EXPLICIT_EOL=0
SET_BOM=0
SET_CRLF=0
DEFAULT_POD="pod-01"
START_TS=$(date +%s)

# ---------- Logging (project-only) ----------
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
LOG_FILE=""
TMP_FILE=""  # tracked temp for cleanup
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
mk_local_tmp() {
  mkdir -p "${PROJECT_ROOT}/tmp" 2>/dev/null
  chmod 700 "${PROJECT_ROOT}/tmp" 2>/dev/null
  local ts="$(date +%Y%m%d-%H%M%S)"
  local f="${PROJECT_ROOT}/tmp/${MODULE_NAME}.${ts}.$$.$RANDOM.tmp"
  : > "$f" || { error "Failed to create temp file in project tmp"; exit 1; }
  TMP_FILE="$f"
  echo "$f"
}

# ---------- Traps ----------
on_exit() {
  local rc=$?
  [ -n "$TMP_FILE" ] && [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE"
  local end_ts; end_ts=$(date +%s); local dur=$(( end_ts - START_TS ))
  if [ $rc -eq 0 ]; then info "Completed successfully in ${dur}s"; else error "Exited with code ${rc} after ${dur}s"; fi
  exit $rc
}
on_err() { local rc=$?; error "An error occurred (rc=${rc}). Use --force to repair header or rerun with -h."; exit $rc; }
trap on_exit EXIT
trap on_err ERR
trap 'warn "Interrupted by user"; exit 130' INT TERM

# ---------- Help / About ----------
print_about() {
  ui_title
  ui_section "About"
  echo "Creates or repairs the roster CSV used to generate a Salt-SSH roster."
  echo "File: roster/data/${CSV_NAME} (hyphenated naming is mandatory)."
  echo "New files: Excel-friendly UTF-8 BOM + CRLF by default."
  echo "Existing files: preserved unless you pass --normalize-excel or --unix."
  echo "--validate: checks platform/port/sudo and required fields; errors => non-zero exit."
  ui_hr
}
print_help() {
  ui_title
  ui_section "Usage"
  echo "  $MODULE_NAME [options]"
  echo
  ui_section "Options"
  echo "  -h, --help             Show help"
  echo "  -a, --about            Show about"
  echo "  -o, --out <file>       Override output CSV path"
  echo "  -p, --pod <name>       Set pod for sample rows (default: ${DEFAULT_POD})"
  echo "  -d, --dir <path>       Override project root directory"
  echo "      --add-sample       Append sample rows if header already exists"
  echo "      --force            Rewrite mismatched header (rows preserved; backup created)"
  echo "      --validate         Validate rows (platform/port/sudo/required fields)"
  echo
  echo "  Encoding/EOL control (existing files only unless creating new):"
  echo "      --normalize-excel, --excel   Force UTF-8 BOM + CRLF"
  echo "      --unix | --unix-eol          Force LF, no BOM"
  echo "      --crlf                       Force CRLF (keep BOM as-is)"
  echo "      --no-bom                     Remove BOM (keep EOL as-is)"
  ui_hr
}

# ---------- CLI (EL7-safe) ----------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help; exit 0 ;;
    -a|--about) print_about; exit 0 ;;
    -o|--out) shift; OUTFILE="$1" ;;
    -p|--pod) shift; DEFAULT_POD="$1" ;;
    -d|--dir) shift; PROJECT_ROOT="$1" ;;
    --add-sample) ADD_SAMPLE=1 ;;
    --force) FORCE=1 ;;
    --validate) VALIDATE=1 ;;
    --normalize-excel|--excel) EXPLICIT_EOL=1; SET_BOM=1; SET_CRLF=1 ;;
    --unix|--unix-eol) EXPLICIT_EOL=1; SET_BOM=0; SET_CRLF=0 ;;
    --crlf) EXPLICIT_EOL=1; SET_CRLF=1 ;;
    --no-bom) EXPLICIT_EOL=1; SET_BOM=0 ;;
    *) warn "Unknown argument: $1"; print_help; exit 2 ;;
  esac
  shift
done

# ---------- Project root detection ----------
if [ -z "$PROJECT_ROOT" ]; then
  THIS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  PARENT="$(cd "$THIS_DIR/.." 2>/dev/null && pwd)"
  if [ -d "$PARENT/modules" ] && [ -d "$PARENT/offline" ]; then PROJECT_ROOT="$PARENT"; else PROJECT_ROOT="$(pwd)"; fi
fi

log_init
ui_title
printf '%b\n' "${C_BOLD}${C_GRN}>> ${MODULE_NAME}:${C_RESET} ${C_BOLD}Generate roster CSV template${C_RESET}"

# ---------- Paths (project-only) ----------
ROSTER_DIR="${PROJECT_ROOT}/roster/data"
TARGET_CSV="${ROSTER_DIR}/${CSV_NAME}"
LEGACY_CSV="${ROSTER_DIR}/${LEGACY_UNDERSCORE_NAME}"

# ---------- Ensure dirs + perms ----------
mkdir -p "$ROSTER_DIR" 2>/dev/null
chmod 700 "${PROJECT_ROOT}/roster" 2>/dev/null
chmod 700 "$ROSTER_DIR" 2>/dev/null

# ---------- Optional override path ----------
if [ -n "$OUTFILE" ]; then
  TARGET_CSV="$OUTFILE"
  OUTDIR="$(dirname "$TARGET_CSV")"
  mkdir -p "$OUTDIR" 2>/dev/null
  chmod 700 "$OUTDIR" 2>/dev/null
fi

# ---------- Enforce hyphenated naming ----------
if [ -f "$LEGACY_CSV" ] && [ ! -f "$TARGET_CSV" ]; then
  info "Migrating legacy underscore CSV to hyphenated name"
  mv "$LEGACY_CSV" "$TARGET_CSV"
elif [ -f "$LEGACY_CSV" ] && [ -f "$TARGET_CSV" ]; then
  TS=$(date +%Y%m%d-%H%M%S)
  warn "Both underscore and hyphen CSV exist; backing up underscore file"
  mv "$LEGACY_CSV" "${LEGACY_CSV}.bak-${TS}"
fi

# ---------- Prepare sample rows with chosen pod ----------
SAMPLE_EL7_ROW=$(printf '%s\n' "$SAMPLE_EL7" | sed "s/^pod-01/${DEFAULT_POD}/")
SAMPLE_EL8_ROW=$(printf '%s\n' "$SAMPLE_EL8" | sed "s/^pod-01/${DEFAULT_POD}/")

# ---------- EOL/BOM helpers ----------
detect_file_crlf() { grep -q $'\r$' "$1" >/dev/null 2>&1; }
normalize_to_lf()  { local src="$1"; local t="$(mk_local_tmp)"; sed 's/\r$//' "$src" > "$t"; mv "$t" "$src"; TMP_FILE=""; }
strip_bom()        { local src="$1"; local t="$(mk_local_tmp)"; sed $'1s/^\xEF\xBB\xBF//' "$src" > "$t"; mv "$t" "$src"; TMP_FILE=""; }
add_bom()          { local src="$1"; local t="$(mk_local_tmp)"; printf '\xEF\xBB\xBF' > "$t"; cat "$src" >> "$t"; mv "$t" "$src"; TMP_FILE=""; }
to_crlf()          { local src="$1"; local t="$(mk_local_tmp)"; sed 's/$/\r/' "$src" > "$t"; mv "$t" "$src"; TMP_FILE=""; }
has_bom()          { head -c 3 "$1" 2>/dev/null | od -An -t x1 | awk '{print tolower($0)}' | grep -q "ef bb bf"; }

write_csv_file_new() {
  local tmpf="$1"
  : > "$tmpf"
  printf '%s\n' "$CANON_HEADER" >> "$tmpf"
  printf '%s\n' "$SAMPLE_EL7_ROW" >> "$tmpf"
  printf '%s\n' "$SAMPLE_EL8_ROW" >> "$tmpf"
}

rewrite_header_preserve_rows() {
  local src="$1"; local t="$(mk_local_tmp)"
  : > "$t"
  printf '%s\n' "$CANON_HEADER" >> "$t"
  tail -n +2 "$src" >> "$t" 2>/dev/null
  mv "$t" "$src"; TMP_FILE=""
}

append_samples_if_missing() {
  local csv="$1"; local added=0; local use_crlf=0
  detect_file_crlf "$csv" && use_crlf=1
  if ! grep -Fq "minion-el7-01" "$csv"; then
    [ $use_crlf -eq 1 ] && printf '%s\r\n' "$SAMPLE_EL7_ROW" >> "$csv" || printf '%s\n' "$SAMPLE_EL7_ROW" >> "$csv"
    added=1
  fi
  if ! grep -Fq "minion-el8-01" "$csv"; then
    [ $use_crlf -eq 1 ] && printf '%s\r\n' "$SAMPLE_EL8_ROW" >> "$csv" || printf '%s\n' "$SAMPLE_EL8_ROW" >> "$csv"
    added=1
  fi
  return $added
}

# ---------- Create/Repair ----------
ACTION="UNCHANGED"
if [ -f "$TARGET_CSV" ]; then
  info "Existing CSV detected at: $TARGET_CSV"
  raw_hdr="$(head -n 1 "$TARGET_CSV" 2>/dev/null)"
  hdr="$(printf '%s' "$raw_hdr" | sed $'1s/^\xEF\xBB\xBF//;s/\r$//')"  # strip BOM + CR
  if [ "$hdr" = "$CANON_HEADER" ]; then
    if [ $ADD_SAMPLE -eq 1 ]; then
      append_samples_if_missing "$TARGET_CSV" && ACTION="UPDATED" || ACTION="UNCHANGED"
      [ "$ACTION" = "UPDATED" ] && info "Sample rows appended" || info "Samples already present; no changes"
    else
      info "Header is canonical; no changes (use --add-sample to append samples)"
    fi
    if [ $EXPLICIT_EOL -eq 1 ]; then
      normalize_to_lf "$TARGET_CSV"
      if [ $SET_BOM -eq 1 ]; then add_bom "$TARGET_CSV"; else strip_bom "$TARGET_CSV"; fi
      [ $SET_CRLF -eq 1 ] && to_crlf "$TARGET_CSV"
      ACTION="UPDATED"
      info "Applied explicit normalization to existing CSV"
    fi
  else
    warn "Header mismatch detected"
    if [ $FORCE -eq 1 ]; then
      TS=$(date +%Y%m%d-%H%M%S); BAK="${TARGET_CSV}.bak-${TS}"
      info "Backing up existing CSV to: $BAK"
      cp -p "$TARGET_CSV" "$BAK"
      rewrite_header_preserve_rows "$TARGET_CSV"
      if [ $EXPLICIT_EOL -eq 1 ]; then
        normalize_to_lf "$TARGET_CSV"
        if [ $SET_BOM -eq 1 ]; then add_bom "$TARGET_CSV"; else strip_bom "$TARGET_CSV"; fi
        [ $SET_CRLF -eq 1 ] && to_crlf "$TARGET_CSV"
      fi
      ACTION="UPDATED"
      info "Rewrote header (rows preserved)"
    else
      error "Refusing to modify mismatched CSV without --force"
      ui_err "Header mismatch. Re-run with --force to rewrite header (backup will be created)."
      exit 3
    fi
  fi
else
  info "Creating new CSV at: $TARGET_CSV"
  tmp="$(mk_local_tmp)"
  write_csv_file_new "$tmp"
  [ $DEFAULT_BOM_NEW -eq 1 ] && add_bom "$tmp"
  [ $DEFAULT_CRLF_NEW -eq 1 ] && to_crlf "$tmp"
  mv "$tmp" "$TARGET_CSV"; TMP_FILE=""
  ACTION="CREATED"
  info "CSV created with canonical header and samples (Excel-default)"
fi

# ---------- Permissions ----------
chmod 600 "$TARGET_CSV" 2>/dev/null || warn "Could not set 600 on CSV"

# ---------- Validation (optional) ----------
VALID_ERRORS=0
VALID_OKS=0
if [ $VALIDATE -eq 1 ]; then
  ui_section "Validation"
  REPORT="$(mk_local_tmp)"
  # gawk FPAT handles quoted CSV fields incl. commas inside quotes
  awk '
    BEGIN {
      FPAT = "([^,]*)|(\"[^\"]*\")";
      row=0; errs=0; oks=0; warns=0;
    }
    {
      line=$0;
      sub(/\r$/, "", line);  # strip CR
      row++;
      if (row==1) next;      # skip header
      tmp=line; gsub(/^[ \t]+|[ \t]+$/, "", tmp);
      if (tmp=="") next;     # skip blank
      n=NF;
      if (n != 12) { print "E\t" row "\tfield_count\t" n; errs++; next; }
      # strip surrounding quotes + trim
      for (i=1;i<=12;i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i);
        if ($i ~ /^\".*\"$/) { sub(/^\"/, "", $i); sub(/\"$/, "", $i); }
      }
      pod=$1; platform=$2; host=$3; port=$4; user=$5; auth=$6; sudo=$7; py2=$8; sshargs=$9; mid=$10; groups=$11; notes=$12;

      ok=1;
      if (pod !~ /^[A-Za-z0-9_.-]+$/)      { print "E\t" row "\tpod\t" pod; ok=0; }
      if (platform !~ /^(el7|el8|el9)$/)   { print "E\t" row "\tplatform\t" platform; ok=0; }
      if (host == "")                      { print "E\t" row "\thost\t" host; ok=0; }
      if (port !~ /^[0-9]+$/ || port<1 || port>65535) { print "E\t" row "\tport\t" port; ok=0; }
      if (user == "")                      { print "E\t" row "\tuser\t" user; ok=0; }
      if (auth !~ /^(askpass|key|none)$/)  { print "E\t" row "\tauth\t" auth; ok=0; }
      if (sudo !~ /^(y|n)$/)               { print "E\t" row "\tsudo\t" sudo; ok=0; }
      if (platform=="el7" && (py2=="" || py2 !~ /^\//)) { print "E\t" row "\tpython2_bin\t" py2; ok=0; }

      if (ok==1) { print "O\t" row; oks++; } else errs++;
    }
    END { print "S\t" oks "\t" errs "\t" warns; }
  ' "$TARGET_CSV" > "$REPORT"

  # Parse report
  while IFS=$'\t' read -r code a b c; do
    [ -z "$code" ] && continue
    case "$code" in
      O) ui_ok "Row $a OK" ;;
      E) ui_err "Row $a invalid: $b${c:+ = \"$c\"}" ;;
      W) ui_warn "Row $a: $b${c:+ = \"$c\"}" ;;
      S) VALID_OKS="$a"; VALID_ERRORS="$b" ;;
    esac
  done < "$REPORT"
  rm -f "$REPORT"
fi

# ---------- Summary Panel ----------
FIELDS_COUNT=$(printf '%s' "$CANON_HEADER" | awk -F',' '{print NF}')
EOL_STYLE=$(detect_file_crlf "$TARGET_CSV" && echo "CRLF (Windows)" || echo "LF (Unix)")
BOM_STATE=$(has_bom "$TARGET_CSV" && echo "Yes" || echo "No")
DATA_ROWS=$([ -s "$TARGET_CSV" ] && tail -n +2 "$TARGET_CSV" | wc -l | awk '{print $1}' || echo "0")
PERMS=$(stat -c "%a" "$TARGET_CSV" 2>/dev/null || echo "600")

ui_section "Result"
case "$ACTION" in
  CREATED) ui_ok "CSV created successfully";;
  UPDATED) ui_ok "CSV updated successfully";;
  *)       ui_ok "No changes required";;
esac
ui_kv "Path"    "${C_BOLD}${TARGET_CSV}${C_RESET}"
ui_kv "Rows"    "${DATA_ROWS} data row(s)"
ui_kv "Header"  "${FIELDS_COUNT} fields"
ui_kv "EOL"     "${EOL_STYLE}"
ui_kv "BOM"     "${BOM_STATE}"
ui_kv "Perms"   "${PERMS}"
if [ $VALIDATE -eq 1 ]; then
  if [ "$VALID_ERRORS" -gt 0 ]; then ui_err "Validation: ${VALID_ERRORS} error(s), ${VALID_OKS} ok row(s)"; else ui_ok "Validation passed: ${VALID_OKS} row(s) OK"; fi
fi
ui_hr
printf '%b\n' "${C_BOLD}${C_GRN}✓ Done${C_RESET}"
ui_hr

# Non-zero exit if validation requested and errors found
if [ $VALIDATE -eq 1 ] && [ "$VALID_ERRORS" -gt 0 ]; then
  exit 4
fi

exit 0

