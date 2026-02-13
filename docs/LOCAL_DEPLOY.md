## Local Deployment (Laptop)

Use this guide to deploy the entire infrastructure from your laptop using a
single command. The deployment script handles everything: building the container
image, pushing to ECR, and applying Terraform.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Deploy](#quick-deploy)
- [Environment Variables](#environment-variables)
- [Deployment Options](#deployment-options)
- [Health Monitoring](#health-monitoring)
- [Tear Down](#tear-down)
- [Troubleshooting](#troubleshooting)

### Prerequisites

- **AWS CLI** configured with credentials (`aws configure`)
- **Container runtime**: Docker, Finch, or Podman (auto-detected)
- **Terraform** 1.6+
- **jq** for JSON processing
- IAM permissions to create/modify AWS resources

> **Note**: The deploy script automatically detects your container runtime.
> To override, set `CONTAINER_RUNTIME=finch` or `CONTAINER_RUNTIME=podman`.

### Quick Deploy

```bash
# 1. Set required environment variables
export TF_VAR_github_owner="your-github-username"
export TF_VAR_github_repo="backend-api-accelerator"

# 2. Configure HTTPS certificate (choose one option)
# Option A: Auto-create certificate with Route 53 (recommended)
export TF_VAR_domain_name="api.example.com"
export TF_VAR_route53_zone_name="example.com"

# Option B: Use an existing ACM certificate
# export TF_VAR_alb_acm_certificate_arn="arn:aws:acm:us-east-1:123456789:certificate/abc123"

# 3. First-time deployment (includes state backend setup)
./scripts/deploy.sh --init-state

# 4. Subsequent deployments (state backend already exists)
./scripts/deploy.sh
```

### Environment Variables

#### Required

| Name | Purpose |
|------|---------|
| `TF_VAR_github_owner` | GitHub org/user name for OIDC trust. |
| `TF_VAR_github_repo` | GitHub repo name for OIDC trust. |

#### HTTPS Certificate (choose one)

| Option | Variables | Description |
|--------|-----------|-------------|
| **Auto-create** | `TF_VAR_domain_name` + `TF_VAR_route53_zone_name` | Terraform creates and validates the certificate automatically. Also sets up DNS records. |
| **Existing cert** | `TF_VAR_alb_acm_certificate_arn` | Use an ACM certificate you've already created. |

#### Optional

| Name | Default | Purpose |
|------|---------|---------|
| `AWS_REGION` | `us-east-1` | AWS region for deployment. |
| `ENVIRONMENT` | `prod` | Environment name (prod, staging, dev). |
| `ECR_REPOSITORY` | `backend-service` | ECR repository name. |
| `IMAGE_TAG` | Git short SHA | Container image tag. |
| `PLATFORM` | `linux/arm64` | Build platform (arm64 for Graviton). |
| `CONTAINER_RUNTIME` | auto-detected | Container runtime: `docker`, `finch`, or `podman`. |

### Deployment Options

```bash
# Full deployment (build, push, apply)
./scripts/deploy.sh

# First-time deployment with state backend
./scripts/deploy.sh --init-state

# Preview changes without applying
./scripts/deploy.sh --plan-only

# Redeploy without rebuilding image
./scripts/deploy.sh --skip-build

# Skip confirmation prompts
./scripts/deploy.sh --auto-approve
```

### Container Runtime

The deploy script supports **Docker**, **Finch**, and **Podman**. It will
automatically detect which one you have installed, preferring them in that order.

```bash
# Auto-detect (default)
./scripts/deploy.sh

# Use Finch explicitly
CONTAINER_RUNTIME=finch ./scripts/deploy.sh

# Use Podman explicitly
CONTAINER_RUNTIME=podman ./scripts/deploy.sh
```

#### Runtime-Specific Notes

| Runtime | Notes |
|---------|-------|
| **Docker** | Requires Docker Desktop or Docker Engine with Buildx enabled. |
| **Finch** | AWS's open-source container tool. Great for macOS without Docker Desktop. |
| **Podman** | Daemonless container engine. Build and push are done separately. |

### What It Does

The `deploy.sh` script performs these steps:

1. **Pre-flight checks** – Verifies AWS credentials and required tools
2. **State backend** (optional) – Creates S3 bucket and DynamoDB for Terraform state
3. **Docker build** – Builds the Phoenix app container for ARM64
4. **ECR push** – Pushes the image to Elastic Container Registry
5. **Terraform apply** – Deploys all infrastructure
6. **Stability wait** – Waits for ECS service to stabilize
7. **Summary** – Displays endpoints and next steps

### Health Monitoring

After deployment, check the health of all components:

```bash
# Full health report
./scripts/deployment-health-report.sh

# Quick status check
./scripts/deployment-health-report.sh --quick

# JSON output (for automation)
./scripts/deployment-health-report.sh --json
```

The health report checks:
- ECS service status and task count
- ALB target health
- Aurora database status
- ElastiCache (Valkey) status
- Application health endpoint (`/healthz`)
- Recent error logs

### Tear Down

```bash
# Destroy main infrastructure (preserves state backend)
./scripts/destroy.sh

# Destroy everything including state backend
./scripts/destroy.sh --include-state

# Also delete ECR images
./scripts/destroy.sh --include-ecr

# Skip confirmations (DANGEROUS)
./scripts/destroy.sh --force
```

### Troubleshooting

#### ECR Push Fails

```bash
# Verify ECR login works
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
```

#### Terraform State Issues

```bash
# Reinitialize Terraform
cd infra && terraform init -reconfigure
```

#### Service Won't Stabilize

```bash
# Check ECS service events
aws ecs describe-services --cluster <cluster> --services <service> --query 'services[0].events[:5]'

# Check task stopped reasons
aws ecs describe-tasks --cluster <cluster> --tasks <task-arn> --query 'tasks[0].stoppedReason'

# View application logs
./scripts/deployment-health-report.sh
```

#### Missing Environment Variables

```bash
# Verify all required variables are set
env | grep TF_VAR
```

See also: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for more common issues.
