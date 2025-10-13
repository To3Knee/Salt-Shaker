#!/bin/bash

#===============================================================
#Script Name: Salt-Shaker.sh
#Date: 09/20/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.11
#Short: Main menu system for Salt Shaker project
#About: Salt-Shaker.sh is the main entry point and professional menu system for the Salt Shaker project. This script dynamically discovers and loads numbered module scripts from the modules/ directory, creating a clean, color-coded, user-friendly menu interface. It handles module execution with comprehensive error trapping, logging to logs/salt-shaker.log, and provides real-time feedback. The menu supports pagination for large module lists, module descriptions, and graceful handling of missing or invalid modules. Designed for air-gapped environments, it uses only native bash and coreutils, ensuring compatibility across Red Hat 7.9, Rocky 8.x, and future EL9 systems without any package installations. Version 1.11 includes polished display formatting, improved about text parsing, and enhanced module execution feedback.
#===============================================================

#===============================================================
# Configuration Section - Edit variables here as needed
#===============================================================
PROJECT_ROOT="${PWD}"  # Project root directory (defaults to current working directory)
MODULES_DIR="${PROJECT_ROOT}/modules"  # Directory containing numbered module scripts
LOG_DIR="${PROJECT_ROOT}/logs"  # Log directory within project
MAIN_LOG="${LOG_DIR}/salt-shaker.log"  # Main log file for all operations
ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"  # Dedicated error log
MODULE_PERMS="755"  # Permissions for executable modules (u+rwx, g+rx, o+rx)
MAX_MENU_ITEMS=15  # Maximum items to display per menu page (for pagination)
VERSION="1.11"  # Fixed version variable
DELIMITER="|"  # Safe delimiter for module info parsing (avoids conflicts with : in descriptions)

# Color definitions for professional appearance (terminal-safe)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m' # No Color
else
    RED="" GREEN="" YELLOW="" BLUE="" PURPLE="" CYAN="" WHITE="" NC=""
fi

#===============================================================
# Functions
#===============================================================

# Function to log messages with color-coded console output
log_info() {
    local message="$1"
    local color="$2"
    [ -z "${color}" ] && color="${GREEN}"
    
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}" 2>/dev/null || {
        echo "${YELLOW}Warning: Could not create ${LOG_DIR}, logging to stdout${NC}" >&2
    }
    
    # Log to file with timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    
    # Color-coded console output
    echo -e "${color}${message}${NC}"
}

# Function to log errors with red highlighting
log_error() {
    local message="$1"
    
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    
    # Log to both error file and main log
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${message}" >> "${ERROR_LOG}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    
    # Red console output
    echo -e "${RED}[ERROR] ${message}${NC}" >&2
}

# Function to log warnings with yellow highlighting
log_warn() {
    local message="$1"
    
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    
    # Log to main log
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    
    # Yellow console output
    echo -e "${YELLOW}[WARN] ${message}${NC}" >&2
}

# Function to pause and wait for user input
pause() {
    local message="${1:-Press Enter to continue...}"
    echo -e "${CYAN}${message}${NC}"
    read -r -e
}

# Function to get user input with validation and backspace support
get_user_input() {
    local prompt="$1"
    local default="${2:-}"
    local input=""
    
    if [ -n "${default}" ]; then
        prompt="${prompt} [${default}]: "
    else
        prompt="${prompt}: "
    fi
    
    read -r -e -p "$(echo -e "${GREEN}${prompt}${NC}")" input
    
    if [ -z "${input}" ]; then
        echo "${default}"
    else
        echo "${input}"
    fi
}

# Function to validate project structure
validate_project() {
    log_info "Validating Salt Shaker project structure..." "${WHITE}"
    
    if [ ! -d "${MODULES_DIR}" ]; then
        log_error "Modules directory '${MODULES_DIR}' not found. Please create it and add module scripts."
        log_info "To create the full project structure, run: ./modules/01-init-dirs.sh" "${YELLOW}"
        return 1
    fi
    
    if [ ! "$(ls -A "${MODULES_DIR}" 2>/dev/null)" ]; then
        log_warn "No module scripts found in '${MODULES_DIR}'. Run 01-init-dirs.sh to initialize the project."
        return 1
    fi
    
    log_info "Project structure validation passed." "${GREEN}"
    return 0
}

