#!/bin/bash
#===============================================================
#Script Name: create-password-hash.sh
#Date: 10/01/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.4
#Short: Interactive SHA-512 password hash generator
#About: Prompts for a UNIX username and a masked password (with confirmation),
#       then outputs a glibc crypt(3) SHA-512 ($6$) hash suitable for
#       /etc/shadow and Salt pillars/states. EL7/EL8/EL9 compatible.
#       Offers to write/update pillar/data.sls in a managed block.
#===============================================================

set -u
umask 077

# ---------- Colors / UI ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"
  C_RED="\033[31m"; C_GRN="\033[32m"; C_YLW="\033[33m"; C_BLU="\033[34m"; C_CYN="\033[36m"; C_MAG="\033[35m"
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_CYN=""; C_MAG=""
fi
ICON_OK="${C_GRN}✓${C_RESET}"
ICON_WARN="${C_YLW}!${C_RESET}"
ICON_ERR="${C_RED}✖${C_RESET}"
ui_hr()      { printf '%b\n' "${C_CYN}──────────────────────────────────────────────────────────────${C_RESET}"; }
ui_title()   { ui_hr; printf '%b\n' "${C_BOLD}${C_GRN}SALT SHAKER${C_RESET} ${C_CYN}|${C_RESET} ${C_BOLD}Tool · Create Password Hash${C_RESET}"; ui_hr; }
ui_section() { printf '%b\n' "${C_BOLD}${1}${C_RESET}"; }
ui_kv()      { printf '%b\n' "  ${C_BOLD}$1${C_RESET}: $2"; }
ui_ok()      { printf '%b\n' "  ${ICON_OK} $1"; }
ui_warn()    { printf '%b\n' "  ${ICON_WARN} $1"; }
ui_err()     { printf '%b\n' "  ${ICON_ERR} $1"; }

# ---------- Defaults / CLI ----------
MODULE_NAME="tools/create-password-hash.sh"
PROJECT_ROOT=""
NON_INTERACTIVE=0
USERNAME=""

# ---------- Logging (project-only) ----------
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
LOG_FILE=""
log_init_done=0
log_init() {
  [ $log_init_done -eq 1 ] && return 0
  [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
  mkdir -p "${PROJECT_ROOT}/logs" 2>/dev/null
  chmod 700 "${PROJECT_ROOT}/logs" 2>/dev/null
  LOG_FILE="${PROJECT_ROOT}/logs/salt-shaker.log"
  log_init_done=1
}
log()     { log_init; printf '%s [%s] (%s) %s\n' "$(stamp)" "INFO"  "$MODULE_NAME" "$1" >> "$LOG_FILE"; }
log_err() { log_init; printf '%s [%s] (%s) %s\n' "$(stamp)" "ERROR" "$MODULE_NAME" "$1" >> "$LOG_FILE"; }

# ---------- Help / About ----------
print_help() {
  ui_title
  ui_section "Usage"
  echo "  tools/create-password-hash.sh [options]"
  echo
  ui_section "Options"
  echo "  -h, --help            Show help"
  echo "  -a, --about           About this tool"
  echo "  -d, --dir <path>      Project root override"
  echo "      --non-interactive Not supported (needs TTY for secrets)"
  ui_hr
}
print_about() {
  ui_title
  ui_section "About"
  echo "Generates a SHA-512 crypt(3) password hash ($6$) compatible with EL7/EL8/EL9."
  echo "Prompts for username and masked password; no data leaves the project."
  ui_hr
}

# ---------- CLI parsing ----------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help; exit 0 ;;
    -a|--about) print_about; exit 0 ;;
    -d|--dir) shift; PROJECT_ROOT="$1" ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    *) ui_err "Unknown argument: $1"; print_help; exit 2 ;;
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

# ---------- TTY for prompts ----------
HAS_TTY=0
if [ -r /dev/tty ] && [ -w /dev/tty ]; then exec 3<> /dev/tty; HAS_TTY=1; fi
die_no_tty() { ui_err "No TTY available; cannot read input securely."; log_err "No TTY"; exit 2; }

