#!/bin/bash
#===============================================================
#Script Name: fix-permissions.sh
#Date: 09/20/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.3
#Short: Fix project directory permissions (one-off utility)
#About: This one-off utility script fixes permissions for the existing Salt Shaker project structure when run as root. It sets proper permissions for starter directories (offline, logs, modules), main scripts (salt-shaker.sh), and module scripts. Directories get 755 permissions, executable scripts get 755, and log files get 644. Designed to be run only during initial setup or permission resets. Must be run as root. Not intended for menu integration - utility only.
#===============================================================

#===============================================================
# Configuration Section
#===============================================================
# Fix PROJECT_ROOT to be the parent directory (since script runs from scripts/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
LOG_DIR="${PROJECT_ROOT}/logs"
MAIN_LOG="${LOG_DIR}/salt-shaker.log"
ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"

# Permissions
DIR_PERMS="755"           # Standard directory permissions
SCRIPT_PERMS="755"        # Executable script permissions
LOG_PERMS="644"           # Log file permissions
MODULES_DIR="${PROJECT_ROOT}/modules"

# Initialize counters (FIXED: Initialize all variables)
dir_success=0
dir_total=0
script_success=0
module_success=0
log_success=0
log_total=0

# Color definitions for console output
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    ORANGE='\033[38;2;255;102;0m'  # Orange for warns about missing dirs
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
else
    RED="" GREEN="" YELLOW="" ORANGE="" BLUE="" CYAN="" WHITE="" NC=""
fi

#===============================================================
# Functions
#===============================================================

# Function to log messages with color-coded console output
log_info() {
    local message="$1"
    local color="$2"
    [ -z "${color}" ] && color="${GREEN}"
    
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    echo -e "${color}${message}${NC}"
}

# Function to log errors with red highlighting
log_error() {
    local message="$1"
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${message}" >> "${ERROR_LOG}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    echo -e "${RED}[ERROR] ${message}${NC}" >&2
}

# Function to log warnings with yellow highlighting (or orange for specific)
log_warn() {
    local message="$1"
    local color="${2:-${YELLOW}}"  # Default yellow, can pass ORANGE
    
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    echo -e "${color}[WARN] ${message}${NC}" >&2
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    log_info "Running as root - good" "${GREEN}"
}

# Function to fix directory permissions
fix_directory() {
    local dir_path="$1"
    local description="$2"
    
    if [ ! -d "${dir_path}" ]; then
        log_warn "Directory not found (run 01-init-dirs.sh first): ${dir_path}" "${ORANGE}"
        return 1
    fi
    
    if chmod "${DIR_PERMS}" "${dir_path}"; then
        log_info "Fixed permissions ${DIR_PERMS} on ${description}: ${dir_path}" "${GREEN}"
        return 0
    else
        log_error "Failed to set permissions on ${dir_path}"
        return 1
    fi
}

# Function to fix script permissions
fix_script() {
    local script_path="$1"
    local description="$2"
    
    if [ ! -f "${script_path}" ]; then
        log_warn "Script not found: ${script_path}"
        return 1
    fi
    
    if [[ ! -x "${script_path}" ]]; then
        if chmod "${SCRIPT_PERMS}" "${script_path}"; then
            log_info "Made executable ${SCRIPT_PERMS}: ${description} (${script_path})" "${GREEN}"
            return 0
        else
            log_error "Failed to make executable: ${script_path}"
            return 1
        fi
    else
        log_info "Already executable: ${description} (${script_path})" "${CYAN}"
        return 0
    fi
}

# Function to fix log file permissions
fix_log() {
    local log_path="$1"
    local description="$2"
    
    if [ ! -f "${log_path}" ]; then
        log_warn "Log file not found, creating empty: ${log_path}"
        if touch "${log_path}"; then
            log_info "Created empty log: ${log_path}"
        else
            log_error "Failed to create log: ${log_path}"
            return 1
        fi
    fi
    
    if chmod "${LOG_PERMS}" "${log_path}"; then
        log_info "Fixed log permissions ${LOG_PERMS}: ${description} (${log_path})" "${GREEN}"
        return 0
    else
        log_error "Failed to set log permissions: ${log_path}"
        return 1
    fi
}

