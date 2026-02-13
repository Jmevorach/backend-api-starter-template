#!/usr/bin/env bash
#
# Unified Deployment Script
# =========================
# Single command to deploy or update the entire infrastructure.
#
# Usage:
#   ./scripts/deploy.sh                    # Full deployment
#   ./scripts/deploy.sh --skip-build       # Skip container build (use existing image)
#   ./scripts/deploy.sh --plan-only        # Terraform plan without apply
#   ./scripts/deploy.sh --init-state       # Also initialize state backend
#
# Required Environment Variables:
#   AWS_REGION                    - AWS region (default: us-east-1)
#   TF_VAR_github_owner           - GitHub owner for OIDC
#   TF_VAR_github_repo            - GitHub repo for OIDC
#   TF_VAR_alb_acm_certificate_arn - ACM certificate ARN for HTTPS
#
# Optional Environment Variables:
#   ENVIRONMENT                   - Environment name (default: prod)
#   IMAGE_TAG                     - Container image tag (default: git short SHA)
#   ECR_REPOSITORY                - ECR repo name (default: backend-service)
#   PLATFORM                      - Build platform (default: linux/arm64)
#   CONTAINER_RUNTIME             - Container runtime: docker, finch, podman (auto-detected)
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="${ROOT_DIR}/app"
INFRA_DIR="${ROOT_DIR}/infra"
STATE_BACKEND_DIR="${ROOT_DIR}/state-backend"

# Defaults
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
ECR_REPOSITORY="${ECR_REPOSITORY:-backend-service}"
PLATFORM="${PLATFORM:-linux/arm64}"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"

# Flags
SKIP_BUILD=false
PLAN_ONLY=false
INIT_STATE=false
AUTO_APPROVE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$1"; }
log_success() { printf '%b[SUCCESS]%b %s\n' "$GREEN" "$NC" "$1"; }
log_warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$1"; }
log_error() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$1" >&2; }

print_header() {
    printf '\n%b' "$CYAN"
    printf '═══════════════════════════════════════════════════════════════════\n'
    printf '  %s\n' "$1"
    printf '═══════════════════════════════════════════════════════════════════%b\n' "$NC"
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Missing required command: $1"
        exit 1
    fi
}

require_env() {
    if [ -z "${!1:-}" ]; then
        log_error "Missing required environment variable: $1"
        log_info "Set it with: export $1=<value>"
        exit 1
    fi
}

# Detect available container runtime (docker, finch, or podman)
detect_container_runtime() {
    if [ -n "$CONTAINER_RUNTIME" ]; then
        # User specified a runtime, verify it exists
        if ! command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1; then
            log_error "Specified container runtime not found: $CONTAINER_RUNTIME"
            exit 1
        fi
        echo "$CONTAINER_RUNTIME"
        return
    fi

    # Auto-detect in order of preference
    if command -v docker >/dev/null 2>&1; then
        echo "docker"
    elif command -v finch >/dev/null 2>&1; then
        echo "finch"
    elif command -v podman >/dev/null 2>&1; then
        echo "podman"
    else
        log_error "No container runtime found. Install docker, finch, or podman."
        exit 1
    fi
}

# Build container image using detected runtime
container_build() {
    local runtime="$1"
    local platform="$2"
    local tag="$3"
    local context="$4"

    case "$runtime" in
        docker)
            docker buildx build \
                --platform "$platform" \
                -t "$tag" \
                --push \
                "$context"
            ;;
        finch)
            # Finch uses similar syntax to docker
            finch build \
                --platform "$platform" \
                -t "$tag" \
                --push \
                "$context"
            ;;
        podman)
            # Podman: build then push separately
            podman build \
                --platform "$platform" \
                -t "$tag" \
                "$context"
            podman push "$tag"
            ;;
        *)
            log_error "Unknown container runtime: $runtime"
            exit 1
            ;;
    esac
}

