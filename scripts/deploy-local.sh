#!/usr/bin/env bash
#
# Legacy deploy script - consider using ./scripts/deploy.sh instead
# This script is kept for backward compatibility.
#
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
APP_DIR=${APP_DIR:-"$ROOT_DIR/app"}
TF_DIR=${TF_DIR:-"$ROOT_DIR/infra"}

AWS_REGION=${AWS_REGION:-"us-east-1"}
ENVIRONMENT=${ENVIRONMENT:-"prod"}
ECR_REPOSITORY=${ECR_REPOSITORY:-"backend-service"}
PLATFORM=${PLATFORM:-"linux/arm64"}
IMAGE_TAG=${IMAGE_TAG:-"$(git -C "$ROOT_DIR" rev-parse --short HEAD)"}
SKIP_TERRAFORM=${SKIP_TERRAFORM:-"false"}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-""}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  if [ -z "${!1:-}" ]; then
    echo "Missing required environment variable: $1" >&2
    exit 1
  fi
}

# Detect container runtime (docker, finch, or podman)
detect_runtime() {
  if [ -n "$CONTAINER_RUNTIME" ]; then
    echo "$CONTAINER_RUNTIME"
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    echo "docker"
  elif command -v finch >/dev/null 2>&1; then
    echo "finch"
  elif command -v podman >/dev/null 2>&1; then
    echo "podman"
  else
    echo "No container runtime found (docker, finch, or podman)" >&2
    exit 1
  fi
}

require_cmd aws
require_cmd terraform
require_cmd git

RUNTIME=$(detect_runtime)
echo "Using container runtime: $RUNTIME"

if [ ! -d "$APP_DIR" ]; then
  echo "App directory not found: $APP_DIR" >&2
  exit 1
fi

if [ ! -d "$TF_DIR" ]; then
  echo "Terraform directory not found: $TF_DIR" >&2
  exit 1
fi

echo "Checking AWS credentials..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

echo "Ensuring ECR repository exists: ${ECR_REPOSITORY}"
if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "$ECR_REPOSITORY" --region "$AWS_REGION" >/dev/null
fi

echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | $RUNTIME login --username AWS --password-stdin "$ECR_REGISTRY"

echo "Building and pushing image: ${IMAGE_URI}"
case "$RUNTIME" in
  docker)
    docker buildx build \
      --platform "$PLATFORM" \
      -t "$IMAGE_URI" \
      --push \
      "$APP_DIR"
    ;;
  finch)
    finch build \
      --platform "$PLATFORM" \
      -t "$IMAGE_URI" \
      --push \
      "$APP_DIR"
    ;;
  podman)
    podman build \
      --platform "$PLATFORM" \
      -t "$IMAGE_URI" \
      "$APP_DIR"
    podman push "$IMAGE_URI"
    ;;
esac

if [ "$SKIP_TERRAFORM" = "true" ]; then
  echo "Skipping Terraform apply (SKIP_TERRAFORM=true)"
  exit 0
fi

require_env TF_VAR_github_owner
require_env TF_VAR_github_repo
require_env TF_VAR_alb_acm_certificate_arn

export TF_VAR_container_image="$IMAGE_URI"
export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_environment="$ENVIRONMENT"

echo "Running Terraform in ${TF_DIR}"
(
  cd "$TF_DIR" || exit 1
  terraform init -input=false
  terraform validate
  terraform apply -auto-approve
)

echo "Deployment complete."
echo "Image: ${IMAGE_URI}"
