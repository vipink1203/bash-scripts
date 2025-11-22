#!/bin/bash

# Author: @vipink1203
# The GeoIP2 Country, City, ISP, Connection Type, and Enterprise databases are updated weekly, every Tuesday.
# Reference: https://support.maxmind.com/geoip-faq/geoip2-and-geoip-legacy-database-updates/how-often-are-the-geoip2-and-geoip-legacy-databases-updated/
# Cron schedule: 0 05 * * 2 (At 05:00 on Tuesday)
# LastEdited: November 22 2025

## Description:
# Downloads MaxMind GeoIP2 databases and uploads them to S3
# Directory format: GeoIP2-Country_20200512 where dbname=GeoIP2-Country and dirday=20200512
# S3 hierarchy: s3://databases-backup/maxmind/${dbname}/${dirday}

set -euo pipefail

# Configuration
readonly SSM_PARAMETER_NAME="${SSM_PARAMETER_NAME:-/dev/MAXMIND/MAX_MIND_LICENSE}"
readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly S3_BUCKET="${S3_BUCKET:-databases-backup}"
readonly SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:us-east-1:XXXXXXXXX:alert}"
readonly WORK_DIR="${WORK_DIR:-$(pwd)}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script failed with exit code ${exit_code}"
    fi
    log_debug "Cleaning up temporary files..."
    cd "${WORK_DIR}" || true
    rm -rf GeoIP2-* 2>/dev/null || true
}

trap cleanup EXIT

# Check required tools
check_dependencies() {
    local deps=("aws" "jq" "wget" "tar")
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            error_exit "Required command '${dep}' not found. Please install it first."
        fi
    done
}

# Get license key from AWS SSM
get_license_key() {
    log_info "Retrieving MaxMind license from AWS SSM..."

    local license
    license=$(aws ssm get-parameter \
        --name "${SSM_PARAMETER_NAME}" \
        --region "${AWS_REGION}" \
        --query 'Parameter.Value' \
        --output text 2>&1)

    if [[ $? -ne 0 ]] || [[ -z "${license}" ]]; then
        error_exit "Failed to retrieve license from SSM parameter: ${SSM_PARAMETER_NAME}"
    fi

    echo "${license}"
}

# Download and process a single database
process_database() {
    local edition_id="$1"
    local license="$2"
    local url="https://download.maxmind.com/app/geoip_download?edition_id=${edition_id}&license_key=${license}&suffix=tar.gz"

    log_info "Processing ${edition_id}..."

    if ! wget -q -c "${url}" -O - | tar -xz; then
        log_error "Failed to download or extract ${edition_id}"
        return 1
    fi

    # Find the extracted directory
    local dirname
    dirname=$(find . -maxdepth 1 -type d -name "GeoIP2-*" -o -name "GeoLite2-*" | head -1)

    if [[ -z "${dirname}" ]]; then
        log_error "No extracted directory found for ${edition_id}"
        return 1
    fi

    dirname="${dirname#./}"

    # Extract database name and date
    local dbname dirday
    dbname=$(echo "${dirname}" | cut -d_ -f1)
    dirday=$(echo "${dirname}" | cut -d_ -f2)

    log_debug "Database: ${dbname}, Date: ${dirday}"

    # Check if already exists in S3
    local s3_path="s3://${S3_BUCKET}/maxmind/${dbname}/${dirday}"
    local object_count
    object_count=$(aws s3 ls "${s3_path}/" 2>/dev/null | wc -l)

    if [[ "${object_count}" -ne 0 ]]; then
        log_warning "Database already exists in S3 for date ${dirday}"
        rm -rf "${dirname}"
        return 2
    fi

    # Rename and upload to S3
    log_info "Uploading ${dbname} (${dirday}) to S3..."
    mv "${dirname}" "${dirday}"

    if ! aws s3 cp "${dirday}" "${s3_path}" --recursive --region "${AWS_REGION}"; then
        log_error "Failed to upload ${dbname} to S3"
        rm -rf "${dirday}"
        return 1
    fi

    rm -rf "${dirday}"
    log_info "Successfully processed ${edition_id}"

    echo "${dirday}"
    return 0
}

# Send SNS notification
send_notification() {
    local update_date="$1"

    log_info "Sending SNS notification..."

    local db_list
    db_list=$(aws s3 ls "s3://${S3_BUCKET}/maxmind/" --region "${AWS_REGION}" | grep -v 'PRE' || echo "No databases listed")

    local message
    message="MaxMind Database Update Notification

Update Date: ${update_date}
S3 Bucket: ${S3_BUCKET}

Databases in S3:
${db_list}

This is an automated notification from the MaxMind DB updater script."

    if aws sns publish \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --subject "MaxMind DB Update Available - ${update_date}" \
        --message "${message}" \
        --region "${AWS_REGION}" &> /dev/null; then
        log_info "SNS notification sent successfully"
    else
        log_warning "Failed to send SNS notification"
    fi
}

# Main function
main() {
    log_info "Starting MaxMind DB updater"

    # Check dependencies
    check_dependencies

    # Change to working directory
    cd "${WORK_DIR}" || error_exit "Cannot change to working directory: ${WORK_DIR}"

    # Get license key
    local license
    license=$(get_license_key)

    # Database editions to download
    local -a editions=(
        "GeoIP2-City"
        "GeoIP2-Connection-Type"
        "GeoIP2-Country"
        "GeoIP2-ISP"
    )

    local -a update_dates=()
    local success_count=0
    local skip_count=0
    local fail_count=0

    # Process each database
    for edition in "${editions[@]}"; do
        log_info "----------------------------------------"
        local result
        if result=$(process_database "${edition}" "${license}"); then
            if [[ -n "${result}" ]]; then
                update_dates+=("${result}")
                ((success_count++))
            fi
        else
            local exit_code=$?
            if [[ ${exit_code} -eq 2 ]]; then
                ((skip_count++))
            else
                ((fail_count++))
            fi
        fi
        sleep 2
    done

    log_info "----------------------------------------"
    log_info "Summary: ${success_count} uploaded, ${skip_count} skipped, ${fail_count} failed"

    # Send notification if there were updates
    if [[ ${#update_dates[@]} -gt 0 ]]; then
        send_notification "${update_dates[0]}"
    else
        log_info "No new databases to report"
    fi

    log_info "MaxMind DB updater completed successfully"
}

# Run main function
main "$@"
