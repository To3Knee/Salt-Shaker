#===============================================================
#Script Name: setup.sh
#Date: 09/30/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Create Salt-Shaker directory skeleton (safe)
#About: Interactive, idempotent directory bootstrap. Asks for target project root,
#       sets conservative permissions, creates all required folders, and ensures
#       .gitignore ignores GitHub/. Never deletes anything. EL7-safe.
#===============================================================
#!/bin/bash
set -euo pipefail

#---------------- Config (edit) ----------------#
DEFAULT_DIR_MODE_ROOT="700"
DEFAULT_DIR_MODE_TEAM="755"
DEFAULT_EXE_MODE="755"
#----------------------------------------------#

color() { [ -t 1 ] || { printf "%s" "$2"; return; }; printf "%b%s%b" "$1" "$2" "\033[0m"; }
C_G="\033[0;32m"; C_Y="\033[1;33m"; C_R="\033[0;31m"; C_B="\033[0;34m"; C_W="\033[1;37m"; C_N="\033[0m"

say() { color "$C_B" "══════════════════════════════════════════════════════════════════════\n"; \
       color "$C_W" "▶ $1\n"; \
       color "$C_B" "Script Dir : $(pwd -P)\n"; \
       color "$C_B" "Current Dir: $PWD\n"; \
       color "$C_B" "══════════════════════════════════════════════════════════════════════\n"; }

ask() { # $1 prompt, $2 default
  local a; read -r -p "$1 [$2]: " a || true; echo "${a:-$2}"
}

ensure_dir() {
  local d="$1" mode="$2"
  if [ ! -d "$d" ]; then mkdir -p "$d"; fi
  chmod "$mode" "$d" 2>/dev/null || true
}

ensure_gitignore_has() {
  local root="$1" pat="$2"
  [ -f "$root/.gitignore" ] || : > "$root/.gitignore"
  if ! grep -qE "^${pat}(/|$)" "$root/.gitignore"; then
    echo "$pat/" >> "$root/.gitignore"
  fi
}

exe_glob_chmod() { # chmod +x if file exists
  local mode="$1"; shift
  for f in "$@"; do
    [ -f "$f" ] && chmod "$mode" "$f" 2>/dev/null || true
  done
}

say "Salt Shaker Setup"

# 1) Choose project root
DEF_ROOT="$(pwd -P)"
PROJECT_ROOT="$(ask "Project root directory" "$DEF_ROOT")"
mkdir -p "$PROJECT_ROOT"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
echo

# 2) Perm model
echo "Permission model:"
echo "  1) root-only (dirs ${DEFAULT_DIR_MODE_ROOT}, exec ${DEFAULT_EXE_MODE})"
echo "  2) team      (dirs ${DEFAULT_DIR_MODE_TEAM}, exec ${DEFAULT_EXE_MODE})"
choice="$(ask "Select 1 or 2" "1")"
DIR_MODE="$DEFAULT_DIR_MODE_ROOT"
[ "$choice" = "2" ] && DIR_MODE="$DEFAULT_DIR_MODE_TEAM"
EXE_MODE="$DEFAULT_EXE_MODE"
echo

# 3) Create skeleton (never remove)
color "$C_W" "Creating directory skeleton under: $PROJECT_ROOT\n"
# top-level
for d in \
  archive bin env file-roots info logs modules offline pillar roster rpm scripts support tmp tools vendor \
  offline/deps offline/salt offline/salt/el7 offline/salt/el8 offline/salt/el9 offline/salt/tarballs offline/salt/thin \
  vendor/el7 vendor/el7/salt vendor/el7/thin vendor/el8 vendor/el8/salt vendor/el9 vendor/el9/salt
do
  ensure_dir "$PROJECT_ROOT/$d" "$DIR_MODE"
done

# 4) Mark known scripts executable if already present (idempotent)
exe_glob_chmod "$EXE_MODE" \
  "$PROJECT_ROOT/salt-shaker.sh" \
  "$PROJECT_ROOT/salt-shaker-el7.sh" \
  "$PROJECT_ROOT/clean-house.sh"

# modules / support / tools / env: chmod +x for *.sh if present
for sub in modules support tools env github; do
  if [ -d "$PROJECT_ROOT/$sub" ]; then
    find "$PROJECT_ROOT/$sub" -maxdepth 1 -type f -name '*.sh' -exec chmod "$EXE_MODE" {} + 2>/dev/null || true
  fi
done

# 5) .gitignore hygiene (ignore GitHub workspace)
ensure_gitignore_has "$PROJECT_ROOT" "GitHub"
ensure_gitignore_has "$PROJECT_ROOT" "github"

color "$C_G" "✓ Skeleton ready.\n"
echo "Next:"
echo "  • Optionally run github/download-salt-shaker.sh to pull code into the tree."
echo "  • Then run salt-shaker.sh and start with module 01."
exit 0