# Login to ECR using detected runtime
container_ecr_login() {
    local runtime="$1"
    local region="$2"
    local registry="$3"

    case "$runtime" in
        docker)
            aws ecr get-login-password --region "$region" | \
                docker login --username AWS --password-stdin "$registry"
            ;;
        finch)
            aws ecr get-login-password --region "$region" | \
                finch login --username AWS --password-stdin "$registry"
            ;;
        podman)
            aws ecr get-login-password --region "$region" | \
                podman login --username AWS --password-stdin "$registry"
            ;;
        *)
            log_error "Unknown container runtime: $runtime"
            exit 1
            ;;
    esac
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --plan-only)
            PLAN_ONLY=true
            shift
            ;;
        --init-state)
            INIT_STATE=true
            shift
            ;;
        --auto-approve|-y)
            AUTO_APPROVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-build     Skip container build, use existing image"
            echo "  --plan-only      Run terraform plan without apply"
            echo "  --init-state     Initialize state backend first"
            echo "  --auto-approve   Skip confirmation prompts"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Container Runtime:"
            echo "  Supports docker, finch, or podman (auto-detected)"
            echo "  Override with: CONTAINER_RUNTIME=finch $0"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Pre-flight Checks
# =============================================================================

print_header "Pre-flight Checks"

log_info "Checking required commands..."
require_cmd aws
require_cmd terraform
require_cmd git
require_cmd jq

# Detect container runtime
RUNTIME=$(detect_container_runtime)
log_success "Container runtime: $RUNTIME"

log_success "All required commands available"

log_info "Checking required environment variables..."
require_env TF_VAR_github_owner
require_env TF_VAR_github_repo
# Certificate: either domain_name+route53_zone_id OR alb_acm_certificate_arn (checked by Terraform)
log_success "All required environment variables set"

log_info "Verifying AWS credentials..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION" 2>/dev/null) || {
    log_error "Failed to verify AWS credentials. Run 'aws configure' or set AWS_* environment variables."
    exit 1
}
AWS_IDENTITY=$(aws sts get-caller-identity --query Arn --output text --region "$AWS_REGION")
log_success "Authenticated as: $AWS_IDENTITY"

# Compute derived values
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

# =============================================================================
# Display Deployment Plan
# =============================================================================

print_header "Deployment Plan"

printf '%b%-25s%b %s\n' "$CYAN" "AWS Account:" "$NC" "$AWS_ACCOUNT_ID"
printf '%b%-25s%b %s\n' "$CYAN" "AWS Region:" "$NC" "$AWS_REGION"
printf '%b%-25s%b %s\n' "$CYAN" "Environment:" "$NC" "$ENVIRONMENT"
printf '%b%-25s%b %s\n' "$CYAN" "Container Runtime:" "$NC" "$RUNTIME"
printf '%b%-25s%b %s\n' "$CYAN" "Image URI:" "$NC" "$IMAGE_URI"
printf '%b%-25s%b %s\n' "$CYAN" "Platform:" "$NC" "$PLATFORM"
# shellcheck disable=SC2154 # TF_VAR_* are set by user as env vars
printf '%b%-25s%b %s\n' "$CYAN" "GitHub Owner:" "$NC" "$TF_VAR_github_owner"
# shellcheck disable=SC2154
printf '%b%-25s%b %s\n' "$CYAN" "GitHub Repo:" "$NC" "$TF_VAR_github_repo"
printf '%b%-25s%b %s\n' "$CYAN" "Skip Build:" "$NC" "$SKIP_BUILD"
printf '%b%-25s%b %s\n' "$CYAN" "Plan Only:" "$NC" "$PLAN_ONLY"
echo ""

if [ "$AUTO_APPROVE" != "true" ]; then
    read -rp "Proceed with deployment? (y/N) " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled by user"
        exit 0
    fi
fi

# =============================================================================
# Step 1: Initialize State Backend (Optional)
# =============================================================================

if [ "$INIT_STATE" = "true" ]; then
    print_header "Step 1: Initialize State Backend"

    if [ ! -d "$STATE_BACKEND_DIR" ]; then
        log_error "State backend directory not found: $STATE_BACKEND_DIR"
        exit 1
    fi

    (
        cd "$STATE_BACKEND_DIR"
        log_info "Initializing Terraform for state backend..."
        terraform init -input=false

        log_info "Applying state backend configuration..."
        terraform apply -auto-approve
    )
    log_success "State backend initialized"
else
    log_info "Skipping state backend initialization (use --init-state to enable)"
fi

# =============================================================================
# Step 2: Build and Push Docker Image
# =============================================================================

