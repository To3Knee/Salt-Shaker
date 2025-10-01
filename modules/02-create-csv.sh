#!/bin/bash
#===============================================================
# Script Name: 02-create-csv.sh
# Date: 09/28/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 2.5
# Short: Generate CSV template for Salt-SSH roster
# About: Creates a user-friendly CSV template for Salt-SSH roster at roster/data/hosts-all-pods.csv with a 10-field format: pod,target,host,ip,port,user,passwd,sudo,ssh_args,description. Includes sample entries for user-specified pod and additional pods (e.g., prod, dev, test). Ensures compatibility with Microsoft Excel and Linux editors (UTF-8, comma-delimited). Validates CSV syntax and sets secure permissions (644). Designed for air-gapped EL7/8/9 systems using bash/coreutils. Generates a README-roster-template.txt for editing guidance. Compatible with Salt Shaker workflow (05-build-thin-el7.sh, 06-check-vendors.sh, 07-remote-test.sh, 08-generate-configs.sh). Version 2.5 fixes syntax error (situations typo) and enhances directory creation checks.
#===============================================================

# Configuration
PROJECT_ROOT="${PWD}"
ROSTER_DIR="${PROJECT_ROOT}/roster"
CSV_FILE="${ROSTER_DIR}/data/hosts-all-pods.csv"
README_FILE="${ROSTER_DIR}/data/README-roster-template.txt"
LOG_DIR="${PROJECT_ROOT}/logs"
MAIN_LOG="${LOG_DIR}/salt-shaker.log"
ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"
CSV_PERMS="644"
SAMPLE_PODS=3
TEMP_CSV="${PROJECT_ROOT}/tmp/hosts-all-pods-$$.csv"

# Color definitions
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED="" GREEN="" YELLOW="" CYAN="" NC=""
fi

# Logging functions
log_info() {
    local msg="$1"
    mkdir -p "${LOG_DIR}" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${msg}" >> "${MAIN_LOG}" 2>/dev/null
    echo -e "${GREEN}${msg}${NC}"
}

log_error() {
    local msg="$1"
    mkdir -p "${LOG_DIR}" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${msg}" >> "${ERROR_LOG}" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${msg}" >> "${MAIN_LOG}" 2>/dev/null
    echo -e "${RED}[ERROR] ${msg}${NC}" >&2
}

log_warning() {
    local msg="$1"
    mkdir -p "${LOG_DIR}" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] ${msg}" >> "${MAIN_LOG}" 2>/dev/null
    echo -e "${YELLOW}[WARN] ${msg}${NC}" >&2
}

# User input function
get_user_input() {
    local prompt="$1"
    local default="$2"
    local input
    if [ -n "${default}" ]; then
        prompt="${prompt} [${default}]: "
    else
        prompt="${prompt}: "
    fi
    read -r -p "$(echo -e "${GREEN}${prompt}${NC}")" input
    echo "${input:-${default}}"
}

# Validate project structure
validate_project() {
    if [ ! -d "${PROJECT_ROOT}" ] || [ ! -w "${PROJECT_ROOT}" ]; then
        log_error "Project root '${PROJECT_ROOT}' not found or not writable"
        return 1
    fi
    if [ ! -d "${ROSTER_DIR}" ]; then
        log_error "Roster directory '${ROSTER_DIR}' not found. Run 01-init-dirs.sh first."
        return 1
    fi
    if [ ! -d "${ROSTER_DIR}/data" ]; then
        mkdir -p "${ROSTER_DIR}/data" || {
            log_error "Failed to create ${ROSTER_DIR}/data"
            return 1
        }
    fi
    if [ ! -w "${ROSTER_DIR}/data" ]; then
        log_error "Directory '${ROSTER_DIR}/data' is not writable. Check permissions with: ls -ld ${ROSTER_DIR}/data"
        return 1
    fi
    if [ ! -d "${PROJECT_ROOT}/tmp" ]; then
        mkdir -p "${PROJECT_ROOT}/tmp" || {
            log_error "Failed to create ${PROJECT_ROOT}/tmp"
            return 1
        }
    fi
    if [ ! -w "${PROJECT_ROOT}/tmp" ]; then
        log_error "Directory '${PROJECT_ROOT}/tmp' is not writable. Check permissions with: ls -ld ${PROJECT_ROOT}/tmp"
        return 1
    fi
    log_info "Project structure validated"
    return 0
}

