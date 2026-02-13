## Environment Variables and Configuration

This file is the **single place** to see every environment variable, Terraform
input, and GitHub Actions setting used by the project.

### Table of Contents

- [Application Runtime (ECS Task)](#application-runtime-ecs-task)
- [Test/CI Runtime (Phoenix)](#testci-runtime-phoenix)
- [Terraform Inputs (infra)](#terraform-inputs-infra)
- [Terraform Inputs (state-backend)](#terraform-inputs-state-backend)
- [Local Deployment (Laptop)](#local-deployment-laptop)
- [Python Version Note](#python-version-note)

### Application Runtime (ECS Task)

These are environment variables the Phoenix app expects at runtime.

| Name | Required | Purpose |
|------|----------|---------|
| `SECRET_KEY_BASE` | Yes | Phoenix secret for signing/encrypting cookies and sessions. |
| `PHX_HOST` | No | Public hostname used in URL generation. |
| `PORT` | No | HTTPS port inside the container (default `443`). |
| `DB_HOST` | Yes | Database hostname (RDS Proxy endpoint). |
| `DB_NAME` | Yes | Database name. |
| `DB_USERNAME` | Yes | Database username. |
| `DB_PASSWORD` | No | Database password (optional fallback when IAM auth disabled). |
| `DB_IAM_AUTH` | No | Enable database IAM authentication (`true/false`). |
| `DB_POOL_SIZE` | No | Ecto pool size (default `10`). |
| `AWS_REGION` | No | AWS region for IAM token generation (default `us-east-1`). |
| `REQUIRE_IAM_AUTH` | No | When `true`, disables password fallback for DB and Valkey (production security). |
| `SSL_KEYFILE` | No | TLS key path inside the container. |
| `SSL_CERTFILE` | No | TLS cert path inside the container. |
| `VALKEY_HOST` | No | Valkey/Redis hostname. |
| `VALKEY_PORT` | No | Valkey/Redis port (default `6379`). |
| `VALKEY_USER` | No | Valkey/Redis username for RBAC (default `app_user`). |
| `VALKEY_PASSWORD` | No | Valkey/Redis password (optional fallback when IAM auth disabled). |
| `VALKEY_IAM_AUTH` | No | Enable Valkey IAM authentication (`true/false`). |
| `VALKEY_CLUSTER_ID` | No | ElastiCache cluster ID (required for IAM auth). |
| `VALKEY_SSL` | No | Enable SSL for Valkey connection (default `true`, set to `false` for local). |
| `ENABLE_SECRET_RELOAD` | No | Enable periodic secret reloading (`true/false`). |
| `AUTH_SUCCESS_REDIRECT` | No | Redirect URL after successful OAuth login. |
| `AUTH_FAILURE_REDIRECT` | No | Redirect URL after OAuth failure. |
| `AUTH_LOGOUT_REDIRECT` | No | Redirect URL after logout. |
| `GOOGLE_CLIENT_ID` | No | Google OAuth client ID. |
| `GOOGLE_CLIENT_SECRET` | No | Google OAuth client secret. |
| `APPLE_CLIENT_ID` | No | Apple OAuth Services ID. |
| `APPLE_CLIENT_SECRET` | No | Apple OAuth client secret. |
| `APPLE_TEAM_ID` | No | Apple Developer Team ID. |
| `APPLE_KEY_ID` | No | Apple OAuth key ID. |
| `APPLE_PRIVATE_KEY` | No | Apple OAuth private key (P8). |
| `STRIPE_API_KEY` | No | Stripe API secret key for payment processing. |
| `CHECKR_API_KEY` | No | Checkr API key for background checks. |
| `CHECKR_ENVIRONMENT` | No | Checkr environment: `sandbox` (default) or `production`. |
| `GOOGLE_MAPS_API_KEY` | No | Google Maps Platform API key for geocoding and places. |
| `UPLOADS_BUCKET` | No | S3 bucket name for file uploads. |
| `UPLOADS_REGION` | No | AWS region for uploads bucket (defaults to `AWS_REGION`). |
| `UPLOADS_MAX_SIZE_MB` | No | Maximum file size for uploads in MB (default `50`). |
| `UPLOADS_PRESIGNED_URL_EXPIRY` | No | Presigned URL expiration in seconds (default `3600`). |

### Test/CI Runtime (Phoenix)

| Name | Required | Purpose |
|------|----------|---------|
| `TEST_DB_HOST` | No | Test database host (default `localhost`). |
| `TEST_DB_USERNAME` | No | Test database user (default `postgres`). |
| `TEST_DB_PASSWORD` | No | Test database password (default `postgres`). |
| `TEST_DB_NAME` | No | Test database name (default `backend_test`). |

### Terraform Inputs (infra)

Use `terraform.tfvars` or `TF_VAR_*` environment variables.

| Variable | Required | Purpose |
|----------|----------|---------|
| `project_name` | No | Resource name prefix (default `phoenix-backend`). |
| `environment` | No | Environment name (`prod`, `staging`, etc.). |
| `aws_region` | No | AWS region (default `us-east-1`). |
| `lambda_python_runtime` | No | Lambda runtime (default `python3.14`). |
| `additional_tags` | No | Extra tags applied to resources. |
| `container_image` | Yes | ECR image URI for the app. |
| `service_desired_count` | No | Desired ECS task count. |
| `ecs_min_capacity` | No | ECS auto scaling minimum. |
| `ecs_max_capacity` | No | ECS auto scaling maximum. |
| `ecs_cpu_target_utilization` | No | Target CPU for scaling. |
| `domain_name` | No* | Domain for auto-certificate creation (e.g., `api.example.com`). |
| `route53_zone_name` | No* | Route 53 zone name for DNS validation (e.g., `example.com`). |
| `alb_acm_certificate_arn` | No* | ACM cert ARN (only if not using auto-creation). |
| `ecr_repository_name` | No | ECR repository name (default `backend-service`). |

> **\*Certificate Note**: You must provide EITHER `domain_name` + `route53_zone_name` for automatic certificate creation, OR `alb_acm_certificate_arn` for an existing certificate.
| `aurora_min_capacity` | No | Aurora Serverless v2 min ACUs. |
| `aurora_max_capacity` | No | Aurora Serverless v2 max ACUs. |
| `github_owner` | Yes | GitHub org/user for OIDC. |
| `github_repo` | Yes | GitHub repo name for OIDC. |
| `github_oidc_thumbprints` | No | GitHub OIDC thumbprints. |
| `google_oauth_client_id_secret_arn` | No | Secrets Manager ARN (Google client ID). |
| `google_oauth_client_secret_secret_arn` | No | Secrets Manager ARN (Google client secret). |
| `apple_oauth_client_id_secret_arn` | No | Secrets Manager ARN (Apple client ID). |
| `apple_oauth_client_secret_secret_arn` | No | Secrets Manager ARN (Apple client secret). |
| `apple_oauth_team_id_secret_arn` | No | Secrets Manager ARN (Apple team ID). |
| `apple_oauth_key_id_secret_arn` | No | Secrets Manager ARN (Apple key ID). |
| `apple_oauth_private_key_secret_arn` | No | Secrets Manager ARN (Apple private key). |
| `stripe_api_key_secret_arn` | No | Secrets Manager ARN (Stripe API key). |
| `checkr_api_key_secret_arn` | No | Secrets Manager ARN (Checkr API key). |
| `google_maps_api_key_secret_arn` | No | Secrets Manager ARN (Google Maps API key). |
| `db_password_secret_arn` | No | Secrets Manager ARN (database password fallback). |
| `valkey_password_secret_arn` | No | Secrets Manager ARN (Valkey password fallback). |
| `require_iam_auth` | No | Disable password fallback in production (default `true`). |
| `uploads_cors_origins` | No | Allowed CORS origins for uploads bucket (default `["*"]`). |
| `uploads_enable_cloudfront` | No | Enable CloudFront CDN for uploads (default `false`). |
| `uploads_enable_intelligent_tiering` | No | Enable S3 Intelligent-Tiering for cost optimization (default `false`). |
| `uploads_max_file_size_mb` | No | Maximum file size for uploads in MB (default `50`). |
| `uploads_presigned_url_expiry_seconds` | No | Presigned URL expiration in seconds (default `3600`). |

### Terraform Inputs (state-backend)

| Variable | Required | Purpose |
|----------|----------|---------|
| `project_name` | No | State backend resource prefix (default `backend-infra`). |
| `environment` | No | Environment name. |
| `aws_region` | No | AWS region for state backend. |

### Local Deployment (Laptop)

These are used by `scripts/deploy.sh` and `scripts/deploy-local.sh`.

| Name | Required | Purpose |
|------|----------|---------|
| `AWS_REGION` | No | AWS region (default `us-east-1`). |
| `ENVIRONMENT` | No | Environment name (default `prod`). |
| `ECR_REPOSITORY` | No | ECR repository name (default `backend-service`). |
| `IMAGE_TAG` | No | Image tag to publish (default git SHA). |
| `PLATFORM` | No | Container platform for build (default `linux/arm64`). |
| `CONTAINER_RUNTIME` | No | Container runtime: `docker`, `finch`, or `podman` (auto-detected). |
| `TF_VAR_github_owner` | Yes | GitHub org/user (required Terraform input). |
| `TF_VAR_github_repo` | Yes | GitHub repo name (required Terraform input). |
| `TF_VAR_alb_acm_certificate_arn` | Yes | ACM certificate ARN for ALB HTTPS. |

### Python Version Note

GitHub Actions uses Python **3.14** for Lambda checks. AWS Lambda supports
**python3.14** for these rotation functions; keep `lambda_python_runtime`
aligned with your target runtime.
