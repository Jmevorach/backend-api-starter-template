#!/usr/bin/env bash
#
# Deployment Health Report
# ========================
# Comprehensive health check of the deployed infrastructure.
#
# Usage:
#   ./scripts/deployment-health-report.sh              # Full report
#   ./scripts/deployment-health-report.sh --quick      # Quick status only
#   ./scripts/deployment-health-report.sh --json       # Output as JSON
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

AWS_REGION="${AWS_REGION:-us-east-1}"
QUICK_MODE=false
JSON_OUTPUT=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Status tracking
declare -A STATUS
OVERALL_HEALTHY=true

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$1"; }
log_success() { printf '%b[✓]%b %s\n' "$GREEN" "$NC" "$1"; }
log_warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$1"; }
log_error() { printf '%b[✗]%b %s\n' "$RED" "$NC" "$1"; }

print_header() {
    printf '\n%b' "$CYAN"
    printf '═══════════════════════════════════════════════════════════════════\n'
    printf '  %s\n' "$1"
    printf '═══════════════════════════════════════════════════════════════════%b\n' "$NC"
}

print_section() {
    printf '\n%b── %s ──%b\n\n' "$YELLOW" "$1" "$NC"
}

set_status() {
    local component="$1"
    local status="$2"
    STATUS["$component"]="$status"
    if [ "$status" != "healthy" ]; then
        OVERALL_HEALTHY=false
    fi
}

get_terraform_output() {
    local output_name="$1"
    (cd "$INFRA_DIR" && terraform output -raw "$output_name" 2>/dev/null) || echo ""
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --quick|-q)
            QUICK_MODE=true
            shift
            ;;
        --json|-j)
            JSON_OUTPUT=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --quick, -q      Quick status check only"
            echo "  --json, -j       Output results as JSON"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# Pre-flight
# =============================================================================

if [ "$JSON_OUTPUT" != "true" ]; then
    print_header "Deployment Health Report"
    printf '%b%-20s%b %s\n' "$CYAN" "Timestamp:" "$NC" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf '%b%-20s%b %s\n' "$CYAN" "Region:" "$NC" "$AWS_REGION"
fi

# Check if infrastructure is deployed
if [ ! -f "$INFRA_DIR/terraform.tfstate" ] && [ ! -d "$INFRA_DIR/.terraform" ]; then
    log_error "Infrastructure not deployed. Run './scripts/deploy.sh' first."
    exit 1
fi

# Get Terraform outputs
ECS_CLUSTER=$(get_terraform_output "ecs_cluster_name")
ECS_SERVICE=$(get_terraform_output "ecs_service_name")
ALB_ARN=$(get_terraform_output "alb_arn")
ALB_DNS=$(get_terraform_output "alb_dns_name")
GA_DNS=$(get_terraform_output "global_accelerator_dns_name")
AURORA_CLUSTER_ARN=$(get_terraform_output "aurora_cluster_arn")
ELASTICACHE_ARN=$(get_terraform_output "elasticache_arn")

if [ -z "$ECS_CLUSTER" ]; then
    log_error "Could not read Terraform outputs. Ensure 'terraform apply' completed successfully."
    exit 1
fi

# =============================================================================
# ECS Service Health
# =============================================================================

if [ "$JSON_OUTPUT" != "true" ]; then
    print_section "ECS Service"
fi

ECS_STATUS=$(aws ecs describe-services \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --region "$AWS_REGION" \
    --query 'services[0]' \
    --output json 2>/dev/null || echo "{}")