if [ "$SKIP_BUILD" = "true" ]; then
    print_header "Step 2: Container Build (Skipped)"
    log_warn "Skipping container build as requested"

    # Verify the image exists in ECR
    log_info "Verifying image exists in ECR..."
    if ! aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageTag="$IMAGE_TAG" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_error "Image not found in ECR: $IMAGE_URI"
        log_info "Remove --skip-build flag to build and push the image"
        exit 1
    fi
    log_success "Image verified: $IMAGE_URI"
else
    print_header "Step 2: Build and Push Container Image"

    # Ensure ECR repository exists
    # Note: We create with basic settings here; Terraform will configure full settings later
    log_info "Ensuring ECR repository exists..."
    if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Creating ECR repository: $ECR_REPOSITORY"
        aws ecr create-repository \
            --repository-name "$ECR_REPOSITORY" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true >/dev/null
    fi
    log_success "ECR repository ready"

    # Login to ECR
    log_info "Logging in to ECR using $RUNTIME..."
    container_ecr_login "$RUNTIME" "$AWS_REGION" "$ECR_REGISTRY"
    log_success "ECR login successful"

    # Build and push
    log_info "Building container image with $RUNTIME..."
    log_info "  Platform: $PLATFORM"
    log_info "  Tag: $IMAGE_URI"

    container_build "$RUNTIME" "$PLATFORM" "$IMAGE_URI" "$APP_DIR"

    log_success "Container image pushed: $IMAGE_URI"
fi

# =============================================================================
# Step 3: Terraform Deployment
# =============================================================================

print_header "Step 3: Terraform Deployment"

# Export Terraform variables
export TF_VAR_container_image="$IMAGE_URI"
export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_environment="$ENVIRONMENT"

(
    cd "$INFRA_DIR"

    log_info "Initializing Terraform..."
    # Use -reconfigure to handle backend configuration changes without interactive prompts
    terraform init -input=false -upgrade -reconfigure

    log_info "Validating Terraform configuration..."
    terraform validate

    log_info "Running Terraform plan..."
    terraform plan -out=tfplan

    if [ "$PLAN_ONLY" = "true" ]; then
        log_warn "Plan only mode - skipping apply"
        log_info "Review the plan above. Run without --plan-only to apply."
        exit 0
    fi

    log_info "Applying Terraform changes..."
    terraform apply tfplan

    # Clean up plan file
    rm -f tfplan
)

log_success "Terraform apply complete"

# =============================================================================
# Step 4: Wait for Service Stability
# =============================================================================

print_header "Step 4: Waiting for Service Stability"

ECS_CLUSTER=$(cd "$INFRA_DIR" && terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
ECS_SERVICE=$(cd "$INFRA_DIR" && terraform output -raw ecs_service_name 2>/dev/null || echo "")

if [ -n "$ECS_CLUSTER" ] && [ -n "$ECS_SERVICE" ]; then
    log_info "Waiting for ECS service to stabilize..."
    log_info "  Cluster: $ECS_CLUSTER"
    log_info "  Service: $ECS_SERVICE"

    if aws ecs wait services-stable \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVICE" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "ECS service is stable"
    else
        log_warn "Timed out waiting for service stability"
        log_info "Run './scripts/deployment-health-report.sh' to check status"
    fi
else
    log_warn "Could not determine ECS cluster/service names"
fi

# =============================================================================
# Deployment Summary
# =============================================================================

print_header "Deployment Complete"

# Fetch outputs
ALB_DNS=$(cd "$INFRA_DIR" && terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")
GA_DNS=$(cd "$INFRA_DIR" && terraform output -raw global_accelerator_dns_name 2>/dev/null || echo "N/A")
ECR_URL=$(cd "$INFRA_DIR" && terraform output -raw ecr_repository_url 2>/dev/null || echo "N/A")

printf '\n'
printf '%b%-30s%b %s\n' "$GREEN" "Image Deployed:" "$NC" "$IMAGE_URI"
printf '%b%-30s%b %s\n' "$GREEN" "ALB Endpoint:" "$NC" "https://$ALB_DNS"
printf '%b%-30s%b %s\n' "$GREEN" "Global Accelerator:" "$NC" "https://$GA_DNS"
printf '%b%-30s%b %s\n' "$GREEN" "ECR Repository:" "$NC" "$ECR_URL"
printf '\n'

log_info "Test the deployment:"
echo "  curl -k https://$ALB_DNS/healthz"
echo ""
log_info "For detailed health report:"
echo "  ./scripts/deployment-health-report.sh"
echo ""

log_success "Deployment completed successfully!"
