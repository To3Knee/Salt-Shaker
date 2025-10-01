#!/bin/bash
#===============================================================
#Script Name: extract-salt-ssh-onedir.sh
#Date: 09/27/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.4
#Short: Extract salt-ssh binary from Salt 3006.15 onedir tarball
#About: Extracts the salt-ssh binary from salt-3006.15-onedir-linux-x86_64.tar.xz to ${PROJECT_ROOT}/vendor/el7/salt/bin/ for use with Salt Shaker. Verifies the binary version (3006.15) with the correct PYTHONPATH. Supports downloading the tarball if needed from GitHub releases. Designed for air-gapped EL7/8/9 systems using native bash/coreutils. Logs to ${PROJECT_ROOT}/logs/salt-shaker.log and ${PROJECT_ROOT}/logs/salt-shaker-errors.log. Uses a professional UI with colors (GREEN info, RED error, YELLOW warn, CYAN prompts, BLUE bars). All paths use PROJECT_ROOT for portability across arbitrary directories.
#===============================================================

#===============================================================
# Configuration Section
#===============================================================
PROJECT_ROOT=""
if [ -n "${SALT_SHAKER_ROOT}" ]; then
    PROJECT_ROOT="${SALT_SHAKER_ROOT}"
elif [ -f "$(dirname "$0")/../Salt-Shaker.sh" ]; then
    PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
else
    PROJECT_ROOT="${PWD}"
fi
[ ! -d "${PROJECT_ROOT}" ] && { echo "Error: Project root not found"; exit 1; }

ONEDIR_TARBALL="${PROJECT_ROOT}/offline/salt/tarballs/salt-3006.15-onedir-linux-x86_64.tar.xz"
SALT_SSH_BIN="${PROJECT_ROOT}/vendor/el7/salt/bin/salt-ssh"
LOG_DIR="${PROJECT_ROOT}/logs"
MAIN_LOG="${LOG_DIR}/salt-shaker.log"
ERROR_LOG="${LOG_DIR}/salt-shaker-errors.log"

# Color definitions (matching salt-shaker.sh palette)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    WHITE=""
    NC=""
fi

#===============================================================
# Functions
#===============================================================

# Function to log messages with color-coded console output
log_info() {
    local message="$1"
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${message}" >> "${MAIN_LOG}" 2>/dev/null || true
    echo -e "${GREEN}${message}${NC}"
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

# Function to draw ASCII bar
bar() {
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
}

# Function to check for required tools
need() {
    local tool
    for tool in "$@"; do
        command -v "${tool}" >/dev/null 2>&1 || {
            log_error "Missing required tool: ${tool}. This script requires native bash/coreutils (e.g., tar, wget, mkdir, cp, chmod)."
            exit 1
        }
    done
}

# Function to download onedir tarball
download_onedir() {
    if [ -f "${ONEDIR_TARBALL}" ]; then
        log_info "Onedir tarball already exists: ${ONEDIR_TARBALL}"
        return 0
    fi
    mkdir -p "${PROJECT_ROOT}/offline/salt/tarballs" 2>/dev/null || {
        log_error "Failed to create directory: ${PROJECT_ROOT}/offline/salt/tarballs"
        return 1
    }
    log_info "Downloading salt-3006.15-onedir-linux-x86_64.tar.xz from GitHub releases..."
    if ! wget -O "${ONEDIR_TARBALL}" "https://github.com/saltstack/salt/releases/download/v3006.15/salt-3006.15-onedir-linux-x86_64.tar.xz"; then
        log_error "Failed to download salt-3006.15-onedir-linux-x86_64.tar.xz from https://github.com/saltstack/salt/releases/download/v3006.15/salt-3006.15-onedir-linux-x86_64.tar.xz"
        return 1
    }
    log_info "Downloaded onedir tarball to ${ONEDIR_TARBALL}"
    return 0
}