# Function to fix all module scripts
fix_modules() {
    log_info "=== Fixing Module Scripts ==="
    
    if [ ! -d "${MODULES_DIR}" ]; then
        log_error "Modules directory not found: ${MODULES_DIR}"
        return 1
    fi
    
    local module_count=0
    local success_count=0
    
    for module_file in "${MODULES_DIR}"/*.sh; do
        [[ -f "$module_file" ]] || continue
        ((module_count++))
        
        local module_name
        module_name=$(basename "$module_file")
        if fix_script "$module_file" "Module ${module_name}"; then
            ((success_count++))
        fi
    done
    
    if [ ${module_count} -eq 0 ]; then
        log_warn "No module scripts found in ${MODULES_DIR}"
    else
        log_info "Fixed ${success_count}/${module_count} module scripts" "${GREEN}"
    fi
    
    if [ ${success_count} -eq ${module_count} ]; then
        module_success=1
    else
        module_success=0
    fi
    return 0
}

# Function to show permission summary
show_summary() {
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}🔒 PERMISSION FIX SUMMARY${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
    
    local total_dirs=0
    local total_scripts=0
    local total_logs=0
    
    # Count directories
    for dir in offline logs modules scripts vendor roster file-roots pillar tools rpm .cache tmp; do
        if [ -d "${PROJECT_ROOT}/${dir}" ]; then
            ((total_dirs++))
            printf "${BLUE}📁 %s${NC}: ${DIR_PERMS}\n" "${dir}"
        fi
    done
    
    # Count main scripts
    for script in salt-shaker.sh; do
        if [ -f "${PROJECT_ROOT}/${script}" ]; then
            ((total_scripts++))
            printf "${GREEN}⚙️  %s${NC}: ${SCRIPT_PERMS}\n" "${script}"
        fi
    done
    
    # Count module scripts
    if [ -d "${MODULES_DIR}" ]; then
        local module_count
        module_count=$(find "${MODULES_DIR}" -name "*.sh" -type f 2>/dev/null | wc -l)
        ((total_scripts += module_count))
        printf "${GREEN}⚙️  Modules${NC}: ${SCRIPT_PERMS} (${module_count} files)\n"
    fi
    
    # Count log files
    for log in salt-shaker.log salt-shaker-errors.log; do
        if [ -f "${LOG_DIR}/${log}" ]; then
            ((total_logs++))
            printf "${YELLOW}📄 %s${NC}: ${LOG_PERMS}\n" "${log}"
        fi
    done
    
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
    printf "${WHITE}📊 TOTAL:${NC} %d dirs (${DIR_PERMS}), %d scripts (${SCRIPT_PERMS}), %d logs (${LOG_PERMS})\n" \
        "${total_dirs}" "${total_scripts}" "${total_logs}"
    echo -e "${GREEN}✅ Permissions fixed successfully!${NC}"
    echo -e "${YELLOW}💡 Now safe to run as non-root user${NC}"
}

# Function to show about information
show_about() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC} ${CYAN}              F I X • P E R M I S S I O N S${NC} ${WHITE}About${NC} ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    cat << EOF
║ fix-permissions.sh is a one-off utility to set proper permissions for the    ║
║ existing Salt Shaker project structure. Run as root during initial setup only.║
║                                                                              ║
║ ${GREEN}Key Features:${NC}                                                       ║
║   • ${WHITE}Directory permissions${NC} - Sets all directories to 755            ║
║   • ${WHITE}Script executables${NC} - Makes all .sh files executable (755)      ║
║   • ${WHITE}Log files${NC} - Sets proper read/write permissions (644)           ║
║   • ${WHITE}Root only${NC} - Must be run with sudo for security                  ║
║   • ${WHITE}Idempotent${NC} - Safe to re-run, skips existing permissions        ║
║                                                                              ║
║ ${GREEN}Sets:${NC}                                                             ║
║   • ${WHITE}Directories${NC}: 755 (drwxr-xr-x)                                  ║
║   • ${WHITE}Scripts${NC}: 755 (-rwxr-xr-x)                                      ║
║   • ${WHITE}Logs${NC}: 644 (-rw-r--r--)                                         ║
║                                                                              ║
║ ${GREEN}Usage:${NC} Run from project root: sudo ./scripts/fix-permissions.sh    ║
║ ${GREEN}AIR-GAPPED SAFE:${NC} No internet or package dependencies               ║
║                                                                              ║
║ ${GREEN}Created by:${NC} T03KNEE                                                ║
║ ${GREEN}Version:${NC} 1.3                                                       ║
║ ${GREEN}Date:${NC} $(date '+%m/%d/%Y')                                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo ""
    echo -e "${YELLOW}⚠️  ONE-OFF UTILITY - Run only during initial setup or permission reset${NC}"
}

# Function to show help
show_help() {
    cat << EOF
${WHITE}Usage:${NC} sudo ${0##*/} [OPTIONS]

${CYAN}fix-permissions.sh${NC} - Fix Salt Shaker Project Permissions (Root Only)