# Generate CSV header
generate_csv_header() {
    echo "# Salt-SSH Roster CSV Template"
    echo "# Edit this file to add your hosts and credentials."
    echo "# Fields: pod,target,host,ip,port,user,passwd,sudo,ssh_args,description"
    echo "# Notes:"
    echo "# - Use commas to separate fields."
    echo "# - Replace placeholders (e.g., <YOUR_PASSWORD>) with actual values."
    echo "# - For Excel: Open with comma delimiter and UTF-8 encoding."
    echo "# - For Linux: Edit with vi, nano, or any text editor."
    echo "# - Avoid commas in field values to prevent parsing issues."
    echo "pod,target,host,ip,port,user,passwd,sudo,ssh_args,description"
}

# Generate sample pod data
generate_sample_data() {
    local pod="$1"
    echo "${pod},web-01-${pod},web-01.${pod}.example.com,10.0.0.10,22,admin,<YOUR_PASSWORD>,TRUE,-o StrictHostKeyChecking=no,Web server 01 in ${pod} environment"
    echo "${pod},web-02-${pod},web-02.${pod}.example.com,10.0.0.11,22,admin,<YOUR_PASSWORD>,TRUE,-o StrictHostKeyChecking=no,Web server 02 in ${pod} environment"
    echo "${pod},db-01-${pod},db-01.${pod}.example.com,10.0.0.20,22,admin,<YOUR_PASSWORD>,TRUE,-o StrictHostKeyChecking=no,Database server in ${pod} environment"
}

# Generate README file
generate_readme() {
    echo "Salt-SSH Roster CSV Editing Guide" > "${README_FILE}"
    echo "================================" >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "This guide explains how to edit ${CSV_FILE} for Salt-SSH roster configuration." >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "1. File Location:" >> "${README_FILE}"
    echo "   - CSV file: ${CSV_FILE}" >> "${README_FILE}"
    echo "   - Format: Comma-separated values (CSV) with 10 fields" >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "2. Fields Description:" >> "${README_FILE}"
    echo "   - pod: Environment identifier (e.g., prod, dev, test)" >> "${README_FILE}"
    echo "   - target: Unique alias for Salt commands (e.g., web-01-prod)" >> "${README_FILE}"
    echo "   - host: Hostname or IP address (e.g., web-01.prod.example.com)" >> "${README_FILE}"
    echo "   - ip: IP address (optional if host is an IP)" >> "${README_FILE}"
    echo "   - port: SSH port (default: 22)" >> "${README_FILE}"
    echo "   - user: SSH username (e.g., admin, root)" >> "${README_FILE}"
    echo "   - passwd: SSH password (replace <YOUR_PASSWORD> or use pillar for security)" >> "${README_FILE}"
    echo "   - sudo: TRUE/FALSE for sudo access" >> "${README_FILE}"
    echo "   - ssh_args: Additional SSH arguments (e.g., -o StrictHostKeyChecking=no)" >> "${README_FILE}"
    echo "   - description: Human-readable description (e.g., Web server in prod)" >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "3. Editing Instructions:" >> "${README_FILE}"
    echo "   - Excel:" >> "${README_FILE}"
    echo "     * Open the CSV in Excel." >> "${README_FILE}"
    echo "     * Ensure comma delimiter and UTF-8 encoding are selected." >> "${README_FILE}"
    echo "     * Replace sample data (e.g., <YOUR_PASSWORD>, 10.0.0.x) with actual values." >> "${README_FILE}"
    echo "     * Save as CSV without changing the format." >> "${README_FILE}"
    echo "   - Linux:" >> "${README_FILE}"
    echo "     * Use vi, nano, or any text editor (e.g., nano ${CSV_FILE})." >> "${README_FILE}"
    echo "     * Replace sample data with actual values." >> "${README_FILE}"
    echo "     * Avoid commas in field values to prevent parsing issues." >> "${README_FILE}"
    echo "     * Save with Unix line endings (\n)." >> "${README_FILE}"
    echo "   - Security:" >> "${README_FILE}"
    echo "     * Avoid storing plaintext passwords in the passwd field." >> "${README_FILE}"
    echo "     * Consider using Salt pillar or encrypted storage for credentials." >> "${README_FILE}"
    echo "     * Set file permissions to 644 (chmod 644 ${CSV_FILE})." >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "4. Example Entry:" >> "${README_FILE}"
    echo "   prod,web-01-prod,web-01.prod.example.com,10.0.0.10,22,admin,securepass,TRUE,-o StrictHostKeyChecking=no,Web server in production" >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "5. Next Steps:" >> "${README_FILE}"
    echo "   - Run 06-check-vendors.sh to validate the build." >> "${README_FILE}"
    echo "   - Run 07-remote-test.sh to test remote connectivity." >> "${README_FILE}"
    echo "   - Run 08-generate-configs.sh to generate the roster file from this CSV." >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "6. Troubleshooting:" >> "${README_FILE}"
    echo "   - Check logs: ${MAIN_LOG}, ${ERROR_LOG}" >> "${README_FILE}"
    echo "   - Ensure no commas in field values." >> "${README_FILE}"
    echo "   - Verify SSH access to hosts before running 07-remote-test.sh." >> "${README_FILE}"
    echo "" >> "${README_FILE}"
    echo "Created: $(date '+%m/%d/%Y')" >> "${README_FILE}"
    echo "Version: 2.5" >> "${README_FILE}"
}

