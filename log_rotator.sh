#!/bin/bash

# Author: @vipink1203
# Web: www.vipinkumar.me
# Script to check the log directory. If the size is more than 3 GB, it will keep the last two written logs and delete the old ones
# LastEdited: November 22 2025

set -euo pipefail

# Configuration
readonly THRESHOLD_GB=3
readonly KEEP_FILES=2

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Usage function
usage() {
    cat <<EOF
Usage: $(basename "$0") <directory_path>

Description:
    Monitors a log directory and performs cleanup if size exceeds ${THRESHOLD_GB}GB.
    Keeps the ${KEEP_FILES} most recent log files and removes older ones.

Arguments:
    directory_path    Path to the log directory (without trailing slash)

Example:
    $(basename "$0") /var/log/application

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

# Main function
main() {
    # Check if argument is provided
    if [[ $# -eq 0 ]] || [[ -z "${1:-}" ]]; then
        log_error "No directory path provided"
        usage
    fi

    local dir="$1"

    # Validate directory exists
    if [[ ! -d "${dir}" ]]; then
        log_error "The path '${dir}' is not a valid directory"
        usage
    fi

    # Check read permissions
    if [[ ! -r "${dir}" ]]; then
        log_error "No read permission for directory '${dir}'"
        exit 1
    fi

    # Get directory size in GB
    local size_output
    size_output=$(du -sh --block-size=1G "${dir}" 2>/dev/null | awk '{print $1}')
    local size_gb="${size_output%G}"

    log_info "Directory: ${dir}"
    log_info "Current size: ${size_gb}GB"
    log_info "Threshold: ${THRESHOLD_GB}GB"

    # Compare size with threshold
    if [[ "${size_gb}" -gt "${THRESHOLD_GB}" ]]; then
        log_warning "Size exceeds ${THRESHOLD_GB}GB. Starting cleanup..."

        # Count files in directory
        local file_count
        file_count=$(find "${dir}" -maxdepth 1 -type f | wc -l)

        if [[ "${file_count}" -le "${KEEP_FILES}" ]]; then
            log_warning "Only ${file_count} file(s) found. Nothing to delete (keeping ${KEEP_FILES} files)"
            exit 0
        fi

        # Get files to delete (all except the last KEEP_FILES files sorted by modification time)
        local files_to_delete
        files_to_delete=$(find "${dir}" -maxdepth 1 -type f -printf '%T@ %p\n' | \
                         sort -rn | \
                         tail -n +$((KEEP_FILES + 1)) | \
                         cut -d' ' -f2-)

        if [[ -n "${files_to_delete}" ]]; then
            local delete_count
            delete_count=$(echo "${files_to_delete}" | wc -l)
            log_info "Deleting ${delete_count} old file(s)..."

            while IFS= read -r file; do
                if [[ -f "${file}" ]]; then
                    rm -f "${file}"
                    log_info "Deleted: ${file}"
                fi
            done <<< "${files_to_delete}"

            log_info "Cleanup completed successfully"
        else
            log_info "No files to delete"
        fi
    else
        log_info "Size is within acceptable limits. No cleanup needed."
    fi
}

# Run main function
main "$@"
