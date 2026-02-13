#!/usr/bin/env bash
#
# Run Checkov security scanner on Terraform configurations
# Usage: ./scripts/run-checkov.sh [directory] [--compact]
#
# Examples:
#   ./scripts/run-checkov.sh              # Scan both infra and state-backend
#   ./scripts/run-checkov.sh infra        # Scan only infra directory
#   ./scripts/run-checkov.sh --compact    # Compact output (failures only)
#   ./scripts/run-checkov.sh --all        # Show all checks (ignore .checkov.yaml)
#
# Configuration:
#   Skipped checks are documented in infra/.checkov.yaml
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
COMPACT=()
DIRECTORY=""
USE_CONFIG="true"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --compact|-c)
            COMPACT=(--compact --quiet)
            shift
            ;;
        --all|-a)
            USE_CONFIG="false"
            shift
            ;;
        *)
            DIRECTORY="$1"
            shift
            ;;
    esac
done

printf '%b\n' "${GREEN}========================================${NC}"
printf '%b\n' "${GREEN}  Checkov Security Scanner${NC}"
printf '%b\n' "${GREEN}========================================${NC}"
printf '\n'

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    printf '%b\n' "${RED}Error: Docker is required but not installed.${NC}"
    printf '%s\n' "Install Docker or use: pip install checkov"
    exit 1
fi

run_checkov() {
    local dir="$1"
    local name="$2"

    printf '%b\n' "${YELLOW}Scanning: ${name}${NC}"
    printf '%s\n' "Directory: ${dir}"
    printf '\n'

    # Build docker command
    local config_args=()
    if [[ "$USE_CONFIG" == "true" && -f "${dir}/.checkov.yaml" ]]; then
        printf '%s\n' "Using config: ${dir}/.checkov.yaml"
        config_args=(--config-file /tf/.checkov.yaml)
    fi

    docker run --rm \
        -v "${dir}:/tf:ro" \
        bridgecrew/checkov \
        -d /tf \
        --framework terraform \
        "${config_args[@]}" \
        "${COMPACT[@]}" \
        || true

    printf '\n'
    printf '%b\n' "${GREEN}----------------------------------------${NC}"
    printf '\n'
}

if [[ -n "$DIRECTORY" ]]; then
    # Scan specific directory
    if [[ -d "${PROJECT_ROOT}/${DIRECTORY}" ]]; then
        run_checkov "${PROJECT_ROOT}/${DIRECTORY}" "$DIRECTORY"
    else
        printf '%b\n' "${RED}Error: Directory '${DIRECTORY}' not found${NC}"
        exit 1
    fi
else
    # Scan all terraform directories
    if [[ -d "${PROJECT_ROOT}/infra" ]]; then
        run_checkov "${PROJECT_ROOT}/infra" "infra"
    fi
    
    if [[ -d "${PROJECT_ROOT}/state-backend" ]]; then
        run_checkov "${PROJECT_ROOT}/state-backend" "state-backend"
    fi
fi

printf '%b\n' "${GREEN}Checkov scan complete!${NC}"
printf '\n'
printf '%s\n' "Options:"
printf '%s\n' "  --compact, -c  : Show only failed checks"
printf '%s\n' "  --all, -a      : Ignore .checkov.yaml skip list"
printf '\n'
printf '%s\n' "Skipped checks are documented in infra/.checkov.yaml"