if [ "$ECS_STATUS" != "{}" ] && [ -n "$ECS_STATUS" ]; then
    RUNNING_COUNT=$(echo "$ECS_STATUS" | jq -r '.runningCount // 0')
    DESIRED_COUNT=$(echo "$ECS_STATUS" | jq -r '.desiredCount // 0')
    PENDING_COUNT=$(echo "$ECS_STATUS" | jq -r '.pendingCount // 0')
    SERVICE_STATUS=$(echo "$ECS_STATUS" | jq -r '.status // "UNKNOWN"')

    if [ "$JSON_OUTPUT" != "true" ]; then
        printf '%-25s %s\n' "Cluster:" "$ECS_CLUSTER"
        printf '%-25s %s\n' "Service:" "$ECS_SERVICE"
        printf '%-25s %s\n' "Status:" "$SERVICE_STATUS"
        printf '%-25s %s/%s (pending: %s)\n' "Tasks:" "$RUNNING_COUNT" "$DESIRED_COUNT" "$PENDING_COUNT"
    fi

    if [ "$RUNNING_COUNT" -eq "$DESIRED_COUNT" ] && [ "$RUNNING_COUNT" -gt 0 ]; then
        set_status "ecs" "healthy"
        [ "$JSON_OUTPUT" != "true" ] && log_success "ECS service is healthy"
    elif [ "$RUNNING_COUNT" -gt 0 ]; then
        set_status "ecs" "degraded"
        [ "$JSON_OUTPUT" != "true" ] && log_warn "ECS service is degraded"
    else
        set_status "ecs" "unhealthy"
        [ "$JSON_OUTPUT" != "true" ] && log_error "ECS service is unhealthy"
    fi

    # Show recent deployments
    if [ "$QUICK_MODE" != "true" ] && [ "$JSON_OUTPUT" != "true" ]; then
        echo ""
        DEPLOYMENTS=$(echo "$ECS_STATUS" | jq -r '.deployments[] | "  \(.status): \(.runningCount)/\(.desiredCount) tasks (\(.rolloutState // "N/A"))"')
        if [ -n "$DEPLOYMENTS" ]; then
            echo "Recent Deployments:"
            echo "$DEPLOYMENTS"
        fi
    fi
else
    set_status "ecs" "unknown"
    [ "$JSON_OUTPUT" != "true" ] && log_error "Could not fetch ECS service status"
fi

# =============================================================================
# ALB Target Health
# =============================================================================

if [ "$JSON_OUTPUT" != "true" ]; then
    print_section "Load Balancer"
fi

# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
    --load-balancer-arn "$ALB_ARN" \
    --region "$AWS_REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
    TARGET_HEALTH=$(aws elbv2 describe-target-health \
        --target-group-arn "$TG_ARN" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null || echo '{"TargetHealthDescriptions":[]}')

    HEALTHY_TARGETS=$(echo "$TARGET_HEALTH" | jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length')
    UNHEALTHY_TARGETS=$(echo "$TARGET_HEALTH" | jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State != "healthy")] | length')
    TOTAL_TARGETS=$(echo "$TARGET_HEALTH" | jq '.TargetHealthDescriptions | length')

    if [ "$JSON_OUTPUT" != "true" ]; then
        printf '%-25s %s\n' "ALB DNS:" "$ALB_DNS"
        printf '%-25s %s healthy, %s unhealthy (total: %s)\n' "Targets:" "$HEALTHY_TARGETS" "$UNHEALTHY_TARGETS" "$TOTAL_TARGETS"
    fi

    if [ "$HEALTHY_TARGETS" -gt 0 ] && [ "$UNHEALTHY_TARGETS" -eq 0 ]; then
        set_status "alb" "healthy"
        [ "$JSON_OUTPUT" != "true" ] && log_success "All ALB targets healthy"
    elif [ "$HEALTHY_TARGETS" -gt 0 ]; then
        set_status "alb" "degraded"
        [ "$JSON_OUTPUT" != "true" ] && log_warn "Some ALB targets unhealthy"
    else
        set_status "alb" "unhealthy"
        [ "$JSON_OUTPUT" != "true" ] && log_error "No healthy ALB targets"
    fi

    # Show individual target status
    if [ "$QUICK_MODE" != "true" ] && [ "$JSON_OUTPUT" != "true" ] && [ "$TOTAL_TARGETS" -gt 0 ]; then
        echo ""
        echo "Target Details:"
        echo "$TARGET_HEALTH" | jq -r '.TargetHealthDescriptions[] | "  \(.Target.Id): \(.TargetHealth.State) (\(.TargetHealth.Reason // "OK"))"'
    fi
else
    set_status "alb" "unknown"
    [ "$JSON_OUTPUT" != "true" ] && log_warn "Could not fetch ALB target health"
fi

# =============================================================================
# Aurora Database Health
# =============================================================================

if [ "$JSON_OUTPUT" != "true" ]; then
    print_section "Aurora Database"