# ---------- Traps / cleanup ----------
PASSWORD=""; CONFIRM=""; SALT=""; HASH=""
on_exit() {
  local rc=$?
  PASSWORD=""; CONFIRM=""
  unset PASSWORD CONFIRM
  [ "$HAS_TTY" -eq 1 ] && exec 3<&- 3>&-
  if [ $rc -eq 0 ]; then log "Password hash generated successfully"; else log_err "Exited with code $rc"; fi
  exit $rc
}
trap on_exit EXIT
trap 'ui_err "Interrupted"; exit 130' INT TERM

# ---------- Prompt helpers ----------
prompt_line() {
  # $1 prompt, $2 default
  [ "$HAS_TTY" -eq 1 ] || die_no_tty
  local p="$1" d="$2" ans=""
  /bin/echo -en "${C_BOLD}${p}${C_RESET} [${d}]: " >&3
  IFS= read -r ans <&3 || ans=""
  [ -z "$ans" ] && ans="$d"
  printf '%s' "$ans"
}
read_secret_stars() {
  # $1 prompt -> returns entered secret
  [ "$HAS_TTY" -eq 1 ] || die_no_tty
  /bin/echo -en "${C_BOLD}$1${C_RESET}: " >&3
  local oldstty; oldstty=$(stty -g <&3)
  stty -echo -icanon min 1 time 0 <&3
  local pw="" ch
  while true; do
    IFS= read -r -n1 ch <&3 || ch=""
    if [ "$ch" = $'\n' ] || [ "$ch" = $'\r' ] || [ -z "$ch" ]; then
      /bin/echo >&3; break
    fi
    case "$ch" in
      $'\177'|$'\010') if [ -n "$pw" ]; then pw="${pw%?}"; /bin/echo -en $'\b \b' >&3; fi ;;
      *) pw+="$ch"; /bin/echo -n "*" >&3 ;;
    esac
  done
  stty "$oldstty" <&3
  printf '%s' "$pw"
}

# ---------- Username validation ----------
is_valid_username() {
  # Linux-friendly: starts with [a-z_], then [a-z0-9_-]
  printf '%s' "$1" | LC_ALL=C grep -Eq '^[a-z_][a-z0-9_-]*$'
}

# ---------- Salt + hashing ----------
gen_salt() { tr -dc 'A-Za-z0-9./' < /dev/urandom | head -c 16; }

compute_hash() {
  # $1 pw, $2 salt
  local pw="$1" salt="$2" out rc
  if command -v python3 >/dev/null 2>&1; then
    out="$(PASS="$pw" SALT="$salt" python3 - <<'PY' 2>/dev/null
import os, crypt
pwd=os.environ.get('PASS',''); salt=os.environ.get('SALT','')
print(crypt.crypt(pwd, '$6$%s$' % salt))
PY
)"; rc=$?; [ $rc -eq 0 ] && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  fi
  if command -v python2 >/dev/null 2>&1; then
    out="$(PASS="$pw" SALT="$salt" python2 - <<'PY' 2>/dev/null
import os
try: import crypt
except Exception: raise SystemExit(1)
pwd=os.environ.get('PASS',''); salt=os.environ.get('SALT','')
print(crypt.crypt(pwd, '$6$%s$' % salt))
PY
)"; rc=$?; [ $rc -eq 0 ] && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  fi
  if command -v python >/dev/null 2>&1; then
    out="$(PASS="$pw" SALT="$salt" python - <<'PY' 2>/dev/null
import os
try: import crypt
except Exception: raise SystemExit(1)
pwd=os.environ.get('PASS',''); salt=os.environ.get('SALT','')
print(crypt.crypt(pwd, '$6$%s$' % salt))
PY
)"; rc=$?; [ $rc -eq 0 ] && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  fi
  if command -v openssl >/dev/null 2>&1 && openssl passwd -help 2>&1 | grep -q -- '-6'; then
    out="$(printf '%s' "$pw" | openssl passwd -6 -salt "$salt" -stdin 2>/dev/null)"
    rc=$?; [ $rc -eq 0 ] && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  fi
  return 1
}

# ---------- Pillar write helpers ----------
BEGIN_MARK="# salt-shaker: managed-users begin"
END_MARK="# salt-shaker: managed-users end"

ensure_proj_dir() {
  [ -d "$1" ] || { mkdir -p "$1" 2>/dev/null || return 1; chmod 700 "$1" 2>/dev/null || true; }
  return 0
}

