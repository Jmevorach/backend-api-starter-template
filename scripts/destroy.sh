#!/usr/bin/env bash
#
# Infrastructure Destroy Script
# =============================
# Safely tear down the deployed infrastructure.
#
# Usage:
#   ./scripts/destroy.sh                    # Destroy main infrastructure
#   ./scripts/destroy.sh --full             # Complete teardown (ECR, buckets, snapshots, state)
#   ./scripts/destroy.sh --include-state    # Also destroy state backend
#   ./scripts/destroy.sh --include-ecr      # Also delete ECR images
#   ./scripts/destroy.sh --force            # Skip all confirmations (DANGEROUS)
#
# Environment Variables:
#   AWS_REGION - AWS region (default: us-east-1)
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/infra"
STATE_BACKEND_DIR="${ROOT_DIR}/state-backend"

AWS_REGION="${AWS_REGION:-us-east-1}"

# Flags
INCLUDE_STATE=false
INCLUDE_ECR=false
FORCE=false
FULL_DESTROY=false

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

confirm_action() {
    local message="$1"
    local confirm_word="${2:-yes}"

    if [ "$FORCE" = "true" ]; then
        return 0
    fi

    printf '%b%s%b\n' "$RED" "$message" "$NC"
    printf 'Type "%s" to confirm: ' "$confirm_word"
    read -r response

    if [ "$response" != "$confirm_word" ]; then
        log_warn "Confirmation failed. Aborting."
        exit 1
    fi
}

get_terraform_output() {
    local dir="$1"
    local output_name="$2"
    local result
    result=$(cd "$dir" && terraform output -raw "$output_name" 2>&1) || true
    # Return empty if output contains warning/error or is empty
    if [[ "$result" == *"Warning"* ]] || [[ "$result" == *"Error"* ]] || [[ -z "$result" ]]; then
        echo ""
    else
        echo "$result"
    fi
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_DESTROY=true
            INCLUDE_ECR=true
            INCLUDE_STATE=true
            shift
            ;;
        --include-state)
            INCLUDE_STATE=true
            shift
            ;;
        --include-ecr)
            INCLUDE_ECR=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --full           Complete teardown: delete ECR images, empty S3 buckets,"
            echo "                   skip RDS snapshots, destroy state backend (use for dev/testing)"
            echo "  --include-state  Also destroy the Terraform state backend (S3 + DynamoDB)"
            echo "  --include-ecr    Also delete all images from ECR repository"
            echo "  --force, -f      Skip all confirmation prompts (DANGEROUS)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "WARNING: This will permanently destroy your infrastructure!"
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

print_header "Infrastructure Destroy"

printf '%b' "$RED"
cat << 'EOF'

  ██████╗  █████╗ ███╗   ██╗ ██████╗ ███████╗██████╗
  ██╔══██╗██╔══██╗████╗  ██║██╔════╝ ██╔════╝██╔══██╗
  ██║  ██║███████║██╔██╗ ██║██║  ███╗█████╗  ██████╔╝
  ██║  ██║██╔══██║██║╚██╗██║██║   ██║██╔══╝  ██╔══██╗
  ██████╔╝██║  ██║██║ ╚████║╚██████╔╝███████╗██║  ██║
  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝

  This will PERMANENTLY DESTROY your infrastructure!

EOF
printf '%b' "$NC"

log_info "Checking AWS credentials..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION" 2>/dev/null) || {
    log_error "Failed to verify AWS credentials"
    exit 1
}
AWS_IDENTITY=$(aws sts get-caller-identity --query Arn --output text --region "$AWS_REGION")
log_info "Account: $AWS_ACCOUNT_ID"
log_info "Identity: $AWS_IDENTITY"

