#!/bin/bash

# Author: @vipink1203
# Web: www.vipinkumar.me
# UseCase: Script to login to all servers via Gravitational Teleport and check Node.js and PHP versions
# LastEdited: November 22 2025

set -euo pipefail

# Configuration
readonly OUTPUT_FILE="${OUTPUT_FILE:-output.csv}"
readonly TEMP_LIST="$(mktemp)"
readonly TELEPORT_PROXY="${TELEPORT_PROXY:-teleport.example.com}"
readonly TELEPORT_AUTH="${TELEPORT_AUTH:-}"
readonly SSH_USER="${SSH_USER:-root}"
readonly EXCLUDE_PATTERN="${EXCLUDE_PATTERN:-Labels|zone|packer|^dev|^qa|aspera}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*"
}

# Cleanup function
cleanup() {
    rm -f "${TEMP_LIST}" 2>/dev/null || true
}

trap cleanup EXIT

# Usage function
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Connects to servers via Teleport and retrieves Node.js and PHP versions.
    Outputs results to a CSV file.

Options:
    -o, --output FILE         Output CSV file (default: ${OUTPUT_FILE})
    -p, --proxy PROXY         Teleport proxy address (default: ${TELEPORT_PROXY})
    -a, --auth METHOD         Teleport authentication method
    -u, --user USER           SSH user (default: ${SSH_USER})
    -e, --exclude PATTERN     Exclude pattern for servers (default: ${EXCLUDE_PATTERN})
    -h, --help               Show this help message

Environment Variables:
    TELEPORT_PROXY           Teleport proxy address
    TELEPORT_AUTH            Teleport authentication method
    SSH_USER                 SSH user for connections
    OUTPUT_FILE              Output CSV file path
    EXCLUDE_PATTERN          Pattern to exclude servers

Example:
    $(basename "$0") -p teleport.example.com -a okta -o versions.csv

EOF
    exit 1
}

# Check dependencies
check_dependencies() {
    local deps=("tsh" "awk" "cut" "sort")
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            log_error "Required command '${dep}' not found. Please install Teleport client."
            exit 1
        fi
    done
}

# Login to Teleport
teleport_login() {
    local proxy="$1"
    local auth="$2"

    log_info "Logging into Teleport proxy: ${proxy}"

    local cmd="tsh login --proxy=${proxy}"
    if [[ -n "${auth}" ]]; then
        cmd="${cmd} --auth=${auth}"
    fi

    if ! eval "${cmd}"; then
        log_error "Failed to login to Teleport"
        exit 1
    fi

    log_info "Successfully logged into Teleport"
}

# Get server list
get_server_list() {
    local exclude_pattern="$1"
    local output_file="$2"

    log_info "Retrieving server list..."

    if ! tsh ls | awk '{print $4}' | cut -d= -f2 | sort -u | \
         grep -Ev "${exclude_pattern}" | grep -v '^$' > "${output_file}"; then
        log_error "Failed to retrieve server list"
        return 1
    fi

    local count
    count=$(wc -l < "${output_file}")
    log_info "Found ${count} servers to process"
}

# Check version on a server
check_versions() {
    local server="$1"
    local user="$2"

    log_debug "Processing server: ${server}"

    # Get server IP
    local ip
    if ! ip=$(tsh ls | grep -m1 "${server}" | awk '{print $2}' | cut -d: -f1); then
        log_warning "Could not find IP for server: ${server}"
        return 1
    fi

    if [[ -z "${ip}" ]]; then
        log_warning "Empty IP for server: ${server}"
        return 1
    fi

    # Check Node.js version
    local node_version="N/A"
    local node_output
    if node_output=$(tsh ssh "${user}@${ip}" "node -v" 2>&1); then
        if [[ "${node_output}" != *"error"* ]] && [[ "${node_output}" != *"command not found"* ]]; then
            node_version="${node_output}"
        fi
    fi

    # Check PHP version
    local php_version="N/A"
    local php_output
    if php_output=$(tsh ssh "${user}@${ip}" "php -v 2>/dev/null | grep -oP 'PHP \K[0-9.]+' | head -1" 2>&1); then
        if [[ "${php_output}" != *"error"* ]] && [[ "${php_output}" != *"command not found"* ]] && [[ -n "${php_output}" ]]; then
            php_version="${php_output}"
        fi
    fi

    echo "${server},${node_version},${php_version}"
}

# Main function
main() {
    local proxy="${TELEPORT_PROXY}"
    local auth="${TELEPORT_AUTH}"
    local user="${SSH_USER}"
    local output="${OUTPUT_FILE}"
    local exclude="${EXCLUDE_PATTERN}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            -p|--proxy)
                proxy="$2"
                shift 2
                ;;
            -a|--auth)
                auth="$2"
                shift 2
                ;;
            -u|--user)
                user="$2"
                shift 2
                ;;
            -e|--exclude)
                exclude="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    log_info "Starting Teleport version checker"
    log_info "Output file: ${output}"

    # Check dependencies
    check_dependencies

    # Login to Teleport
    if [[ "${proxy}" == "teleport.example.com" ]]; then
        log_warning "Using default proxy address. Please configure TELEPORT_PROXY or use -p option."
    fi

    teleport_login "${proxy}" "${auth}"

    # Get server list
    get_server_list "${exclude}" "${TEMP_LIST}"

    # Initialize output file
    echo "Server,Node-Version,PHP-Version" > "${output}"

    # Process each server
    local total
    total=$(wc -l < "${TEMP_LIST}")
    local current=0

    while IFS= read -r server; do
        ((current++))
        log_info "Processing ${current}/${total}: ${server}"

        if result=$(check_versions "${server}" "${user}"); then
            echo "${result}" >> "${output}"
            log_debug "Result: ${result}"
        else
            log_warning "Failed to check versions for ${server}"
            echo "${server},ERROR,ERROR" >> "${output}"
        fi
    done < "${TEMP_LIST}"

    log_info "----------------------------------------"
    log_info "Completed! Results saved to: $(realpath "${output}")"
    log_info "Total servers processed: ${total}"
}

# Run main function
main "$@"