file_has_managed_block() {
  # $1 file
  [ -f "$1" ] || return 1
  grep -qF "$BEGIN_MARK" "$1" && grep -qF "$END_MARK" "$1"
}

rebuild_block_to_file() {
  # $1 src file (may exist), $2 out block file, $3 username, $4 hash
  local src="$1" out="$2" user="$3" hash="$4"
  awk -v bm="$BEGIN_MARK" -v em="$END_MARK" -v user="$user" -v hash="$hash" '
    BEGIN{ in=0; have=0 }
    $0==bm { in=1; next }
    $0==em { in=0; next }
    {
      if(in){
        if($1=="users:"){ after_users=1; next }
        if(after_users){
          if($0 ~ /^[[:space:]]{2}[a-z_][a-z0-9_-]*:[[:space:]]*$/){
            uname=$0; gsub(/^[[:space:]]{2}|:[[:space:]]*$/,"",uname); cur=uname; next
          }
          if($0 ~ /^[[:space:]]{4}password:[[:space:]]*".*"([[:space:]]*)$/){
            gsub(/^[[:space:]]{4}password:[[:space:]]*"/,"",$0); gsub(/".*$/,"",$0)
            users[cur]=$0; cur=""
          }
        }
      }
    }
    END{
      users[user]=hash
      print bm > "'"$out"'"
      print "users:" >> "'"$out"'"
      # sort keys for stable output (gawk asort)
      n=0; for (k in users){ if(k!=""){ keys[++n]=k } }
      if(n>0){ asort(keys) }
      for(i=1;i<=n;i++){
        u=keys[i]; printf("  %s:\n    password: \"%s\"\n", u, users[u]) >> "'"$out"'"
      }
      print em >> "'"$out"'"
    }
  ' "$src" 2>/dev/null
}

replace_managed_block_in_file() {
  # $1 src file, $2 block file, $3 dest file
  local src="$1" block="$2" dest="$3"
  awk -v bm="$BEGIN_MARK" -v em="$END_MARK" -v bf="$block" '
    BEGIN{ in=0 }
    {
      if($0==bm){
        in=1
        while ((getline l < bf) > 0) print l
        next
      }
      if(in){
        if($0==em){ in=0; next } else { next }
      }
      print
    }
  ' "$src" > "$dest"
}

warn_users_key_outside_block() {
  # $1 file -> warns if 'users:' exists outside managed block
  local f="$1"
  awk -v bm="$BEGIN_MARK" -v em="$END_MARK" '
    BEGIN{ in=0 }
    {
      if($0==bm){ in=1; next }
      if(in && $0==em){ in=0; next }
      if(!in) print
    }
  ' "$f" | grep -qE '^[[:space:]]*users:[[:space:]]*$' && return 0 || return 1
}

gitignore_mentions_pillar_data() {
  # returns 0 if .gitignore mentions pillar/data.sls
  [ -f "${PROJECT_ROOT}/.gitignore" ] || return 1
  grep -qE '(^|/| )pillar/data\.sls($| )' "${PROJECT_ROOT}/.gitignore"
}