# Function to detect OS for compatibility logging
detect_os() {
    if [ -f /etc/redhat-release ]; then
        local os_info
        os_info=$(cat /etc/redhat-release 2>/dev/null | head -n1)
        log_info "Detected OS: ${os_info}" "${WHITE}"
        echo "${os_info}" > "${LOG_DIR}/os-detection.log" 2>/dev/null || true
    else
        log_info "OS Detection: Assuming Red Hat compatible system (EL7/EL8/EL9)" "${WHITE}"
    fi
}

# Helper function for short OS detection
detect_os_short() {
    if [ -f /etc/redhat-release ]; then
        grep -oE '(Red Hat|Rocky|CentOS).*([0-9]+\.[0-9]+)' /etc/redhat-release 2>/dev/null | head -n1 || echo "Red Hat Compatible"
    else
        echo "Unknown"
    fi
}

# IMPROVED Module parsing - Better about text extraction
get_module_info() {
    local module_path="$1"
    local num name short_desc long_desc
    
    # Extract number and name from filename
    local filename
    filename=$(basename "$module_path")
    if [[ "$filename" =~ ^([0-9]{2})-(.+)\.sh$ ]]; then
        num="${BASH_REMATCH[1]}"
        name="${BASH_REMATCH[2]}"
    else
        echo ":${filename}:No description:No description:${module_path}"
        return
    fi
    
    # Get short description from #Short: line
    short_desc=$(grep "^#Short:" "$module_path" 2>/dev/null | head -1 | sed 's/^#Short: *//')
    if [ -z "$short_desc" ]; then
        short_desc="${name^} module"
    fi
    
    # IMPROVED: Get long description from after #About: (first non-empty line after header)
    local about_line
    about_line=$(sed -n '/^#About:/{n; :loop; n; /^#=/q; /^# *$/b loop; s/^# *//; p; q}' "$module_path" 2>/dev/null)
    
    if [ -z "$about_line" ]; then
        about_line="${name^} - Detailed functionality not specified"
    fi
    
    # Output in safe pipe-separated format (no | expected in names/descriptions)
    printf "%s%s%s%s%s%s%s%s%s\n" "$num" "$DELIMITER" "$name" "$DELIMITER" "$short_desc" "$DELIMITER" "$about_line" "$DELIMITER" "$module_path"
}

# FIXED: Robust sorting function that properly populates array
sort_modules() {
    local -n modules_array="$1"  # Nameref to input array
    local -n sorted_array="$2"   # Nameref to output array
    
    # Create temp file with numbered lines for sorting
    local temp_file=$(mktemp)
    local i=0
    for module in "${modules_array[@]}"; do
        echo "$module" >> "$temp_file"
        ((i++))
    done
    
    # Sort by first field (module number) and repopulate array
    local line_num=0
    while IFS= read -r line; do
        sorted_array[line_num]="$line"
        ((line_num++))
    done < <(sort -t"$DELIMITER" -k1n "$temp_file")
    
    rm -f "$temp_file"
    log_info "Sorted ${line_num} modules by number" "${CYAN}"
}