fi

# Extract cluster identifier from ARN
AURORA_CLUSTER_ID=$(echo "$AURORA_CLUSTER_ARN" | sed 's/.*:cluster://')

if [ -n "$AURORA_CLUSTER_ID" ]; then
    AURORA_STATUS=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$AURORA_CLUSTER_ID" \
        --region "$AWS_REGION" \
        --query 'DBClusters[0]' \
        --output json 2>/dev/null || echo "{}")

    if [ "$AURORA_STATUS" != "{}" ] && [ -n "$AURORA_STATUS" ]; then
        CLUSTER_STATUS=$(echo "$AURORA_STATUS" | jq -r '.Status // "unknown"')
        CAPACITY=$(echo "$AURORA_STATUS" | jq -r '.ServerlessV2ScalingConfiguration.MinCapacity // "N/A"')
        MAX_CAPACITY=$(echo "$AURORA_STATUS" | jq -r '.ServerlessV2ScalingConfiguration.MaxCapacity // "N/A"')

        if [ "$JSON_OUTPUT" != "true" ]; then
            printf '%-25s %s\n' "Cluster ID:" "$AURORA_CLUSTER_ID"
            printf '%-25s %s\n' "Status:" "$CLUSTER_STATUS"
            printf '%-25s %s - %s ACUs\n' "Capacity:" "$CAPACITY" "$MAX_CAPACITY"
        fi

        if [ "$CLUSTER_STATUS" = "available" ]; then
            set_status "aurora" "healthy"
            [ "$JSON_OUTPUT" != "true" ] && log_success "Aurora cluster is healthy"
        else
            set_status "aurora" "degraded"
            [ "$JSON_OUTPUT" != "true" ] && log_warn "Aurora cluster status: $CLUSTER_STATUS"
        fi
    else
        set_status "aurora" "unknown"
        [ "$JSON_OUTPUT" != "true" ] && log_error "Could not fetch Aurora status"
    fi
else
    set_status "aurora" "unknown"
    [ "$JSON_OUTPUT" != "true" ] && log_warn "Aurora cluster not found"
fi

# =============================================================================
# ElastiCache Health
# =============================================================================

if [ "$JSON_OUTPUT" != "true" ]; then
    print_section "ElastiCache (Valkey)"
fi

# Extract cache name from ARN
CACHE_NAME=$(echo "$ELASTICACHE_ARN" | sed 's/.*:serverlesscache://')

if [ -n "$CACHE_NAME" ]; then
    CACHE_STATUS=$(aws elasticache describe-serverless-caches \
        --serverless-cache-name "$CACHE_NAME" \
        --region "$AWS_REGION" \
        --query 'ServerlessCaches[0]' \
        --output json 2>/dev/null || echo "{}")

    if [ "$CACHE_STATUS" != "{}" ] && [ -n "$CACHE_STATUS" ]; then
        STATUS_VAL=$(echo "$CACHE_STATUS" | jq -r '.Status // "unknown"')
        ENDPOINT=$(echo "$CACHE_STATUS" | jq -r '.Endpoint.Address // "N/A"')

        if [ "$JSON_OUTPUT" != "true" ]; then
            printf '%-25s %s\n' "Cache Name:" "$CACHE_NAME"
            printf '%-25s %s\n' "Status:" "$STATUS_VAL"
            printf '%-25s %s\n' "Endpoint:" "$ENDPOINT"
        fi

        if [ "$STATUS_VAL" = "available" ]; then
            set_status "elasticache" "healthy"
            [ "$JSON_OUTPUT" != "true" ] && log_success "ElastiCache is healthy"
        else
            set_status "elasticache" "degraded"
            [ "$JSON_OUTPUT" != "true" ] && log_warn "ElastiCache status: $STATUS_VAL"
        fi
    else
        set_status "elasticache" "unknown"
        [ "$JSON_OUTPUT" != "true" ] && log_error "Could not fetch ElastiCache status"
    fi
else
    set_status "elasticache" "unknown"
    [ "$JSON_OUTPUT" != "true" ] && log_warn "ElastiCache not found"
fi

# =============================================================================
# Health Endpoint Check
# =============================================================================