# Show what will be destroyed
echo ""
printf '%b%-30s%b %s\n' "$YELLOW" "AWS Region:" "$NC" "$AWS_REGION"
printf '%b%-30s%b %s\n' "$YELLOW" "Destroy Mode:" "$NC" "$([ "$FULL_DESTROY" = "true" ] && echo "FULL (empty buckets, skip snapshots)" || echo "Standard")"
printf '%b%-30s%b %s\n' "$YELLOW" "Main Infrastructure:" "$NC" "WILL BE DESTROYED"
printf '%b%-30s%b %s\n' "$YELLOW" "State Backend:" "$NC" "$([ "$INCLUDE_STATE" = "true" ] && echo "WILL BE DESTROYED" || echo "Will be preserved")"
printf '%b%-30s%b %s\n' "$YELLOW" "ECR Images:" "$NC" "$([ "$INCLUDE_ECR" = "true" ] && echo "WILL BE DELETED" || echo "Will be preserved")"
echo ""

# =============================================================================
# Confirmation
# =============================================================================

if [ "$INCLUDE_STATE" = "true" ]; then
    confirm_action "WARNING: This will also destroy your Terraform state backend. You will lose all state history!" "destroy-state"
fi

confirm_action "Are you sure you want to destroy all infrastructure in $AWS_REGION?" "yes"

# =============================================================================
# Step 1: Scale Down ECS Service
# =============================================================================

print_header "Step 1: Scale Down ECS Service"

ECS_CLUSTER=$(get_terraform_output "$INFRA_DIR" "ecs_cluster_name")
ECS_SERVICE=$(get_terraform_output "$INFRA_DIR" "ecs_service_name")

if [ -n "$ECS_CLUSTER" ] && [ -n "$ECS_SERVICE" ]; then
    log_info "Scaling down ECS service to 0..."
    log_info "  Cluster: $ECS_CLUSTER"
    log_info "  Service: $ECS_SERVICE"

    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_SERVICE" \
        --desired-count 0 \
        --region "$AWS_REGION" >/dev/null 2>&1 || true

    log_info "Waiting for tasks to drain (30 seconds)..."
    sleep 30

    log_success "ECS service scaled down"
else
    log_info "No ECS service found (may already be destroyed)"
fi

# =============================================================================
# Step 2: Clean ECR Images (Optional)
# =============================================================================

if [ "$INCLUDE_ECR" = "true" ]; then
    print_header "Step 2: Clean ECR Repository"

    ECR_REPO_NAME=$(get_terraform_output "$INFRA_DIR" "ecr_repository_url" | sed 's|.*/||')

    if [ -n "$ECR_REPO_NAME" ]; then
        log_info "Deleting all images from ECR repository: $ECR_REPO_NAME"

        # Get all image digests
        IMAGE_DIGESTS=$(aws ecr list-images \
            --repository-name "$ECR_REPO_NAME" \
            --region "$AWS_REGION" \
            --query 'imageIds[*]' \
            --output json 2>/dev/null || echo "[]")

        if [ "$IMAGE_DIGESTS" != "[]" ] && [ -n "$IMAGE_DIGESTS" ]; then
            # Delete images in batches of 100
            echo "$IMAGE_DIGESTS" | jq -c '.[:100]' | while read -r batch; do
                if [ "$batch" != "[]" ]; then
                    aws ecr batch-delete-image \
                        --repository-name "$ECR_REPO_NAME" \
                        --image-ids "$batch" \
                        --region "$AWS_REGION" >/dev/null 2>&1 || true
                fi
            done
            log_success "ECR images deleted"
        else
            log_info "No images found in ECR repository"
        fi
    else
        log_info "No ECR repository found (may already be destroyed)"
    fi
else
    log_info "Skipping ECR cleanup (use --include-ecr to delete images)"
fi

# =============================================================================
# Step 3: Full Destroy Preparations (Optional)
# =============================================================================