# Function to build and display the menu - FIXED DISPLAY FORMATTING
build_menu() {
    log_info "Scanning for modules in '${MODULES_DIR}'..." "${WHITE}"
    
    local -a modules=()
    local module_count=0
    
    # Simple file scanning
    for module_file in "${MODULES_DIR}"/*.sh; do
        [[ -f "$module_file" ]] || continue
        local info
        info=$(get_module_info "$module_file")
        
        # Parse with safe delimiter
        local IFS="$DELIMITER"
        local -a fields
        read -ra fields <<< "$info"
        local num="${fields[0]}"
        local name="${fields[1]}"
        local short_desc="${fields[2]}"
        local long_desc="${fields[3]}"
        local path="${fields[4]}"
        
        if [ -n "$num" ] && [ -n "$name" ] && [[ "$num" =~ ^[0-9]{2}$ ]]; then
            # Ensure executable
            if [ ! -x "$module_file" ]; then
                chmod +x "$module_file" 2>/dev/null || true
            fi
            
            modules[$module_count]="$num$DELIMITER$name$DELIMITER$short_desc$DELIMITER$long_desc$DELIMITER$module_file"
            ((module_count++))
            log_info "Loaded module: $num - $name ($short_desc)" "${CYAN}"
        else
            log_warn "Skipping invalid module: $module_file (missing number/name format)"
        fi
    done
    
    if [ $module_count -eq 0 ]; then
        clear
        display_header
        echo -e "${PURPLE}┌─ ${WHITE}Salt Shaker Menu${PURPLE} ──────────────────────────────────────────────────────┐${NC}"
        echo -e "${PURPLE}│${NC}"
        echo -e "${YELLOW}│ No modules found. Please initialize the project first.${NC}"
        echo -e "${YELLOW}│${NC}"
        echo -e "${YELLOW}│ To get started:${NC}"
        echo -e "${YELLOW}│   1. Create modules/01-init-dirs.sh with the proper header format${NC}"
        echo -e "${YELLOW}│   2. Make it executable: chmod +x modules/01-init-dirs.sh${NC}"
        echo -e "${YELLOW}│   3. Run it to create the full project structure${NC}"
        echo -e "${YELLOW}│   4. The menu will automatically detect new modules${NC}"
        echo -e "${PURPLE}│${NC}"
        echo -e "${PURPLE}└─${NC} ${WHITE}Options:${NC} ${YELLOW}[${CYAN}Q${YELLOW}]uit  [${CYAN}R${YELLOW}]efresh  [${CYAN}H${YELLOW}]elp${NC}"
        echo ""
        
        local choice
        choice=$(get_user_input "Select option (Q/R/H)" "Q")
        
        case "${choice^^}" in
            Q|QUIT)
                display_goodbye
                exit 0
                ;;
            R|REFRESH)
                log_info "Refreshing module list..." "${WHITE}"
                build_menu
                ;;
            H|HELP)
                show_help_menu
                pause
                build_menu
                ;;
            *)
                display_goodbye
                exit 0
                ;;
        esac
        return
    fi
    
    # FIXED: Sort modules using dedicated function
    local -a sorted_modules=()
    sort_modules modules sorted_modules
    
    log_info "Found ${#sorted_modules[@]} valid modules ready for display" "${GREEN}"
    
    # Display menu with pagination
    local page=0
    local total_pages=$(( (${#sorted_modules[@]} + MAX_MENU_ITEMS - 1) / MAX_MENU_ITEMS ))
    local choice=""
    
    while true; do
        clear
        display_header
        
        echo -e "${PURPLE}┌─ ${WHITE}Salt Shaker Menu${PURPLE} ──────────────────────────────────────────────────────┐${NC}"
        echo -e "${PURPLE}│${NC}"
        
        local start=$((page * MAX_MENU_ITEMS))
        local end=$(((page + 1) * MAX_MENU_ITEMS))
        [ $end -gt ${#sorted_modules[@]} ] && end=${#sorted_modules[@]}
        
        for ((i=start; i<end; i++)); do
            local IFS="$DELIMITER"
            local -a fields
            read -ra fields <<< "${sorted_modules[i]}"
            local num="${fields[0]}"
            local name="${fields[1]}"
            local short_desc="${fields[2]}"
            local long_desc="${fields[3]}"
            local path="${fields[4]}"
            
            local option_num=$((i - start + 1))
            local display_num=$((page * MAX_MENU_ITEMS + option_num))
            
            # FIXED: Use SHORT description for menu display (max 40 chars)
            local menu_desc="${short_desc:0:40}"
            [ ${#short_desc} -gt 40 ] && menu_desc="${menu_desc}..."
            
            # FIXED: Proper display formatting - no double dots
            local display_text="${display_num}."
            printf "│ %2s ${CYAN}%-20s${NC} - ${WHITE}%s${NC}\n" \
                "${display_text}" "${name}" "${menu_desc}"
        done
        
        echo -e "${PURPLE}│${NC}"
        echo -e "${PURPLE}└─${NC} ${WHITE}Options:${NC} ${YELLOW}[${CYAN}Q${YELLOW}]uit  [${CYAN}N${YELLOW}]ext  [${CYAN}P${YELLOW}]rev  [${CYAN}R${YELLOW}]efresh  [${CYAN}H${YELLOW}]elp${NC}"
        echo -e "${PURPLE}   Page ${page}/${total_pages}  (${#sorted_modules[@]} modules loaded)${NC}"
        echo ""
        
        choice=$(get_user_input "Select option (number/Q/N/P/R/H)" "")
        
        case "${choice^^}" in
            Q|QUIT)
                display_goodbye
                exit 0
                ;;
            N|NEXT)
                [ $((page + 1)) -lt $total_pages ] && ((page++))
                ;;
            P|PREV|PREVIOUS)
                [ $page -gt 0 ] && ((page--))
                ;;
            R|REFRESH)
                log_info "Refreshing module list..." "${WHITE}"
                build_menu
                return
                ;;
            H|HELP)
                show_help_menu
                pause
                continue
                ;;
            "")
                continue
                ;;
            *)
                if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le $((end - start)) ]; then
                    local selected_index=$((start + choice - 1))
                    local IFS="$DELIMITER"
                    local -a fields
                    read -ra fields <<< "${sorted_modules[selected_index]}"
                    local num="${fields[0]}"
                    local name="${fields[1]}"
                    local short_desc="${fields[2]}"
                    local long_desc="${fields[3]}"
                    local path="${fields[4]}"
                    
                    # IMPROVED: Better description display with word wrapping
                    echo -e "${GREEN}Executing Module ${num}: ${CYAN}${name}${NC}"
                    echo -e "${WHITE}Description:${NC} ${long_desc:0:80}"
                    if [ ${#long_desc} -gt 80 ]; then
                        echo -e "           ${long_desc:80:80}"
                    fi
                    pause "Press Enter to execute or Ctrl+C to cancel"
                    
                    if execute_module "${path}" "${name}" "${long_desc}"; then
                        log_info "Module '${name}' completed successfully." "${GREEN}"
                        echo -e "${GREEN}✓ Module ${num} - ${name} executed successfully${NC}"
                        pause "Press Enter to return to menu"
                    else
                        log_error "Module '${name}' failed. Check logs in ${LOG_DIR}/"
                        echo -e "${RED}✗ Module ${num} - ${name} execution failed${NC}"
                        pause "Press Enter to return to menu"
                    fi
                else
                    log_warn "Invalid selection. Please choose a number from 1-${((end - start))} or Q/N/P/R/H"
                    pause
                fi
                ;;
        esac
    done
}

# Function to execute a module with error handling
execute_module() {
    local module_path="$1"
    local module_name="${2:-$(basename "${module_path}" .sh)}"
    local module_long_desc="$3"
    
    if [ ! -x "${module_path}" ]; then
        chmod +x "${module_path}" 2>/dev/null || {
            log_error "Failed to make module '${module_name}' executable"
            return 1
        }
    fi
    
    pushd "${PROJECT_ROOT}" >/dev/null
    
    log_info "Starting execution of module: ${module_name}" "${WHITE}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📦 MODULE OUTPUT: ${module_name}${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
    
    set +e
    local exit_code
    if "${module_path}"; then
        exit_code=0
    else
        exit_code=$?
    fi
    set -e
    
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${NC}"
    
    if [ ${exit_code} -eq 0 ]; then
        log_info "Module '${module_name}' completed successfully" "${GREEN}"
        popd >/dev/null
        return 0
    else
        log_error "Module '${module_name}' returned exit code ${exit_code}"
        popd >/dev/null
        return 1
    fi
}

# Function to display professional header
display_header() {
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC} ${PURPLE}                    S A L T • S H A K E R${NC} ${WHITE}v${VERSION}${NC} ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC} ${CYAN}Portable SaltStack Automation for Air-Gapped Environments${NC} ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC} ${GREEN}Project:${NC} ${WHITE}${PROJECT_ROOT}${NC} ${WHITE}│${NC} ${GREEN}OS:${NC} $(detect_os_short) ${WHITE}│${NC} ${GREEN}Modules:${NC} $(find "${MODULES_DIR}" -name '[0-9][0-9]-*.sh' -type f 2>/dev/null | wc -l) ${NC}║${NC}"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to show help menu
show_help_menu() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC} ${CYAN}                    S A L T • S H A K E R${NC} ${WHITE}Help Menu${NC} ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    cat << 'EOF'
║ Navigation:                                                                  ║
║   • Enter a number to execute the corresponding module                       ║
║   • [Q] Quit - Exit the Salt Shaker application                              ║
║   • [N] Next - Go to next page of modules                                    ║
║   • [P] Previous - Go to previous page of modules                            ║
║   • [R] Refresh - Reload modules from modules/ directory                     ║
║   • [H] Help - Show this help menu                                           ║
║                                                                              ║
║ Adding Modules:                                                              ║
║   1. Create a new script in modules/ with format: [NN]-name-description.sh   ║
║   2. Make it executable: chmod +x modules/NN-name.sh                         ║
║   3. Add #Short: and #About: fields in the script header                     ║
║   4. The menu will automatically detect and display it                       ║
║                                                                              ║
║ Module Header Format:                                                        ║
║ #Short: One-line description (max 40 chars)                                  ║
║ #About: Full detailed description                                            ║
║                                                                              ║
║ Logging: All operations logged to logs/salt-shaker.log                       ║
║ Errors logged to: logs/salt-shaker-errors.log                                ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# Function to show about information
show_about() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC} ${CYAN}                    S A L T • S H A K E R${NC} ${WHITE}About${NC} ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    cat << EOF
║ Salt Shaker is a portable, air-gapped SaltStack automation framework designed ║
║ for secure environments requiring zero internet connectivity.                 ║
║                                                                              ║
║ ${GREEN}Key Features:${NC}                                                       ║
║   • ${WHITE}No package installations${NC} - Uses RPM extraction and native tools    ║
║   • ${WHITE}Cross-platform${NC} - Compatible with Red Hat 7.9, Rocky 8.x, EL9     ║
║   • ${WHITE}Modular design${NC} - Add/remove functionality without code changes    ║
║   • ${WHITE}Professional UI${NC} - Color-coded menus with pagination and help      ║
║   • ${WHITE}Comprehensive logging${NC} - Detailed operation tracking and errors    ║
║                                                                              ║
║ ${GREEN}Created by:${NC} T03KNEE                                                ║
║ ${GREEN}GitHub:${NC} https://github.com/To3Knee/Salt-Shaker                       ║
║ ${GREEN}Version:${NC} ${VERSION}                                            ║
║ ${GREEN}Date:${NC} $(date '+%m/%d/%Y')                                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo ""
    pause "Press Enter to return to main menu"
}

# Function to display goodbye message
display_goodbye() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC} ${PURPLE}                    S A L T • S H A K E R${NC} ${WHITE}Thank You!${NC} ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║${NC} ${GREEN}Thank you for using Salt Shaker!${NC} ${WHITE}                    ║${NC}"
    echo -e "${WHITE}║${NC} ${YELLOW}Check logs in ${LOG_DIR} for operation details.${NC} ${WHITE}║${NC}"
    echo -e "${WHITE}║${NC} ${CYAN}Happy Automating!${NC}                                 ${WHITE}║${NC}"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to show command line help
show_help() {
    cat << EOF
${WHITE}Usage:${NC} $0 [OPTIONS]

${PURPLE}Salt Shaker${NC} - Portable SaltStack Automation Framework

${GREEN}Options:${NC}
    -h, --help     Show this help message
    -a, --about    Show detailed about information
    -v, --version  Show version information
    -d PATH, --dir PATH  Specify project root directory (default: current directory)
    -l, --list     List available modules without entering menu
    -m MODULE, --module MODULE  Execute specific module by name or number

${GREEN}Examples:${NC}
    $0                           # Start interactive menu (default)
    $0 -d /path/to/salt-shaker    # Use custom project directory
    $0 --list                    # Show available modules
    $0 -m 01                     # Execute module 01-init-dirs.sh
    $0 --module init-dirs        # Execute module by name

${YELLOW}Requirements:${NC}
    • Bash shell (native on EL7/EL8/EL9)
    • modules/ directory with numbered scripts (*.sh)
    • No package installations required
    • Compatible with Red Hat 7.9, Rocky 8.x, EL9 systems

${CYAN}Project Structure:${NC}
    Salt-Shaker.sh  (Main menu)
    ├── modules/    (Numbered module scripts)
    ├── logs/       (Operation logs)
    ├── offline/    (Air-gapped resources)
    └── ...         (Other project directories)

${WHITE}For more information, run: $0 -a${NC}
EOF
}

#===============================================================
# Error Trapping and Signal Handling
#===============================================================
trap 'log_error "Script interrupted by signal at line ${LINENO}. Cleaning up..."; display_goodbye; exit 1' INT TERM

#===============================================================
# Main Script Logic
#===============================================================

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case ${1} in
        -h|--help)
            show_help
            exit 0
            ;;
        -a|--about)
            show_about
            exit 0
            ;;
        -v|--version)
            echo -e "${PURPLE}Salt Shaker${NC} version ${VERSION}"
            echo "Built: $(date '+%Y-%m-%d')"
            exit 0
            ;;
        -d|--dir)
            shift
            PROJECT_ROOT="$1"
            MODULES_DIR="${PROJECT_ROOT}/modules"
            LOG_DIR="${PROJECT_ROOT}/logs"
            MAIN_LOG="${LOG_DIR}/salt-shaker.log"
            ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
            shift
            ;;
        -l|--list)
            if validate_project; then
                echo -e "${WHITE}Available Modules:${NC}"
                echo "========================"
                for module in "${MODULES_DIR}"/*.sh; do
                    [[ -f "$module" ]] || continue
                    local info
                    info=$(get_module_info "$module")
                    local IFS="$DELIMITER"
                    local -a fields
                    read -ra fields <<< "$info"
                    local num="${fields[0]}"
                    local name="${fields[1]}"
                    local short_desc="${fields[2]}"
                    if [ -n "$num" ] && [ -n "$name" ]; then
                        printf "%s. ${CYAN}%s${NC} - %s\n" "$num" "$name" "${short_desc:0:60}"
                    fi
                done
            fi
            exit 0
            ;;
        -m|--module)
            shift
            local module_arg="$1"
            if ! validate_project; then
                exit 1
            fi
            
            local found_module=""
            if [[ "${module_arg}" =~ ^[0-9]{2}$ ]]; then
                found_module=$(find "${MODULES_DIR}" -name "${module_arg}-*.sh" -type f 2>/dev/null | head -n1)
            else
                found_module=$(find "${MODULES_DIR}" -name "*${module_arg}*.sh" -type f 2>/dev/null | head -n1)
            fi
            
            if [ -n "$found_module" ]; then
                local info
                info=$(get_module_info "$found_module")
                local IFS="$DELIMITER"
                local -a fields
                read -ra fields <<< "$info"
                local num="${fields[0]}"
                local name="${fields[1]}"
                local short_desc="${fields[2]}"
                local long_desc="${fields[3]}"
                log_info "Executing module: ${name} (${short_desc})" "${GREEN}"
                execute_module "$found_module" "$name" "$long_desc"
            else
                log_error "Module '${module_arg}' not found"
                echo -e "${YELLOW}Available modules:${NC}"
                $0 --list
            fi
            exit $?
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help >&2
            exit 1
            ;;
        *)
            PROJECT_ROOT="$1"
            MODULES_DIR="${PROJECT_ROOT}/modules"
            LOG_DIR="${PROJECT_ROOT}/logs"
            MAIN_LOG="${LOG_DIR}/salt-shaker.log"
            ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
            shift
            ;;
    esac
done

# Validate project root directory
if [ ! -d "${PROJECT_ROOT}" ]; then
    log_error "Project root directory '${PROJECT_ROOT}' does not exist."
    log_info "Create it with: mkdir -p ${PROJECT_ROOT}" "${YELLOW}"
    exit 1
fi

if [ ! -w "${PROJECT_ROOT}" ]; then
    log_error "Project root directory '${PROJECT_ROOT}' is not writable."
    exit 1
fi

# Initialize logging directory
mkdir -p "${LOG_DIR}" 2>/dev/null || {
    log_error "Cannot create log directory '${LOG_DIR}'"
    exit 1
}

# Set proper permissions
chmod ${MODULE_PERMS} "${0}" 2>/dev/null || true

# Log startup
log_info "=== Salt Shaker Started ===" "${WHITE}"
log_info "Project Root: ${PROJECT_ROOT}" "${WHITE}"
detect_os

# Validate project structure
if ! validate_project; then
    log_info "Project validation failed. Use -h for help." "${YELLOW}"
    pause
    exit 1
fi

# Launch the menu
build_menu

# Cleanup and exit
log_info "=== Salt Shaker Exited ===" "${WHITE}"
exit 0