if [ "$JSON_OUTPUT" != "true" ]; then
    print_section "Application Health Endpoint"
fi

HEALTH_URL="https://${ALB_DNS}/healthz"

if [ "$JSON_OUTPUT" != "true" ]; then
    printf '%-25s %s\n' "URL:" "$HEALTH_URL"
fi

# Try to hit the health endpoint
HEALTH_RESPONSE=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 10 "$HEALTH_URL" 2>/dev/null || echo "000")

if [ "$JSON_OUTPUT" != "true" ]; then
    printf '%-25s %s\n' "HTTP Status:" "$HEALTH_RESPONSE"
fi

if [ "$HEALTH_RESPONSE" = "200" ]; then
    set_status "health_endpoint" "healthy"
    [ "$JSON_OUTPUT" != "true" ] && log_success "Health endpoint responding"
elif [ "$HEALTH_RESPONSE" = "000" ]; then
    set_status "health_endpoint" "unreachable"
    [ "$JSON_OUTPUT" != "true" ] && log_error "Health endpoint unreachable"
else
    set_status "health_endpoint" "unhealthy"
    [ "$JSON_OUTPUT" != "true" ] && log_warn "Health endpoint returned: $HEALTH_RESPONSE"
fi

# =============================================================================
# Recent Errors (CloudWatch Logs)
# =============================================================================

if [ "$QUICK_MODE" != "true" ] && [ "$JSON_OUTPUT" != "true" ]; then
    print_section "Recent Application Logs"

    LOG_GROUP=$(get_terraform_output "ecs_log_group_name")

    if [ -n "$LOG_GROUP" ]; then
        log_info "Fetching recent error logs from: $LOG_GROUP"
        echo ""

        # Get logs from the last 30 minutes
        START_TIME=$(($(date +%s) * 1000 - 1800000))

        RECENT_ERRORS=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time "$START_TIME" \
            --filter-pattern "?ERROR ?error ?Error ?WARN ?warn ?Warn" \
            --limit 10 \
            --region "$AWS_REGION" \
            --query 'events[].message' \
            --output text 2>/dev/null || echo "")

        if [ -n "$RECENT_ERRORS" ] && [ "$RECENT_ERRORS" != "None" ]; then
            log_warn "Recent errors/warnings found:"
            echo "$RECENT_ERRORS" | head -20
        else
            log_success "No recent errors found"
        fi
    else
        log_warn "Could not determine log group"
    fi
fi

# =============================================================================
# Summary
# =============================================================================

if [ "$JSON_OUTPUT" = "true" ]; then
    # JSON output
    cat <<EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "region": "$AWS_REGION",
  "overall_healthy": $OVERALL_HEALTHY,
  "components": {
    "ecs": "${STATUS[ecs]:-unknown}",
    "alb": "${STATUS[alb]:-unknown}",
    "aurora": "${STATUS[aurora]:-unknown}",
    "elasticache": "${STATUS[elasticache]:-unknown}",
    "health_endpoint": "${STATUS[health_endpoint]:-unknown}"
  },
  "endpoints": {
    "alb_dns": "$ALB_DNS",
    "global_accelerator_dns": "$GA_DNS",
    "health_url": "$HEALTH_URL"
  }
}
EOF
else
    print_header "Summary"

    printf '\n'
    printf '%-20s %s\n' "Component" "Status"
    printf '%-20s %s\n' "─────────" "──────"

    for component in ecs alb aurora elasticache health_endpoint; do
        status="${STATUS[$component]:-unknown}"
        case $status in
            healthy)
                printf '%-20s %b%s%b\n' "$component" "$GREEN" "$status" "$NC"
                ;;
            degraded)
                printf '%-20s %b%s%b\n' "$component" "$YELLOW" "$status" "$NC"
                ;;
            unhealthy|unreachable)
                printf '%-20s %b%s%b\n' "$component" "$RED" "$status" "$NC"
                ;;
            *)
                printf '%-20s %b%s%b\n' "$component" "$YELLOW" "$status" "$NC"
                ;;
        esac
    done

    echo ""

    if [ "$OVERALL_HEALTHY" = "true" ]; then
        log_success "All systems operational"
        exit 0
    else
        log_warn "Some components need attention"
        exit 1
    fi
fi
