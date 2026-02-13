#!/usr/bin/env bash
#
# Run KICS (Keeping Infrastructure as Code Secure) scanner on Terraform configurations
# Usage: ./scripts/run-kics.sh [directory] [--compact]
#
# Examples:
#   ./scripts/run-kics.sh              # Scan both infra and state-backend
#   ./scripts/run-kics.sh infra        # Scan only infra directory
#   ./scripts/run-kics.sh --compact    # Compact output (failures only)
#
# Configuration:
#   KICS results are saved to kics-results.json
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default settings
COMPACT=""
DIRECTORY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --compact|-c)
            COMPACT="--minimal-ui"
            shift
            ;;
        *)
            DIRECTORY="$1"
            shift
            ;;
    esac
done

printf '%b\n' "${GREEN}========================================${NC}"
printf '%b\n' "${GREEN}  KICS Security Scanner${NC}"
printf '%b\n' "${GREEN}========================================${NC}"
printf '\n'

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    printf '%b\n' "${RED}Error: Docker is required but not installed.${NC}"
    printf '%s\n' "Install Docker or use: docker pull checkmarx/kics"
    exit 1
fi

run_kics() {
    local dir="$1"
    local name="$2"

    printf '%b\n' "${YELLOW}Scanning: ${name}${NC}"
    printf '%s\n' "Directory: ${dir}"
    printf '\n'

    # Run KICS scan
    docker run --rm \
        -v "${dir}:/path" \
        -v "${PROJECT_ROOT}:/output" \
        checkmarx/kics:latest \
        scan \
        --path "/path" \
        --output-path "/output" \
        --output-name "kics-results-${name}" \
        --report-formats json,sarif \
        --type terraform \
        ${COMPACT} \
        || true

    printf '\n'
    printf '%b\n' "${GREEN}Results saved to: kics-results-${name}.json${NC}"
    printf '%b\n' "${GREEN}SARIF report: kics-results-${name}.sarif${NC}"
    printf '\n'
    printf '%b\n' "${GREEN}----------------------------------------${NC}"
    printf '\n'
}

if [[ -n "$DIRECTORY" ]]; then
    # Scan specific directory
    if [[ -d "${PROJECT_ROOT}/${DIRECTORY}" ]]; then
        run_kics "${PROJECT_ROOT}/${DIRECTORY}" "$DIRECTORY"
    else
        printf '%b\n' "${RED}Error: Directory '${DIRECTORY}' not found${NC}"
        exit 1
    fi
else
    # Scan all terraform directories
    if [[ -d "${PROJECT_ROOT}/infra" ]]; then
        run_kics "${PROJECT_ROOT}/infra" "infra"
    fi
    
    if [[ -d "${PROJECT_ROOT}/state-backend" ]]; then
        run_kics "${PROJECT_ROOT}/state-backend" "state-backend"
    fi
fi

printf '%b\n' "${GREEN}KICS scan complete!${NC}"
printf '\n'
printf '%s\n' "Options:"
printf '%s\n' "  --compact, -c  : Minimal UI output"
printf '\n'
