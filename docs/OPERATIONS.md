# Operations Guide

This document covers deployment, scaling, upgrades, and day-2 operations.

## Table of Contents

- [Prerequisites](#prerequisites)
- [One-Time Bootstrap](#one-time-bootstrap)
- [Deploy the Stack](#deploy-the-stack)
- [Updates and Rollbacks](#updates-and-rollbacks)
- [Scaling](#scaling)
- [Secrets Rotation](#secrets-rotation)
- [Backups](#backups)
- [Logs and Monitoring](#logs-and-monitoring)
- [Disaster Recovery](#disaster-recovery)
- [Operational Checklists](#operational-checklists)

## Prerequisites

- AWS account with permissions to create VPC, ECS, RDS, IAM, etc.
- AWS CLI configured with appropriate credentials
- Terraform installed (see `infra/README.md` for version)
- Docker installed for building images
- (Optional) ACM certificate for HTTPS

## One-Time Bootstrap

1. **Create the remote Terraform backend**
   ```bash
   cd state-backend
   terraform init
   terraform apply -auto-approve
   ```

2. **Note the outputs**
   - The S3 bucket name and DynamoDB table name will be used by the main infra.

## Deploy the Stack

Use `scripts/deploy-local.sh` for a streamlined deployment:

```bash
# Set required environment variables
export AWS_REGION=us-east-1
export ENVIRONMENT=prod

# Run the deployment
./scripts/deploy-local.sh
```

**Manual deployment steps:**

1. **Build and push the image**
   ```bash
   cd app
   docker build -t your-ecr-repo:tag .
   docker push your-ecr-repo:tag
   ```

2. **Apply Terraform**
   ```bash
   cd infra
   terraform init
   terraform plan -var="container_image=your-ecr-repo:tag"
   terraform apply -var="container_image=your-ecr-repo:tag"
   ```

3. **Verify**
   - Hit `/healthz` on the ALB endpoint.
   - Confirm ECS tasks are healthy.

See `docs/LOCAL_DEPLOY.md` for detailed prerequisites and environment variables.

## Updates and Rollbacks

- **App updates**: Build a new image, push to ECR, and re-apply Terraform.
- **Infra changes**: Update Terraform files and run `terraform apply`.
- **Rollback**: Re-deploy a previous container image tag and apply again.

Example rollback:
```bash
cd infra
terraform apply -var="container_image=your-ecr-repo:previous-tag"
```

## Scaling

ECS auto scaling uses CPU target utilization. Adjust these variables in `infra/variables.tf`:

- `ecs_min_capacity` - Minimum number of tasks
- `ecs_max_capacity` - Maximum number of tasks
- `ecs_cpu_target_utilization` - Target CPU percentage for scaling

Aurora Serverless v2 scales automatically by ACUs. Adjust min/max ACUs in `variables.tf` if needed:

- `aurora_min_capacity` - Minimum ACUs
- `aurora_max_capacity` - Maximum ACUs

## Secrets Rotation

Secrets rotate via AWS Secrets Manager and custom Lambdas:

- **DB password** rotates every 30 days
- **Valkey auth token** rotates every 30 days
- **SECRET_KEY_BASE** rotates every 90 days

Rotation Lambdas trigger ECS deployments so tasks pick up new values automatically.

To manually trigger rotation:
```bash
aws secretsmanager rotate-secret --secret-id your-secret-arn
```

## Backups

- AWS Backup stores snapshots of the Aurora cluster.
- Retention is configurable in `infra/backup.tf`.
- Cross-region replication is enabled by default.

To restore from backup, use the AWS Console or CLI:
```bash
aws backup start-restore-job --recovery-point-arn <arn> --metadata <metadata>
```

## Logs and Monitoring

- **CloudWatch Logs**: ECS task logs, Lambda logs
- **CloudWatch Dashboard**: Pre-built dashboard in `infra/monitoring.tf`
- **CloudWatch Alarms**: Alerts for CPU, memory, errors, latency
- **CloudTrail**: AWS API activity
- **VPC Flow Logs**: Network traffic logging
- **ALB logs**: Optional request logging to S3

Access logs:
```bash
# View recent ECS logs
aws logs tail /ecs/your-cluster --follow

# View Lambda rotation logs
aws logs tail /aws/lambda/db-password-rotation --follow
```

## Disaster Recovery

1. **Data loss recovery**
   - Use AWS Backup to restore Aurora from a recovery point.
   - Point-in-time recovery is available for granular restore.

2. **Infrastructure recovery**
   - Re-apply Terraform to reconstruct infrastructure.
   - Terraform state is stored in S3 with versioning.

3. **Region failover** (if configured)
   - Global Accelerator provides health-based routing.
   - Deploy to secondary region using the same Terraform with different backend.

## Operational Checklists

**Pre-deploy**
- [ ] Terraform plan is clean (no unexpected changes)
- [ ] Image build succeeded
- [ ] Required secrets exist in Secrets Manager
- [ ] Security scans passed (`scripts/run-checkov.sh`, `scripts/run-kics.sh`)

**Post-deploy**
- [ ] `/healthz` returns 200
- [ ] ECS service shows desired task count
- [ ] Database connections are healthy
- [ ] CloudWatch dashboard shows normal metrics

**Weekly maintenance**
- [ ] Review CloudWatch alarms
- [ ] Check for pending Dependabot updates
- [ ] Review cost reports in AWS Cost Explorer

For incident-specific guidance, see `docs/TROUBLESHOOTING.md`.