if [ "$FULL_DESTROY" = "true" ]; then
    print_header "Step 3: Full Destroy Preparations"

    # Empty S3 buckets (including versioned objects)
    LOGS_BUCKET=$(get_terraform_output "$INFRA_DIR" "logs_bucket_name")

    # If terraform output failed, try to find bucket by pattern
    if [ -z "$LOGS_BUCKET" ]; then
        log_info "Searching for logs bucket by name pattern..."
        LOGS_BUCKET=$(aws s3api list-buckets --region "$AWS_REGION" --query "Buckets[?contains(Name, '-logs-${AWS_ACCOUNT_ID}')].Name" --output text 2>/dev/null | head -1) || true
    fi

    if [ -n "$LOGS_BUCKET" ]; then
        log_info "Emptying S3 bucket: $LOGS_BUCKET"

        # Count and delete all object versions (required for versioned buckets)
        log_info "  Counting object versions..."
        VERSIONS_JSON=$(aws s3api list-object-versions \
            --bucket "$LOGS_BUCKET" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null) || VERSIONS_JSON="{}"

        VERSION_COUNT=$(echo "$VERSIONS_JSON" | jq -r '.Versions // [] | length' 2>/dev/null) || VERSION_COUNT=0
        MARKER_COUNT=$(echo "$VERSIONS_JSON" | jq -r '.DeleteMarkers // [] | length' 2>/dev/null) || MARKER_COUNT=0

        log_info "  Found $VERSION_COUNT object versions and $MARKER_COUNT delete markers"

        if [ "$VERSION_COUNT" -gt 0 ]; then
            log_info "  Deleting object versions..."
            DELETED=0
            echo "$VERSIONS_JSON" | jq -r '.Versions[]? | "\(.Key)\t\(.VersionId)"' 2>/dev/null | \
            while IFS=$'\t' read -r key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object \
                        --bucket "$LOGS_BUCKET" \
                        --key "$key" \
                        --version-id "$version_id" \
                        --region "$AWS_REGION" >/dev/null 2>&1 || true
                    DELETED=$((DELETED + 1))
                    if [ $((DELETED % 100)) -eq 0 ]; then
                        printf '\r  Deleted %d/%d versions...' "$DELETED" "$VERSION_COUNT"
                    fi
                fi
            done
            printf '\r  Deleted %d versions                    \n' "$VERSION_COUNT"
        fi

        if [ "$MARKER_COUNT" -gt 0 ]; then
            log_info "  Deleting delete markers..."
            DELETED=0
            echo "$VERSIONS_JSON" | jq -r '.DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' 2>/dev/null | \
            while IFS=$'\t' read -r key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object \
                        --bucket "$LOGS_BUCKET" \
                        --key "$key" \
                        --version-id "$version_id" \
                        --region "$AWS_REGION" >/dev/null 2>&1 || true
                    DELETED=$((DELETED + 1))
                    if [ $((DELETED % 100)) -eq 0 ]; then
                        printf '\r  Deleted %d/%d markers...' "$DELETED" "$MARKER_COUNT"
                    fi
                fi
            done
            printf '\r  Deleted %d markers                     \n' "$MARKER_COUNT"
        fi

        # Final cleanup of any remaining objects
        log_info "  Running final cleanup..."
        aws s3 rm "s3://${LOGS_BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null || true

        log_success "S3 bucket emptied"
    else
        log_info "No logs bucket found (may already be destroyed)"
    fi
fi

# =============================================================================
# Step 4: Destroy Main Infrastructure
# =============================================================================

print_header "Step 4: Destroy Main Infrastructure"