${GREEN}Options:${NC}
    -h          Show this help message
    -a          Show about information
    -d          Dry run - Show what would be fixed (no changes)

${GREEN}Examples:${NC}
    sudo ${0##*/}                          # Fix all permissions
    sudo ${0##*/} -d                      # Dry run (show changes only)
    sudo ./scripts/fix-permissions.sh     # Run from scripts directory

${YELLOW}Requirements:${NC}
    • MUST RUN AS ROOT (use sudo)
    • Project directories already created (run 01-init-dirs.sh first)
    • No internet or package dependencies

${CYAN}What it does:${NC}
    1. Sets all directories to 755 permissions
    2. Makes all .sh scripts executable (755)
    3. Sets log files to readable (644)
    4. Validates permission changes

${WHITE}⚠️  RUN AS ROOT ONLY - One-off utility for initial setup${NC}
${WHITE}For more information, run: sudo ${0##*/} -a${NC}
EOF
}

#===============================================================
# Error Trapping and Signal Handling
#===============================================================
trap 'log_error "Script interrupted at line ${LINENO}"; exit 1' INT TERM

#===============================================================
# Main Script Logic
#===============================================================

# Parse command-line arguments
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case ${1} in
        -h)
            show_help
            exit 0
            ;;
        -a)
            show_about
            exit 0
            ;;
        -d)
            DRY_RUN=true
            log_info "DRY RUN MODE - No changes will be made" "${YELLOW}"
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help >&2
            exit 1
            ;;
    esac
    shift
done

# Check if running as root
check_root

# Validate project root
if [ ! -d "${PROJECT_ROOT}" ] || [ ! -w "${PROJECT_ROOT}" ]; then
    log_error "Project root '${PROJECT_ROOT}' not found or not writable"
    exit 1
fi

log_info "=== Starting Permission Fix for Salt Shaker Project ==="
log_info "Project Root: ${PROJECT_ROOT}"
log_info "Mode: ${DRY_RUN:+DRY RUN - no changes}"

echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}🔒 FIXING SALT SHAKER PERMISSIONS${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
if [ "${DRY_RUN}" = true ]; then
    echo -e "${YELLOW}👀 DRY RUN MODE - Showing what would be fixed${NC}"
fi
echo ""

# Fix starter directories
log_info "=== Fixing Starter Directories ==="
declare -A starter_dirs=(
    ["offline"]="Offline resources directory"
    ["logs"]="Project logging directory"
    ["modules"]="Module scripts directory"
    ["scripts"]="Utility scripts directory"
    ["vendor"]="Extracted vendor binaries"
    ["roster"]="Salt-SSH roster files"
    ["file-roots"]="Salt state files"
    ["pillar"]="Pillar configuration data"
    ["tools"]="Helper tools"
    ["rpm"]="RPM specification files"
    [".cache"]="Salt cache directory"
    ["tmp"]="Temporary files directory"
)

for dir in "${!starter_dirs[@]}"; do
    ((dir_total++))
    if fix_directory "${PROJECT_ROOT}/${dir}" "${starter_dirs[$dir]}"; then
        ((dir_success++))
    fi
done

# Fix main script
log_info "=== Fixing Main Script ==="
if fix_script "${PROJECT_ROOT}/salt-shaker.sh" "Main menu script"; then
    script_success=1
fi

# Fix all module scripts
if fix_modules; then
    module_success=1
fi

# Fix log files
log_info "=== Fixing Log Files ==="
for log_file in "salt-shaker.log" "salt-shaker-errors.log"; do
    ((log_total++))
    if fix_log "${LOG_DIR}/${log_file}" "${log_file}"; then
        ((log_success++))
    fi
done

# Show summary
show_summary

# Final validation - FIXED: Proper variable initialization and logic
if [ "${dir_success}" -eq "${dir_total}" ] && [ "${script_success}" -eq 1 ] && [ "${module_success}" -eq 1 ] && [ "${log_success}" -eq "${log_total}" ]; then
    log_info "=== All permissions fixed successfully ===" "${GREEN}"
    echo -e "${GREEN}🎉 Permission fix completed! Project is ready.${NC}"
    echo -e "${CYAN}💡 You can now run Salt-Shaker.sh as a regular user${NC}"
else
    log_warn "=== Permission fix completed with some warnings (missing optional dirs?) ===" "${ORANGE}"
    echo -e "${YELLOW}⚠️ Permission fix completed with warnings${NC}"
    echo -e "${YELLOW}💡 Check the logs; missing dirs are optional but recommended${NC}"
fi

log_info "fix-permissions.sh completed successfully"
exit 0
