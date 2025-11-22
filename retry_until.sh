#!/bin/bash

# Author: @vipink1203
# Web: www.vipinkumar.me
# UseCase: Generic script to retry a command until it succeeds with configurable retry delay and max attempts
# LastEdited: November 22 2025

set -euo pipefail

# Configuration
readonly DEFAULT_RETRY_DELAY=10
readonly DEFAULT_MAX_ATTEMPTS=0  # 0 means infinite retries

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Usage function
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] -- COMMAND [ARGS...]

Description:
    Retries a command until it succeeds with configurable delay and max attempts.

Options:
    -d, --delay SECONDS       Delay between retries (default: ${DEFAULT_RETRY_DELAY})
    -m, --max-attempts NUM    Maximum retry attempts (default: ${DEFAULT_MAX_ATTEMPTS}, 0 = infinite)
    -h, --help               Show this help message

Arguments:
    COMMAND                   The command to execute
    ARGS                      Arguments for the command

Examples:
    # Retry curl with default settings (infinite retries, 10s delay)
    $(basename "$0") -- curl -f https://example.com/api

    # Retry with 5 second delay
    $(basename "$0") -d 5 -- ping -c 1 google.com

    # Retry maximum 3 times with 15 second delay
    $(basename "$0") -d 15 -m 3 -- ./my-script.sh

    # Complex command with arguments
    $(basename "$0") -d 30 -- php artisan queue:work --tries=3

EOF
    exit 1
}

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

# Main retry function
retry_command() {
    local retry_delay="$1"
    local max_attempts="$2"
    shift 2
    local command=("$@")

    local attempt=1

    while true; do
        if [[ "${max_attempts}" -gt 0 ]]; then
            log_info "Attempt ${attempt}/${max_attempts}: ${command[*]}"
        else
            log_info "Attempt ${attempt}: ${command[*]}"
        fi

        if "${command[@]}"; then
            log_info "Command succeeded!"
            return 0
        fi

        local exit_code=$?
        log_warning "Command failed with exit code ${exit_code}"

        if [[ "${max_attempts}" -gt 0 ]] && [[ "${attempt}" -ge "${max_attempts}" ]]; then
            log_error "Maximum attempts (${max_attempts}) reached. Giving up."
            return "${exit_code}"
        fi

        log_info "Retrying in ${retry_delay} seconds..."
        sleep "${retry_delay}"
        ((attempt++))
    done
}

# Main function
main() {
    local retry_delay="${DEFAULT_RETRY_DELAY}"
    local max_attempts="${DEFAULT_MAX_ATTEMPTS}"
    local command_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -d|--delay)
                if [[ -z "${2:-}" ]] || [[ ! "${2}" =~ ^[0-9]+$ ]]; then
                    log_error "Invalid delay value: ${2:-}"
                    usage
                fi
                retry_delay="$2"
                shift 2
                ;;
            -m|--max-attempts)
                if [[ -z "${2:-}" ]] || [[ ! "${2}" =~ ^[0-9]+$ ]]; then
                    log_error "Invalid max attempts value: ${2:-}"
                    usage
                fi
                max_attempts="$2"
                shift 2
                ;;
            --)
                shift
                command_args=("$@")
                break
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate command is provided
    if [[ ${#command_args[@]} -eq 0 ]]; then
        log_error "No command provided"
        usage
    fi

    # Execute retry logic
    retry_command "${retry_delay}" "${max_attempts}" "${command_args[@]}"
}

# Run main function
main "$@"