# Function to extract salt-ssh from onedir tarball
extract_salt_ssh() {
    if [ ! -f "${ONEDIR_TARBALL}" ]; then
        log_error "Onedir tarball not found at ${ONEDIR_TARBALL}. Run with --download to fetch it."
        return 1
    }
    rm -f "${SALT_SSH_BIN}"
    mkdir -p "${PROJECT_ROOT}/vendor/el7/salt/bin" 2>/dev/null || {
        log_error "Failed to create directory: ${PROJECT_ROOT}/vendor/el7/salt/bin"
        return 1
    }
    if ! tar -xJf "${ONEDIR_TARBALL}" --strip-components=2 -C "${PROJECT_ROOT}/vendor/el7/salt/bin" salt/bin/salt-ssh; then
        log_error "Failed to extract salt-ssh from ${ONEDIR_TARBALL}"
        return 1
    }
    chmod +x "${SALT_SSH_BIN}" 2>/dev/null || {
        log_error "Failed to set executable permissions on ${SALT_SSH_BIN}"
        return 1
    }
    log_info "Extracted salt-ssh to ${SALT_SSH_BIN}"
    return 0
}

# Function to verify salt-ssh version
verify_salt_ssh() {
    if [ ! -x "${SALT_SSH_BIN}" ]; then
        log_error "salt-ssh binary not executable at ${SALT_SSH_BIN}"
        return 1
    }
    local version
    version=$(PYTHONPATH="${PROJECT_ROOT}/vendor/el7/salt/lib/python3.10/site-packages" "${SALT_SSH_BIN}" --version 2>&1 | grep -o 'Salt: [0-9.]*' || echo "unknown")
    if [ "${version}" != "Salt: 3006.15" ]; then
        log_error "salt-ssh binary at ${SALT_SSH_BIN} is not version 3006.15 (found: ${version})"
        return 1
    }
    log_info "salt-ssh binary verified at ${SALT_SSH_BIN} (version 3006.15)"
    return 0
}

#===============================================================
# Main Script Logic
#===============================================================

# Parse command-line arguments
DOWNLOAD=0
FORCE_DOWNLOAD=0
while [ $# -gt 0 ]; do
    case ${1} in
        -h|--help)
            cat << EOF
${WHITE}Usage:${NC} ${0##*/} [OPTIONS]

${CYAN}extract-salt-ssh-onedir.sh${NC} - Extract salt-ssh from Salt 3006.15 onedir tarball

${GREEN}Options:${NC}
    -h|--help        Show this help message
    --download       Download the onedir tarball if not present
    --force-download Force re-download of the onedir tarball

${GREEN}Examples:${NC}
    ${0##*/}                    # Extract from existing tarball
    ${0##*/} --download         # Download and extract tarball
    ${0##*/} --force-download   # Re-download and extract tarball

${YELLOW}Requirements:${NC}
    • Bash shell (native on EL7/EL8/EL9)
    • Tools: tar, wget, mkdir, cp, chmod
    • Onedir tarball: ${ONEDIR_TARBALL} (downloaded with --download)

${CYAN}Output:${NC}
    • salt-ssh binary at ${SALT_SSH_BIN}
    • Logs: ${MAIN_LOG}, ${ERROR_LOG}
EOF
            exit 0
            ;;
        --download)
            DOWNLOAD=1
            ;;
        --force-download)
            DOWNLOAD=1
            FORCE_DOWNLOAD=1
            rm -f "${ONEDIR_TARBALL}" 2>/dev/null
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# Check required tools
need tar wget mkdir cp chmod

# Log startup
log_info "Starting extract-salt-ssh-onedir.sh (Version 1.4) in project root: ${PROJECT_ROOT}"
bar

# Download onedir tarball if requested
if [ "${DOWNLOAD}" -eq 1 ]; then
    if [ "${FORCE_DOWNLOAD}" -eq 1 ]; then
        log_info "Force downloading onedir tarball..."
    fi
    download_onedir || {
        log_error "Failed to download onedir tarball. Please download manually to ${ONEDIR_TARBALL}"
        exit 1
    }
fi

# Extract salt-ssh
extract_salt_ssh || {
    log_error "Failed to extract salt-ssh. Ensure ${ONEDIR_TARBALL} exists or use --download."
    exit 1
}

# Verify salt-ssh
verify_salt_ssh || {
    log_error "salt-ssh verification failed. Check logs: ${MAIN_LOG}, ${ERROR_LOG}"
    exit 1
}

bar
log_info "Successfully extracted and verified salt-ssh (version 3006.15) at ${SALT_SSH_BIN}"
log_info "Next: Run ${PROJECT_ROOT}/modules/05-build-thin-el7.sh to verify, then proceed to 08-generate-configs.sh, 06-check-vendors.sh, or 07-remote-test.sh."
bar
exit 0
