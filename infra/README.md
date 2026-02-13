## Infra – AWS Terraform Stack

This directory contains Terraform code for the production-grade AWS
infrastructure that powers the Phoenix API service.

### Table of Contents

- [Architecture Highlights](#architecture-highlights)
- [Structure](#structure)
- [Providers & State](#providers--state)
- [Key Variables](#key-variables)
- [Typical Workflow](#typical-workflow)
- [Secrets and Rotation](#secrets-and-rotation)
- [Notes for Production](#notes-for-production)

### Architecture Highlights

- Global Accelerator → ALB → ECS Fargate service
- Aurora Serverless v2 (PostgreSQL) with RDS Proxy in private subnets
- ElastiCache Serverless (Valkey) for session storage
- AWS Backup with long-term retention policies
- Centralized logging (CloudWatch, S3 logs, VPC Flow Logs, CloudTrail)
- Secrets Manager + KMS encryption
- Automatic secret rotation via Lambdas in `infra/lambdas/`

### Structure

- `main.tf` – Root wiring and shared locals
- `variables.tf` – Input variables
- `outputs.tf` – Important outputs
- `network.tf` – VPC, subnets, NAT, flow logs
- `iam.tf` – IAM roles and policies
- `logging.tf` – CloudWatch, S3 logs, CloudTrail
- `ecs.tf` – ECS cluster, task definition, service, ALB
- `rds.tf` – Aurora Serverless v2, RDS Proxy
- `elasticache.tf` – Valkey/ElastiCache
- `backup.tf` – Backup vault/plan
- `secret-rotation.tf` – Rotation schedule + Lambda wiring
- `secrets.tf` – Secrets Manager secrets
- `kms.tf` – KMS keys
- `ecr.tf` – ECR repository

### Providers & State

Use a remote backend (S3 + DynamoDB) for real environments. The bootstrap
configuration lives in `state-backend/`.

### Key Variables

- `aws_region`
- `environment`
- `container_image`
- `service_desired_count`
- `alb_acm_certificate_arn`
- `lambda_python_runtime` (default `python3.14`)

See `ENVIRONMENT.md` for the full list of variables and GitHub secrets/vars.

### Typical Workflow

1. **Bootstrap state backend**
   - Run `terraform apply` in `state-backend/` once per account/region.
2. **Initialize infra**
   - `terraform init` in `infra/` (will use the remote backend).
3. **Plan**
   - `terraform plan -var="container_image=..."`
4. **Apply**
   - `terraform apply -auto-approve -var="container_image=..."`

### Secrets and Rotation

Secrets are generated in Terraform and stored in AWS Secrets Manager. Rotation
Lambdas update secrets and trigger ECS deployments so tasks pick up new values.

Lambdas live in `infra/lambdas/` and are packaged automatically by Terraform.

### Notes for Production

- Attach an ACM certificate for ALB HTTPS.
- Configure GitHub OIDC and CI/CD with the least-privilege role.
- Adjust scaling and cost limits to match expected traffic.

For deep details, see `docs/ARCHITECTURE.md` and `docs/OPERATIONS.md`.
