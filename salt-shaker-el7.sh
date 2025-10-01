# /sto/salt-shaker/Salt-Shaker.sh
#!/bin/bash
#===============================================================
# Script Name : Salt-Shaker.sh
# Version     : v8.10
# Codename    : Green Obsidian
# Compatibility: RHEL 7 (bash 4.2+) and newer
# Notes (why): Auto-width box; title/tagline/OS on separate lines; color UI; dynamic height; fixed name column; exclude xx-* modules
#===============================================================

#------------------------- Config ------------------------------
PROJECT_ROOT="${PWD}"
MODULES_DIR="${PROJECT_ROOT}/modules"
LOG_DIR="${PROJECT_ROOT}/logs"
MAIN_LOG="${LOG_DIR}/salt-shaker.log"
ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
MODULE_PERMS="755"

MAX_MENU_ITEMS=15              # items per page
BOX_INNER_WIDTH=78             # auto-updated per terminal/content
NAME_COLUMN=12                 # 1-based column where names start
DELIMITER="|"
BANNER_VERSION="v8.10"
SUBHEADER_TEXT="Portable SaltStack Automation for Air-Gapped Environments"

#------------------------- Colors ------------------------------
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'; PURPLE=$'\033[0;35m'; CYAN=$'\033[0;36m'
  WHITE=$'\033[1;37m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; PURPLE=""; CYAN=""; WHITE=""; NC=""
fi

#------------------------- Utils -------------------------------
ensure_dirs() { mkdir -p "${LOG_DIR}"; : >"${MAIN_LOG}" 2>/dev/null || true; : >"${ERROR_LOG}" 2>/dev/null || true; }
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log_info()  { echo "$(timestamp) [INFO]  $1"  >>"${MAIN_LOG}";  echo -e "${GREEN}[INFO] $1${NC}"; }
log_warn()  { echo "$(timestamp) [WARN]  $1"  >>"${MAIN_LOG}";  echo -e "${YELLOW}[WARN] $1${NC}" >&2; }
log_error() { echo "$(timestamp) [ERROR] $1"  >>"${ERROR_LOG}"; echo -e "${RED}[ERROR] $1${NC}" >&2; }

# ANSI helpers for width
_strip_ansi() { printf "%s" "$1" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'; }
_vlen()       { local s; s=$(_strip_ansi "$1"); echo -n "${#s}"; }

# Terminal width
get_term_cols() {
  local c
  c=$( (tput cols 2>/dev/null || true) )
  [ -n "$c" ] || c="${COLUMNS:-0}"
  [[ "$c" =~ ^[0-9]+$ ]] || c=0
  echo "$c"
}

center_line() {
  local text="$1" len; len=$(_vlen "$text")
  if [ "$len" -ge "$BOX_INNER_WIDTH" ]; then printf "%s" "$text"; return; fi
  local pad=$(( (BOX_INNER_WIDTH - len) / 2 ))
  printf "%*s%s%*s" "$pad" "" "$text" $((BOX_INNER_WIDTH - len - pad)) ""
}

pad_line() {
  local text="$1" len; len=$(_vlen "$text")
  if [ "$len" -ge "$BOX_INNER_WIDTH" ]; then printf "%s" "$text"; return; fi
  printf "%s%*s" "$text" $((BOX_INNER_WIDTH - len)) ""
}

pause() { local msg="${1:-Press Enter to continue...}"; echo -e "${CYAN}${msg}${NC}"; read -r -e; }

#------------------------- OS Detect ---------------------------
# Returns "base|codename"
get_os_info() {
  local base="" code=""
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    # Prefer PRETTY_NAME for full name, but strip any parentheses content from base
    local pretty="${PRETTY_NAME:-$NAME $VERSION_ID}"
    base="$(echo "$pretty" | sed -E 's/ *\([^)]*\)//g' | sed -E 's/  +/ /g')"
    # Codename priority: VERSION_CODENAME, then content in parentheses from PRETTY_NAME or VERSION
    if [ -n "${VERSION_CODENAME:-}" ]; then
      code="$VERSION_CODENAME"
    else
      code="$(echo "$pretty" | sed -n 's/.*(\([^)]\+\)).*/\1/p')"
      [ -z "$code" ] && code="$(echo "${VERSION:-}" | sed -n 's/.*(\([^)]\+\)).*/\1/p')"
    fi
  elif [ -f /etc/redhat-release ]; then
    local rel; rel="$(cat /etc/redhat-release 2>/dev/null || true)"
    base="$(echo "$rel" | sed -E 's/ *\([^)]*\)//g' | sed -E 's/  +/ /g')"
    code="$(echo "$rel" | sed -n 's/.*(\([^)]\+\)).*/\1/p')"
  else
    base="Unknown"; code=""
  fi
  printf "%s|%s" "$base" "$code"
}

# Build colored OS line once we know width
build_os_line() {
  local info base code
  info="$(get_os_info)"
  IFS="|" read -r base code <<< "$info"
  if [ -n "$code" ]; then
    printf "%s" "${PURPLE}${base}${NC} ${WHITE}•${NC} ${GREEN}${code}${NC}"
  else
    printf "%s" "${PURPLE}${base}${NC}"
  fi
}

# Compute inner width based on content & terminal
compute_inner_width() {
  local term_cols title tagline osline need n
  term_cols=$(get_term_cols); [ "$term_cols" -ge 20 ] || term_cols=0

  title="${CYAN}S A L T • S H A K E R ${BANNER_VERSION}${NC}"
  tagline="${YELLOW}${SUBHEADER_TEXT}${NC}"
  osline="$(build_os_line)"

  need=$(_vlen "$title")
  n=$(_vlen "$tagline"); [ "$n" -gt "$need" ] && need="$n"
  n=$(_vlen "$osline");  [ "$n" -gt "$need" ] && need="$n"
  [ "$need" -lt 78 ] && need=78
  if [ "$term_cols" -gt 0 ]; then
    local max_inner=$(( term_cols - 2 ))
    [ "$need" -gt "$max_inner" ] && need="$max_inner"
  fi
  BOX_INNER_WIDTH="$need"
}

#------------------------- Filter ------------------------------
should_skip_module() {
  # hide WIP/disabled modules
  local name_lc="$1" base_lc="$2"
  case "$name_lc" in xx*|xx\ *|xx-*|xx_* ) return 0;; esac
  case "$base_lc" in xx*|xx-*|xx_* ) return 0;; esac
  return 1
}

#------------------------- Module Parsing ----------------------
parse_module_headers() {
  local module_path="$1"
  local num name short about
  num=$(grep -m1 -oE '^#\s*Module:\s*([0-9]+)' "$module_path" 2>/dev/null | grep -oE '[0-9]+' || true)
  name=$(grep -m1 -oE '^#\s*Module:\s*[0-9]+\s*-\s*(.+)$' "$module_path" 2>/dev/null | sed -E 's/^#\s*Module:\s*[0-9]+\s*-\s*//' || true)
  short=$(grep -m1 -oE '^#\s*Short:\s*(.+)$' "$module_path" 2>/dev/null | sed -E 's/^#\s*Short:\s*//' || true)
  about=$(grep -m1 -oE '^#\s*About:\s*(.+)$' "$module_path" 2>/dev/null | sed -E 's/^#\s*About:\s*//' || true)

  if [ -n "$num" ] && [ -n "$name" ]; then
    printf "%s%s%s%s%s%s%s%s%s%s%s%s%s\n" \
      "$num" "$DELIMITER" "$num" "$DELIMITER" "$name" "$DELIMITER" "$short" "$DELIMITER" "$about" "$DELIMITER" "$module_path" "$DELIMITER" "H"
    return 0
  fi
  return 1
}

parse_module_from_filename() {
  local module_path="$1"
  local base file num rest name
  base="$(basename -- "$module_path")"
  file="${base%.*}"
  num="$(echo "$file" | grep -oE '^[0-9]+' || true)"
  rest="$(echo "$file" | sed -E 's/^[0-9]+[-_ ]?//' )"
  name="$(echo "${rest:-$file}" | sed -E 's/[-_]+/ /g')"
  if [ -n "$num" ]; then
    printf "%s%s%s%s%s%s%s%s%s%s%s%s%s\n" \
      "$num" "$DELIMITER" "$num" "$DELIMITER" "$name" "$DELIMITER" "" "$DELIMITER" "" "$DELIMITER" "$module_path" "$DELIMITER" "F"
  else
    printf "%s%s%s%s%s%s%s%s%s%s%s%s%s\n" \
      "9999999" "$DELIMITER" "" "$DELIMITER" "$name" "$DELIMITER" "" "$DELIMITER" "" "$DELIMITER" "$module_path" "$DELIMITER" "F"
  fi
}

#------------------------- Sorting (bash-4.2 safe) -------------
sort_modules() {
  # Fields: 1=sort_key 2=display_num 3=name 4=short 5=about 6=path 7=src
  local in_name="$1" out_name="$2"
  local sorted_lines
  sorted_lines=$(eval "printf '%s\n' \"\${${in_name}[@]}\" | sort -t\"$DELIMITER\" -k1n,1 -k3") || return 1
  eval "$out_name=()"
  while IFS= read -r line; do eval "$out_name+=(\"\$line\")"; done <<< "$sorted_lines"
}

#------------------------- UI Helpers --------------------------
box_top()    { printf "${WHITE}╔"; printf '═%.0s' $(seq 1 "$BOX_INNER_WIDTH"); printf "╗${NC}\n"; }
box_rule()   { printf "${WHITE}╠"; printf '═%.0s' $(seq 1 "$BOX_INNER_WIDTH"); printf "╣${NC}\n"; }
box_line()   { printf "${WHITE}║${NC}"; pad_line "$1"; printf "${WHITE}║${NC}\n"; }
box_bottom() { printf "${WHITE}╚"; printf '═%.0s' $(seq 1 "$BOX_INNER_WIDTH"); printf "╝${NC}\n"; }

print_header() {
  compute_inner_width
  local title tagline osline
  title="${CYAN}S A L T • S H A K E R ${BANNER_VERSION}${NC}"
  tagline="${YELLOW}${SUBHEADER_TEXT}${NC}"
  osline="$(build_os_line)"

  box_top
  box_line "$(center_line "$title")"
  box_rule
  box_line "$(center_line "$tagline")"
  box_line "$(center_line "$osline")"
  box_rule
}

print_footer() {
  box_rule
  box_line "  ${WHITE}[1-${VISIBLE_COUNT}] Select${NC} • ${CYAN}[N] Next${NC} • ${CYAN}[P] Prev${NC} • ${CYAN}[R] Refresh${NC} • ${CYAN}[H] Help${NC} • ${RED}[Q] Quit${NC}  "
  box_bottom
}

render_module_line() {
  local idx="$1" name="$2"
  local prefix; prefix=$(printf "  ${WHITE}%2d)${NC}  " "$idx")
  local cur_col; cur_col=$(_vlen "$prefix")
  local gap=$(( NAME_COLUMN - cur_col )); [ $gap -lt 1 ] && gap=1
  local spaces; spaces=$(printf "%*s" "$gap" "")
  box_line "${prefix}${spaces}${CYAN}${name}${NC}"
}

print_modules_page() {
  local -a arr=("$@")
  local start_index="$PAGE_START" end_index="$PAGE_END" idx=1
  for ((i=start_index; i<end_index; i++)); do
    IFS="$DELIMITER" read -r _sort _disp name _s _a _path _src <<< "${arr[$i]}"
    render_module_line "$idx" "$name"
    ((idx++))
  done
}

#------------------------- Menu -------------------------------
show_help_menu() {
  clear
  print_header
  box_line "  ${WHITE}•${NC} Enter a number to execute the corresponding module"
  box_line "  ${WHITE}•${NC} ${CYAN}[Q] Quit${NC}  ${CYAN}[N] Next${NC}  ${CYAN}[P] Previous${NC}  ${CYAN}[R] Refresh${NC}  ${CYAN}[H] Help${NC}"
  print_footer
  pause
}

build_menu() {
  log_info "Scanning modules in '${MODULES_DIR}'..."
  local -a modules=() sorted_modules=()
  shopt -s nullglob
  for module_file in "${MODULES_DIR}"/*.sh; do
    [[ -f "$module_file" ]] || continue
    local info="" base lcbase
    base="$(basename -- "$module_file")"
    lcbase="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
    if ! info=$(parse_module_headers "$module_file"); then info=$(parse_module_from_filename "$module_file"); fi
    [ -z "$info" ] && continue
    IFS="$DELIMITER" read -r _sort _disp name _s _a _path _src <<< "$info"
    local lcname; lcname="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    if should_skip_module "$lcname" "$lcbase"; then continue; fi
    modules+=("$info")
  done
  shopt -u nullglob

  if [ "${#modules[@]}" -eq 0 ]; then
    clear; print_header; box_line "${RED}No valid modules found in ${MODULES_DIR}.${NC}"; print_footer
    echo -en "${WHITE}Press Enter to rescan or Q to quit:${NC} "; read -r -n1 key || true
    case "${key}" in q|Q) clear; box_top; box_line "$(center_line "${CYAN}Thanks for using Salt Shaker!${NC}")"; box_bottom; exit 0 ;; *) return 0 ;; esac
  fi

  sort_modules modules sorted_modules

  local total=${#sorted_modules[@]} page=0 per_page="${MAX_MENU_ITEMS}"
  while :; do
    local start=$(( page * per_page )) end=$(( start + per_page ))
    [ "$end" -gt "$total" ] && end="$total"
    PAGE_START="$start"; PAGE_END="$end"

    clear
    print_header
    print_modules_page "${sorted_modules[@]}"
    VISIBLE_COUNT=$((end - start))
    print_footer

    echo -en "${WHITE}Select [1-${VISIBLE_COUNT} / N / P / R / H / Q]: ${NC}"
    read -r -e choice || true
    case "$choice" in
      [Qq]) clear; box_top; box_line "$(center_line "${CYAN}Thanks for using Salt Shaker!${NC}")"; box_bottom; exit 0 ;;
      [Hh]) show_help_menu ;;
      [Rr]) return 0 ;;
      [Nn]) if [ "$end" -lt "$total" ]; then ((page++)); else log_warn "Already on last page."; fi ;;
      [Pp]) if [ "$page" -gt 0 ]; then ((page--)); else log_warn "Already on first page."; fi ;;
      ''|*[!0-9]*)
        log_warn "Invalid selection. Use a number, or N/P/R/H/Q."
        ;;
      *)
        local sel="$choice"
        if [ "$sel" -ge 1 ] && [ "$sel" -le "$VISIBLE_COUNT" ]; then
          local target=$(( start + sel - 1 ))
          IFS="$DELIMITER" read -r _sort _disp name _s _a module_path _src <<< "${sorted_modules[$target]}"
          echo -e "${BLUE}→ Running: ${name}${NC}"
          chmod "${MODULE_PERMS}" "$module_path" 2>/dev/null || true
          bash "$module_path"
          status=$?
          if [ $status -eq 0 ]; then echo -e "${GREEN}✓ Completed: ${name}${NC}"
          else log_error "Module '${name}' failed. See logs."; echo -e "${RED}✗ Failed: ${name}${NC}"; fi
          pause "Press Enter to return to menu"
        else
          log_warn "Select a number from 1-${VISIBLE_COUNT}."
          pause
        fi
        ;;
    esac
  done
}

#------------------------- Main --------------------------------
main() {
  ensure_dirs
  while :; do build_menu || true; done
}

main "$@"