# Validate CSV syntax
validate_csv() {
    local file="$1"
    if [ ! -f "${file}" ]; then
        log_error "CSV file '${file}' does not exist"
        return 1
    fi
    local line_count
    line_count=$(wc -l < "${file}")
    if [ "${line_count}" -lt 2 ]; then
        log_error "CSV file is empty or missing header"
        return 1
    fi
    local header
    header=$(grep -v '^#' "${file}" | head -n1)
    if [ "${header}" != "pod,target,host,ip,port,user,passwd,sudo,ssh_args,description" ]; then
        log_warning "CSV header incorrect. Expected: pod,target,host,ip,port,user,passwd,sudo,ssh_args,description"
        log_warning "Found: ${header}"
        return 1
    fi
    local line_num=0
    local header_seen=false
    while IFS= read -r line; do
        ((line_num++))
        if [[ "${line}" =~ ^[^#] ]]; then
            if [ "${header_seen}" = false ]; then
                header_seen=true
                continue
            fi
            if ! echo "${line}" | grep -qE '^[^,]+,[^,]+,[^,]+,[^,]+,[0-9]+,[^,]+,[^,]*,[TRUE|FALSE]+,[^,]+,[^,]+$'; then
                log_warning "Invalid CSV format at line ${line_num}: ${line}"
                return 1
            fi
        fi
    done < "${file}"
    log_info "CSV validated: ${line_count} lines"
    return 0
}

# Show help
show_help() {
    echo -e "${CYAN}Usage: ${0##*/} [OPTIONS]${NC}"
    echo ""
    echo -e "${CYAN}02-create-csv.sh - Generate Salt-SSH Roster CSV Template${NC}"
    echo ""
    echo -e "${GREEN}Options:${NC}"
    echo "  -h          Show this help message"
    echo "  -p POD      Specify pod name (default: prompt)"
    echo "  -n NUM      Number of sample pods (default: 3, max: 10)"
    echo "  -f          Force overwrite existing CSV"
    echo ""
    echo -e "${GREEN}Examples:${NC}"
    echo "  ${0##*/}                # Interactive mode"
    echo "  ${0##*/} -p prod -n 2  # Generate 2 pods starting with prod"
    echo "  ${0##*/} -f           # Force overwrite"
    echo ""
    echo -e "${YELLOW}Requirements:${NC}"
    echo "  - Bash shell (EL7/8/9)"
    echo "  - roster/data/ directory (from 01-init-dirs.sh)"
    echo ""
    echo -e "${CYAN}Output:${NC}"
    echo "  - ${CSV_FILE} - CSV template"
    echo "  - ${README_FILE} - Editing guide"
}

# Signal handling
trap 'log_error "Script interrupted"; rm -f "${TEMP_CSV}"; exit 1' INT TERM

# Main logic
FORCE_OVERWRITE=false
POD_NAME=""
NUM_PODS=${SAMPLE_PODS}

while [ $# -gt 0 ]; do
    case "$1" in
        -h) show_help; exit 0 ;;
        -p) shift; POD_NAME="$1" ;;
        -n) shift
            if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 10 ]; then
                log_error "Invalid number of pods: $1. Must be 1-10."
                exit 1
            fi
            NUM_PODS="$1"
            ;;
        -f) FORCE_OVERWRITE=true ;;
        *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

