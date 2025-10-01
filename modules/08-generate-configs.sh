#!/bin/bash
#===============================================================
#Script Name: 08-generate-configs.sh
#Date: 09/27/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Generate sample Salt configurations
#About: Generates sample Salt configurations, including master config, roster template from CSV, state/pillar files. Prompts for target pod (network) and generates YAML roster file from the CSV created by module 02. Outputs: conf/master, roster/roster_build.ini, file-roots/top.sls/init.sls, pillar/top.sls/data.sls. Designed for air-gapped environments, uses only native bash and coreutils, ensuring compatibility across Red Hat 7.9, Rocky 8.x, and EL9 systems. Supports interactive pod selection, comprehensive logging, and error handling. No package installations required.
#===============================================================

#===============================================================
# Configuration Section - Edit variables here as needed
#===============================================================
PROJECT_ROOT="${PWD}"  # Project root (defaults to current)
CSV_FILE="${PROJECT_ROOT}/roster/data/hosts_all_pods.csv"  # CSV from module 02
ROSTER_DIR="${PROJECT_ROOT}/roster"
ROSTER_FILE="${ROSTER_DIR}/hosts.yml"  # Generated YAML roster
CONF_DIR="${PROJECT_ROOT}/conf"
FILE_ROOTS_DIR="${PROJECT_ROOT}/file-roots"
PILLAR_DIR="${PROJECT_ROOT}/pillar"
LOG_DIR="${PROJECT_ROOT}/logs"
MAIN_LOG="${LOG_DIR}/salt-shaker.log"
ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
DIR_PERMS="700"  # Directories: user rwx, group/world none
FILE_PERMS="600"  # Files: user rw, group/world none
SCRIPT_PERMS="755"  # Scripts: user rwx, group/world rx

# Color definitions for professional appearance (terminal-safe)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
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
    
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    echo -e "${color}${message}${NC}"
}

# Function to log errors
log_error() {
    local message="$1"
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${message}" >> "${ERROR_LOG}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    echo -e "${RED}[ERROR] ${message}${NC}" >&2
}

# Function to log warnings
log_warn() {
    local message="$1"
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    echo -e "${YELLOW}[WARN] ${message}${NC}" >&2
}

# Function to pause and wait for user input
pause() {
    local message="${1:-Press Enter to continue...}"
    echo -e "${CYAN}${message}${NC}"
    read -r -e
}

# Function to get user input with validation
get_user_input() {
    local prompt="$1" default="$2" input
    echo -e "${CYAN}${prompt} [default: ${default}]: ${NC}"
    read -r -e input
    input="${input:-${default}}"
    echo "${input}"
}

# Function to validate CSV file
validate_csv() {
    local csv="$1"
    if [ ! -r "${csv}" ]; then
        log_error "CSV file not found or not readable: ${csv}"
        return 1
    fi
    # Basic validation: check header
    head -n1 "${csv}" | grep -q "pod,target,host,ip,port,user,passwd,sudo,ssh_args,description" || {
        log_error "Invalid CSV header in ${csv}"
        return 1
    }
    log_info "CSV validated: ${csv}"
    return 0
}

# Function to generate master config
generate_master_config() {
    local conf_file="${CONF_DIR}/master"
    mkdir -p "${CONF_DIR}" 2>/dev/null || true
    {
        echo "# Sample Salt master config for Salt Shaker"
        echo "interface: 0.0.0.0"
        echo "publish_port: 4505"
        echo "ret_port: 4506"
        echo "file_roots:"
        echo "  base:"
        echo "    - ${FILE_ROOTS_DIR}"
        echo "pillar_roots:"
        echo "  base:"
        echo "    - ${PILLAR_DIR}"
    } > "${conf_file}"
    chmod "${FILE_PERMS}" "${conf_file}" 2>/dev/null || true
    log_info "Generated master config: ${conf_file}"
}

# Function to generate state files
generate_state_files() {
    local top_sls="${FILE_ROOTS_DIR}/top.sls"
    local init_sls="${FILE_ROOTS_DIR}/init.sls"
    mkdir -p "${FILE_ROOTS_DIR}" 2>/dev/null || true
    {
        echo "base:"
        echo "  '*':"
        echo "    - init"
    } > "${top_sls}"
    {
        echo "echo_test:"
        echo "  cmd.run:"
        echo "    - name: echo 'Hello from Salt Shaker'"
    } > "${init_sls}"
    chmod "${FILE_PERMS}" "${top_sls}" "${init_sls}" 2>/dev/null || true
    log_info "Generated state files: ${top_sls}, ${init_sls}"
}

# Function to generate pillar files
generate_pillar_files() {
    local top_sls="${PILLAR_DIR}/top.sls"
    local data_sls="${PILLAR_DIR}/data.sls"
    mkdir -p "${PILLAR_DIR}" 2>/dev/null || true
    {
        echo "base:"
        echo "  '*':"
        echo "    - data"
    } > "${top_sls}"
    {
        echo "message: 'Sample pillar data from Salt Shaker'"
    } > "${data_sls}"
    chmod "${FILE_PERMS}" "${top_sls}" "${data_sls}" 2>/dev/null || true
    log_info "Generated pillar files: ${top_sls}, ${data_sls}"
}

# Function to generate roster from CSV
generate_roster() {
    local pod="$1"
    mkdir -p "${ROSTER_DIR}" 2>/dev/null || true
    {
        awk -F, -v pod="${pod}" 'NR==1 {next} $1 == pod {print $2 ":\n  host: " $3 "\n  ip: " $4 "\n  port: " $5 "\n  user: " $6 "\n  passwd: " $7 "\n  sudo: " $8 "\n  ssh_args: " $9 "\n  description: " $10}' "${CSV_FILE}"
    } > "${ROSTER_FILE}"
    if [ -s "${ROSTER_FILE}" ]; then
        chmod "${FILE_PERMS}" "${ROSTER_FILE}" 2>/dev/null || true
        log_info "Generated roster file for pod ${pod}: ${ROSTER_FILE}"
    else
        log_error "No entries found for pod ${pod} in ${CSV_FILE}"
    fi
}

#===============================================================
# Error Trapping and Signal Handling
#===============================================================
trap 'log_error "Script interrupted at line ${LINENO}"; exit 1' INT TERM

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
        -*)
            log_error "Unknown option: $1"
            show_help >&2
            exit 1
            ;;
    esac
    shift
done

# Validate CSV
if ! validate_csv "${CSV_FILE}"; then
    exit 1
fi

# Prompt for pod
POD_NAME=$(get_user_input "Enter target pod (e.g., prod, dev, test)" "prod")

# Generate files
generate_master_config
generate_state_files
generate_pillar_files
generate_roster "${POD_NAME}"

# Success message
bar
log_info "Configuration generation completed successfully for pod: ${POD_NAME}"
log_info "Next steps:"
log_info "   1. Review and edit generated files if needed."
log_info "   2. Run salt-ssh using the generated roster: PYTHONPATH=${PROJECT_ROOT}/vendor/el7/salt/lib/python3.10/site-packages ${PROJECT_ROOT}/vendor/el7/salt/bin/salt-ssh '*' test.ping --thin-dir ${OUT_DIR} --roster-file ${ROSTER_FILE}"
bar
pause
exit 0