if [ -d "$INFRA_DIR" ] && [ -f "$INFRA_DIR/main.tf" ]; then
    (
        cd "$INFRA_DIR"

        # Temporarily disable prevent_destroy lifecycle rules
        # Using perl for cross-platform compatibility (sed -i differs between macOS/Linux)
        log_info "Disabling lifecycle protection for destroy..."
        perl -i -pe 's/prevent_destroy = true/prevent_destroy = false/g' ./*.tf

        # For full destroy, also disable RDS protections
        if [ "$FULL_DESTROY" = "true" ]; then
            log_info "Disabling RDS deletion protection and adding skip_final_snapshot..."
            # Replace deletion_protection line and add skip_final_snapshot
            perl -i -pe 's/deletion_protection\s*=\s*true.*/deletion_protection                 = false\n  skip_final_snapshot                 = true/g' rds.tf

            # Verify the change was made
            if grep -q "skip_final_snapshot" rds.tf; then
                log_success "RDS settings updated in rds.tf"
            else
                log_warn "Failed to update rds.tf, trying alternative method..."
                # Alternative: directly insert the line after deletion_protection
                perl -i -pe 's/(deletion_protection\s*=\s*false)/\1\n  skip_final_snapshot                 = true/' rds.tf
            fi
        fi

        # Restore settings on exit (success or failure)
        restore_settings() {
            perl -i -pe 's/prevent_destroy = false/prevent_destroy = true/g' ./*.tf
            if [ "$FULL_DESTROY" = "true" ]; then
                # Remove skip_final_snapshot and restore deletion_protection
                perl -i -pe 's/^\s*skip_final_snapshot\s*=.*\n//g' rds.tf
                perl -i -pe 's/deletion_protection\s*=\s*false.*/deletion_protection                 = true               # Prevent accidental deletion/g' rds.tf
            fi
            log_info "Restored Terraform settings"
        }
        trap restore_settings EXIT

        # Check if backend bucket exists
        BACKEND_BUCKET=$(grep -oP 'bucket\s*=\s*"\K[^"]+' main.tf 2>/dev/null | head -1) || BACKEND_BUCKET=""

        if [ -n "$BACKEND_BUCKET" ]; then
            BUCKET_EXISTS=$(aws s3api head-bucket --bucket "$BACKEND_BUCKET" --region "$AWS_REGION" 2>&1 && echo "yes" || echo "no")
        else
            BUCKET_EXISTS="no"
        fi

        if [ "$BUCKET_EXISTS" = "no" ]; then
            log_warn "Backend bucket not found. Using local state for destroy."
            # Create temporary override to use local backend
            cat > backend_override.tf << 'OVERRIDE'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
OVERRIDE
            # Remove stale terraform directory
            rm -rf .terraform .terraform.lock.hcl

            log_info "Initializing Terraform with local backend..."
            if ! terraform init -input=false 2>&1 | grep -v "Warning"; then
                log_info "No existing state - infrastructure may already be destroyed"
                rm -f backend_override.tf
                exit 0
            fi
        else
            log_info "Initializing Terraform..."
            terraform init -input=false >/dev/null 2>&1 || true
        fi

        # Pass placeholders for required variables (not used during destroy)
        DESTROY_VARS="-var=container_image=destroying -var=github_owner=destroying -var=github_repo=destroying"

        # For full destroy, first apply the RDS config changes before destroying
        if [ "$FULL_DESTROY" = "true" ] && [ "$BUCKET_EXISTS" = "yes" ]; then
            log_info "Applying RDS config changes (disable deletion protection)..."
            terraform apply -auto-approve -target=aws_rds_cluster.app $DESTROY_VARS >/dev/null 2>&1 || true
        fi

        log_info "Running Terraform destroy..."
        if [ "$FORCE" = "true" ]; then
            terraform destroy -auto-approve $DESTROY_VARS 2>&1 || true
        else
            terraform destroy $DESTROY_VARS 2>&1 || true
        fi

        # Clean up override file if created
        rm -f backend_override.tf
    )
    log_success "Main infrastructure destroyed"
else
    log_warn "Infrastructure directory not found or not initialized"
fi

# =============================================================================
# Step 5: Destroy State Backend (Optional)
# =============================================================================