if ! validate_project; then
    rm -f "${TEMP_CSV}"
    exit 1
fi

if [ -z "${POD_NAME}" ]; then
    POD_NAME=$(get_user_input "Enter pod name (e.g., prod, dev, test)" "prod")
fi

log_info "Generating CSV for pod: ${POD_NAME}"
log_info "Output: ${CSV_FILE}"
log_info "Sample pods: ${NUM_PODS}"

if [ -f "${CSV_FILE}" ] && [ "${FORCE_OVERWRITE}" = false ]; then
    log_warning "CSV file exists: ${CSV_FILE}"
    if ! get_user_input "Overwrite? (y/N)" "N" | grep -qi "^y"; then
        log_info "Aborted by user"
        rm -f "${TEMP_CSV}"
        exit 0
    fi
fi

: > "${TEMP_CSV}" || {
    log_error "Failed to create temporary CSV: ${TEMP_CSV}"
    rm -f "${TEMP_CSV}"
    exit 1
}

generate_csv_header >> "${TEMP_CSV}"
log_info "Wrote CSV header"

# Generate sample data for user-specified pod and additional pods
pod_list=("${POD_NAME}")
if [ "${NUM_PODS}" -gt 1 ]; then
    default_pods=("prod" "dev" "test" "stage" "qa")
    count=1
    for default_pod in "${default_pods[@]}"; do
        if [ "${default_pod}" != "${POD_NAME}" ] && [ "${count}" -lt "${NUM_PODS}" ]; then
            pod_list+=("${default_pod}")
            ((count++))
        fi
    done
    while [ "${count}" -lt "${NUM_PODS}" ]; do
        pod_list+=("pod${count}")
        ((count++))
    done
fi

for pod in "${pod_list[@]}"; do
    generate_sample_data "${pod}" >> "${TEMP_CSV}"
    echo "" >> "${TEMP_CSV}"
    log_info "Wrote sample data for pod: ${pod}"
done

echo "# EOF - Edit this file to add your actual hosts and credentials" >> "${TEMP_CSV}"

if ! mv "${TEMP_CSV}" "${CSV_FILE}"; then
    log_error "Failed to move CSV to ${CSV_FILE}. Check directory permissions with: ls -ld ${ROSTER_DIR}/data"
    rm -f "${TEMP_CSV}"
    exit 1
fi

chmod "${CSV_PERMS}" "${CSV_FILE}" 2>/dev/null || log_warning "Could not set CSV permissions to ${CSV_PERMS}"

generate_readme
log_info "Wrote README: ${README_FILE}"
chmod "${CSV_PERMS}" "${README_FILE}" 2>/dev/null || log_warning "Could not set README permissions to ${CSV_PERMS}"

log_info "Generated CSV contents:"
cat "${CSV_FILE}" | sed 's|^|  |'
if ! get_user_input "Is CSV content correct? (y/N)" "y" | grep -qi "^y"; then
    log_warning "User rejected CSV content. Edit ${CSV_FILE} manually."
    exit 1
fi

if validate_csv "${CSV_FILE}"; then
    log_info "CSV generation completed!"
    echo -e "${GREEN}✓ CSV created: ${CSV_FILE}${NC}"
    echo -e "${GREEN}✓ README created: ${README_FILE}${NC}"
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Edit ${CSV_FILE} (see ${README_FILE})"
    echo "  2. Run 06-check-vendors.sh to validate build"
    echo "  3. Run 07-remote-test.sh to test connectivity"
    echo "  4. Run 08-generate-configs.sh for roster file"
    echo "  5. Check logs: ${MAIN_LOG}, ${ERROR_LOG}"
    read -r -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
else
    log_error "CSV validation failed: ${CSV_FILE}"
    read -r -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
    exit 1
fi

log_info "02-create-csv.sh completed for pod: ${POD_NAME}"
exit 0
