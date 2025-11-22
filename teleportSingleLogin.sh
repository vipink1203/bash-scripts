#!/bin/bash

# Author: @vipink1203
# Web: www.vipinkumar.me
# UseCase: Interactive script to login to a server via Gravitational Teleport SSH gateway
# LastEdited: November 22 2025

set -euo pipefail

# Configuration
readonly TELEPORT_PROXY="${TELEPORT_PROXY:-teleport.example.com}"
readonly TELEPORT_AUTH="${TELEPORT_AUTH:-}"
readonly SSH_USER="${SSH_USER:-root}"

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

# Usage function
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [SERVER_PATTERN]

Description:
    Interactive script to SSH into a server via Teleport.
    If multiple servers match the pattern, displays a selection menu.

Options:
    -p, --proxy PROXY         Teleport proxy address (default: ${TELEPORT_PROXY})
    -a, --auth METHOD         Teleport authentication method
    -u, --user USER           SSH user (default: ${SSH_USER})
    -l, --list               List all available servers and exit
    -h, --help               Show this help message

Arguments:
    SERVER_PATTERN           Optional server name or pattern to match

Environment Variables:
    TELEPORT_PROXY           Teleport proxy address
    TELEPORT_AUTH            Teleport authentication method
    SSH_USER                 SSH user for connections

Examples:
    # Interactive mode (prompts for server)
    $(basename "$0")

    # Direct mode with server pattern
    $(basename "$0") web-prod

    # List all servers
    $(basename "$0") --list

    # Use specific proxy and auth
    $(basename "$0") -p teleport.example.com -a okta web-prod

EOF
    exit 1
}

# Check dependencies
check_dependencies() {
    if ! command -v tsh &> /dev/null; then
        log_error "Teleport client 'tsh' not found. Please install it first."
        exit 1
    fi
}

# Login to Teleport if not already logged in
ensure_teleport_login() {
    local proxy="$1"
    local auth="$2"

    if ! tsh status &> /dev/null; then
        log_info "Not logged into Teleport. Logging in..."

        local cmd="tsh login --proxy=${proxy}"
        if [[ -n "${auth}" ]]; then
            cmd="${cmd} --auth=${auth}"
        fi

        if ! eval "${cmd}"; then
            log_error "Failed to login to Teleport"
            exit 1
        fi
    else
        log_debug "Already logged into Teleport"
    fi
}

# List all servers
list_servers() {
    log_info "Available servers:"
    if ! tsh ls; then
        log_error "Failed to list servers"
        exit 1
    fi
}

# Find servers matching pattern
find_servers() {
    local pattern="$1"
    local temp_file
    temp_file=$(mktemp)

    if ! tsh ls | grep -i "${pattern}" | awk '{print $2}' | cut -d: -f1 > "${temp_file}"; then
        rm -f "${temp_file}"
        return 1
    fi

    if [[ ! -s "${temp_file}" ]]; then
        rm -f "${temp_file}"
        return 1
    fi

    cat "${temp_file}"
    rm -f "${temp_file}"
    return 0
}

# Interactive server selection
select_server() {
    local -a servers=("$@")
    local count=${#servers[@]}

    if [[ ${count} -eq 0 ]]; then
        log_error "No servers found"
        exit 1
    fi

    if [[ ${count} -eq 1 ]]; then
        echo "${servers[0]}"
        return 0
    fi

    log_warning "Found ${count} matching servers:"
    echo ""

    local i=1
    for server in "${servers[@]}"; do
        echo "  ${i}) ${server}"
        ((i++))
    done

    echo ""
    while true; do
        read -rp "Select server (1-${count}): " selection

        if [[ "${selection}" =~ ^[0-9]+$ ]] && [[ ${selection} -ge 1 ]] && [[ ${selection} -le ${count} ]]; then
            echo "${servers[$((selection - 1))]}"
            return 0
        else
            log_error "Invalid selection. Please enter a number between 1 and ${count}"
        fi
    done
}

# Connect to server
connect_to_server() {
    local ip="$1"
    local user="$2"

    log_info "Connecting to ${user}@${ip}..."

    if ! tsh ssh "${user}@${ip}"; then
        log_error "Failed to connect to server"
        exit 1
    fi
}

# Main function
main() {
    local proxy="${TELEPORT_PROXY}"
    local auth="${TELEPORT_AUTH}"
    local user="${SSH_USER}"
    local server_pattern=""
    local list_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
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
            -l|--list)
                list_only=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                server_pattern="$1"
                shift
                ;;
        esac
    done

    # Check dependencies
    check_dependencies

    # Ensure logged into Teleport
    ensure_teleport_login "${proxy}" "${auth}"

    # List servers and exit if requested
    if [[ "${list_only}" == true ]]; then
        list_servers
        exit 0
    fi

    # Get server pattern if not provided
    if [[ -z "${server_pattern}" ]]; then
        echo -n "Enter server name or pattern: "
        read -r server_pattern

        if [[ -z "${server_pattern}" ]]; then
            log_error "Server pattern cannot be empty"
            exit 1
        fi
    fi

    # Find matching servers
    log_info "Searching for servers matching: ${server_pattern}"

    local matching_ips
    if ! matching_ips=$(find_servers "${server_pattern}"); then
        log_error "No servers found matching pattern: ${server_pattern}"
        exit 1
    fi

    # Convert to array
    local -a server_array
    mapfile -t server_array <<< "${matching_ips}"

    # Select server (interactive if multiple matches)
    local selected_ip
    selected_ip=$(select_server "${server_array[@]}")

    # Connect to selected server
    connect_to_server "${selected_ip}" "${user}"
}

# Run main function
main "$@" 