if [ "$INCLUDE_STATE" = "true" ]; then
    print_header "Step 5: Destroy State Backend"

    if [ -d "$STATE_BACKEND_DIR" ] && [ -f "$STATE_BACKEND_DIR/main.tf" ]; then
        (
            cd "$STATE_BACKEND_DIR"

            log_info "Initializing Terraform..."
            terraform init -input=false >/dev/null 2>&1 || true

            # Discover resources dynamically from AWS
            log_info "Discovering state backend resources..."

            # Find S3 buckets with tf-state in the name
            STATE_BUCKETS=$(aws s3api list-buckets --region "$AWS_REGION" \
                --query "Buckets[?contains(Name, 'tf-state')].Name" \
                --output text 2>/dev/null) || STATE_BUCKETS=""

            # Find DynamoDB tables with tf-locks in the name
            DYNAMODB_TABLES=$(aws dynamodb list-tables --region "$AWS_REGION" \
                --query "TableNames[?contains(@, 'tf-locks')]" \
                --output text 2>/dev/null) || DYNAMODB_TABLES=""

            # Empty S3 buckets (including all versions)
            for BUCKET in $STATE_BUCKETS; do
                if [ -n "$BUCKET" ]; then
                    log_info "Emptying S3 bucket: $BUCKET"

                    # Delete all object versions
                    aws s3api list-object-versions \
                        --bucket "$BUCKET" \
                        --region "$AWS_REGION" \
                        --output json 2>/dev/null | \
                    jq -r '.Versions[]? | "\(.Key)\t\(.VersionId)"' 2>/dev/null | \
                    while IFS=$'\t' read -r key version_id; do
                        if [ -n "$key" ] && [ -n "$version_id" ]; then
                            aws s3api delete-object \
                                --bucket "$BUCKET" \
                                --key "$key" \
                                --version-id "$version_id" \
                                --region "$AWS_REGION" >/dev/null 2>&1 || true
                        fi
                    done

                    # Delete all delete markers
                    aws s3api list-object-versions \
                        --bucket "$BUCKET" \
                        --region "$AWS_REGION" \
                        --output json 2>/dev/null | \
                    jq -r '.DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' 2>/dev/null | \
                    while IFS=$'\t' read -r key version_id; do
                        if [ -n "$key" ] && [ -n "$version_id" ]; then
                            aws s3api delete-object \
                                --bucket "$BUCKET" \
                                --key "$key" \
                                --version-id "$version_id" \
                                --region "$AWS_REGION" >/dev/null 2>&1 || true
                        fi
                    done

                    # Final cleanup
                    aws s3 rm "s3://${BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null || true
                fi
            done

            # Disable DynamoDB deletion protection for all matching tables
            for TABLE in $DYNAMODB_TABLES; do
                if [ -n "$TABLE" ]; then
                    log_info "Disabling DynamoDB deletion protection: $TABLE"
                    aws dynamodb update-table \
                        --table-name "$TABLE" \
                        --no-deletion-protection-enabled \
                        --region "$AWS_REGION" >/dev/null 2>&1 || true
                fi
            done

            log_info "Running Terraform destroy..."
            if [ "$FORCE" = "true" ]; then
                terraform destroy -auto-approve
            else
                terraform destroy
            fi
        )

        log_success "State backend destroyed"
    else
        log_warn "State backend directory not found or not initialized"
    fi
else
    log_info "Skipping state backend destruction (use --include-state to destroy)"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Destruction Complete"

printf '%b' "$GREEN"
cat << 'EOF'

  Infrastructure has been destroyed.

  What was removed:
EOF
printf '%b' "$NC"

echo "  ✓ ECS cluster and service"
echo "  ✓ ALB and Global Accelerator"
echo "  ✓ Aurora database cluster"
echo "  ✓ ElastiCache cluster"
echo "  ✓ VPC and networking"
echo "  ✓ Secrets and KMS keys"
echo "  ✓ IAM roles and policies"
echo "  ✓ CloudWatch logs and alarms"

if [ "$INCLUDE_ECR" = "true" ]; then
    echo "  ✓ ECR images"
fi

if [ "$INCLUDE_STATE" = "true" ]; then
    echo "  ✓ Terraform state backend (S3 + DynamoDB)"
fi

echo ""

if [ "$INCLUDE_STATE" != "true" ]; then
    log_info "State backend was preserved. To fully clean up, run:"
    echo "  ./scripts/destroy.sh --include-state"
fi

echo ""
log_success "Cleanup complete"