write_to_pillar_datasls() {
  # $1 username, $2 hash
  local user="$1" hash="$2" tstamp; tstamp="$(date +%Y%m%d-%H%M%S)"
  local pdir="${PROJECT_ROOT}/pillar"
  local file="${pdir}/data.sls"
  local bkup="${file}.bak.${tstamp}"
  local blockf="${PROJECT_ROOT}/tmp/create-hash.block.${tstamp}.$$"
  local tmpout="${PROJECT_ROOT}/tmp/create-hash.file.${tstamp}.$$"

  ensure_proj_dir "${PROJECT_ROOT}/tmp" || { ui_err "Failed to create tmp dir"; return 2; }
  ensure_proj_dir "$pdir" || { ui_err "Failed to create pillar dir"; return 2; }

  if [ ! -f "$file" ]; then
    # fresh file with our managed block
    {
      echo "# Generated by ${MODULE_NAME} on $(date)"
      echo "$BEGIN_MARK"
      echo "users:"
      echo "  ${user}:"
      echo "    password: \"${hash}\""
      echo "$END_MARK"
    } > "$file" || return 2
    chmod 600 "$file" 2>/dev/null || true
    ui_ok "Created pillar/data.sls"
  else
    cp -p "$file" "$bkup" 2>/dev/null || true
    # build new managed block
    rebuild_block_to_file "$file" "$blockf" "$user" "$hash"
    if file_has_managed_block "$file"; then
      replace_managed_block_in_file "$file" "$blockf" "$tmpout" || return 2
      mv -f "$tmpout" "$file" || return 2
    else
      # append managed block at EOF
      printf '\n' >> "$file"
      cat "$blockf" >> "$file" || return 2
    fi
    chmod 600 "$file" 2>/dev/null || true
    ui_ok "Updated pillar/data.sls (backup: $(basename "$bkup"))"
    if warn_users_key_outside_block "$file"; then
      ui_warn "Detected another 'users:' key outside managed block; YAML may have duplicate keys (last wins)."
      ui_warn "Consider consolidating into the managed block."
    fi
  fi

  if ! gitignore_mentions_pillar_data; then
    ui_warn "Git: pillar/data.sls is not ignored. Consider adding to .gitignore."
  fi

  # show the managed snippet (for visibility)
  ui_section "Managed block (pillar/data.sls)"
  echo "$BEGIN_MARK"
  echo "users:"
  echo "  ${user}:"
  echo "    password: \"${hash}\""
  echo "$END_MARK"

  return 0
}

# ---------- Main ----------
ui_title
ui_section "Create Password Hash"
printf "Project Root : %s\n" "$PROJECT_ROOT"
ui_hr

[ $NON_INTERACTIVE -eq 1 ] && { ui_err "--non-interactive not supported for secret input"; exit 2; }

# Username
attempts=0
default_user="admin"
while : ; do
  USERNAME="$(prompt_line 'Enter username' "$default_user")"
  if is_valid_username "$USERNAME"; then
    break
  fi
  attempts=$((attempts+1))
  ui_warn "Invalid username. Use: ^[a-z_][a-z0-9_-]*$"
  [ $attempts -ge 3 ] && { ui_err "Too many invalid attempts"; exit 2; }
done

# Password (masked, confirmed)
tries=0
while : ; do
  PASSWORD="$(read_secret_stars 'Enter password')"
  CONFIRM="$(read_secret_stars 'Re-enter password')"
  if [ "$PASSWORD" = "$CONFIRM" ] && [ -n "$PASSWORD" ]; then
    break
  fi
  tries=$((tries+1))
  if [ $tries -ge 3 ]; then ui_err "Too many mismatches or empty password"; exit 2; fi
  ui_warn "Passwords did not match or were empty. Try again."
done

SALT="$(gen_salt)"
HASH="$(compute_hash "$PASSWORD" "$SALT" || true)"
PASSWORD=""; CONFIRM=""; unset PASSWORD CONFIRM

[ -n "$HASH" ] || { ui_err "Failed to produce SHA-512 hash (need python3/python2 or openssl -6)."; exit 3; }

# ---------- Result ----------
ui_section "Result"
ui_kv "Username" "$USERNAME"
ui_kv "Algorithm" "SHA-512 (crypt \$6\$)"
ui_kv "Salt" "$SALT"
ui_kv "Hash" "$HASH"
ui_hr
ui_section "Usage (examples)"
echo "  Pillar:"
echo "    users:"
echo "      ${USERNAME}:"
echo "        password: \"$HASH\""
echo "  State (user.present):"
echo "    usermod-${USERNAME}:"
echo "      user.present:"
echo "        - name: ${USERNAME}"
echo "        - password: \"$HASH\""
ui_hr

# ---------- Offer write to pillar/data.sls ----------
WRITE="$(prompt_line 'Write to pillar/data.sls? (Y/n)' 'Y')"
case "$WRITE" in
  n|N) ui_ok "Skipped writing to pillar/data.sls." ;;
  *)   write_to_pillar_datasls "$USERNAME" "$HASH" || { ui_err "Failed to update pillar/data.sls"; exit 4; } ;;
esac

ui_ok "Hash generated. Copy the 'Hash' value above."
ui_hr
printf '%b\n' "${C_BOLD}${C_GRN}✓ Done${C_RESET}"
ui_hr
exit 0

