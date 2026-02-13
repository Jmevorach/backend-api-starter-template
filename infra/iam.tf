# =============================================================================
# IAM Roles and Policies
# =============================================================================
# This file defines IAM roles for:
# - ECS Task Execution: Pulling images, secrets for container startup
# - ECS Task: Runtime permissions for the application
# - AWS Backup: Taking Aurora snapshots
# - GitHub Actions: CI/CD deployment via OIDC federation
#
# Security Principles:
# - Least privilege: Each role has only the permissions it needs
# - Resource-scoped: Policies target specific resources where possible
# - No long-lived credentials: GitHub Actions uses OIDC, not access keys
# =============================================================================

# -----------------------------------------------------------------------------
# ECS Task Execution Role
# -----------------------------------------------------------------------------
# Used by the ECS agent to:
# - Pull container images from ECR
# - Retrieve secrets from Secrets Manager for container environment
# - Write logs to CloudWatch

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "ecs_task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Attach AWS managed policy for basic ECS task execution (ECR pull, CloudWatch logs)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional permissions to pull secrets from Secrets Manager at container startup
# These secrets are referenced in the ECS task definition's "secrets" block
data "aws_iam_policy_document" "ecs_task_execution_secrets" {
  # Allow fetching secret values
  # Note: Database and ElastiCache use IAM auth - no passwords to fetch!
  statement {
    sid     = "GetSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat(
      # Required secrets (only SECRET_KEY_BASE now)
      [aws_secretsmanager_secret.secret_key_base.arn],
      # Optional secrets (only if ARN is provided)
      var.google_oauth_client_id_secret_arn != "" ? [var.google_oauth_client_id_secret_arn] : [],
      var.google_oauth_client_secret_secret_arn != "" ? [var.google_oauth_client_secret_secret_arn] : [],
      var.apple_oauth_client_id_secret_arn != "" ? [var.apple_oauth_client_id_secret_arn] : [],
      var.apple_oauth_client_secret_secret_arn != "" ? [var.apple_oauth_client_secret_secret_arn] : [],
      var.apple_oauth_team_id_secret_arn != "" ? [var.apple_oauth_team_id_secret_arn] : [],
      var.apple_oauth_key_id_secret_arn != "" ? [var.apple_oauth_key_id_secret_arn] : [],
      var.apple_oauth_private_key_secret_arn != "" ? [var.apple_oauth_private_key_secret_arn] : [],
      # Third-party API keys
      var.stripe_api_key_secret_arn != "" ? [var.stripe_api_key_secret_arn] : [],
      var.checkr_api_key_secret_arn != "" ? [var.checkr_api_key_secret_arn] : [],
      var.google_maps_api_key_secret_arn != "" ? [var.google_maps_api_key_secret_arn] : [],
      # Database/Cache password fallback
      var.db_password_secret_arn != "" ? [var.db_password_secret_arn] : [],
      var.valkey_password_secret_arn != "" ? [var.valkey_password_secret_arn] : []
    )
  }

  # Allow decrypting secrets with our KMS key
  statement {
    sid       = "DecryptSecrets"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.secrets.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-ecs-exec-secrets"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_execution_secrets.json
}

# -----------------------------------------------------------------------------
# ECS Task Role
# -----------------------------------------------------------------------------
# Runtime permissions for the Phoenix application container.
# Used when the application makes AWS API calls.

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "ecs_task" {
  # Allow reading secrets at runtime
  statement {
    sid = "SecretsAccess"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = concat(
      [aws_secretsmanager_secret.secret_key_base.arn],
      var.google_oauth_client_id_secret_arn != "" ? [var.google_oauth_client_id_secret_arn] : [],
      var.google_oauth_client_secret_secret_arn != "" ? [var.google_oauth_client_secret_secret_arn] : [],
      var.apple_oauth_client_id_secret_arn != "" ? [var.apple_oauth_client_id_secret_arn] : [],
      var.apple_oauth_client_secret_secret_arn != "" ? [var.apple_oauth_client_secret_secret_arn] : [],
      var.apple_oauth_team_id_secret_arn != "" ? [var.apple_oauth_team_id_secret_arn] : [],
      var.apple_oauth_key_id_secret_arn != "" ? [var.apple_oauth_key_id_secret_arn] : [],
      var.apple_oauth_private_key_secret_arn != "" ? [var.apple_oauth_private_key_secret_arn] : [],
      # Third-party API keys
      var.stripe_api_key_secret_arn != "" ? [var.stripe_api_key_secret_arn] : [],
      var.checkr_api_key_secret_arn != "" ? [var.checkr_api_key_secret_arn] : [],
      var.google_maps_api_key_secret_arn != "" ? [var.google_maps_api_key_secret_arn] : [],
      # Database/Cache password fallback
      var.db_password_secret_arn != "" ? [var.db_password_secret_arn] : [],
      var.valkey_password_secret_arn != "" ? [var.valkey_password_secret_arn] : []
    )
  }

  # Allow decrypting secrets
  statement {
    sid = "DecryptSecrets"

    actions = ["kms:Decrypt"]

    resources = [aws_kms_key.secrets.arn]
  }

  # IAM authentication for RDS Proxy
  # Allows the application to generate authentication tokens for database connections
  statement {
    sid = "RDSProxyIAMAuth"

    actions = ["rds-db:connect"]

    resources = [
      "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_proxy.app.id}/${aws_rds_cluster.app.master_username}"
    ]
  }

  # IAM authentication for ElastiCache
  # Allows the application to connect to Valkey using IAM credentials
  statement {
    sid = "ElastiCacheIAMAuth"

    actions = ["elasticache:Connect"]

    resources = [
      aws_elasticache_serverless_cache.app.arn,
      "${aws_elasticache_serverless_cache.app.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "elasticache:userId"
      values   = [local.elasticache_app_user_final_id]
    }
  }

  # S3 uploads bucket access
  # Allows the application to generate presigned URLs and manage uploaded files
  statement {
    sid = "S3UploadsAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.uploads.arn,
      "${aws_s3_bucket.uploads.arn}/*"
    ]
  }

  # Allow encrypting/decrypting uploads with KMS
  statement {
    sid = "S3UploadsKMS"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]

    resources = [aws_kms_key.uploads.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_inline" {
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-ecs-task-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task.json
}

# -----------------------------------------------------------------------------
# AWS Backup Role
# -----------------------------------------------------------------------------
# Used by AWS Backup service to take and manage Aurora snapshots

resource "aws_iam_role" "backup" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "backup_managed" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC Provider
# -----------------------------------------------------------------------------
# Enables GitHub Actions to assume IAM roles without long-lived credentials.
# Uses OpenID Connect federation for secure, short-lived tokens.
#
# How it works:
# 1. GitHub Actions requests a JWT from GitHub's OIDC provider
# 2. AWS validates the JWT signature using the thumbprints below
# 3. AWS issues temporary credentials if the token claims match our conditions
#
# Note: The OIDC provider is account-wide and auto-detected. If it already
# exists (e.g., from another project), we reuse it; otherwise we create it.

# Auto-detect if GitHub OIDC provider already exists in this AWS account
data "external" "check_github_oidc" {
  program = ["bash", "-c", <<-EOF
    # Check if GitHub OIDC provider exists
    PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
      --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn | [0]" \
      --output text 2>/dev/null)

    if [ -n "$PROVIDER_ARN" ] && [ "$PROVIDER_ARN" != "None" ]; then
      echo "{\"exists\": \"true\", \"arn\": \"$PROVIDER_ARN\"}"
    else
      echo "{\"exists\": \"false\", \"arn\": \"\"}"
    fi
  EOF
  ]
}

locals {
  github_oidc_provider_exists = data.external.check_github_oidc.result.exists == "true"
}

# Create OIDC provider only if it doesn't already exist
resource "aws_iam_openid_connect_provider" "github" {
  count = local.github_oidc_provider_exists ? 0 : 1

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub Actions OIDC root certificate thumbprints.
  # These are used to verify the authenticity of tokens from GitHub.
  # Include both primary and backup thumbprints for resilience.
  thumbprint_list = var.github_oidc_thumbprints
}

locals {
  # Use existing provider ARN if found, otherwise use the newly created one
  github_oidc_provider_arn = local.github_oidc_provider_exists ? data.external.check_github_oidc.result.arn : aws_iam_openid_connect_provider.github[0].arn
}

# Trust policy: Only allow our specific GitHub repository to assume this role
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    # Verify the token is intended for AWS
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only allow tokens from our specific repository
    # The wildcard allows any branch/workflow in the repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(local.tags, { Component = "github-oidc" })
}

# -----------------------------------------------------------------------------
# GitHub Actions Permissions
# -----------------------------------------------------------------------------
# Scoped permissions for CI/CD workflows including:
# - Container image build and push to ECR
# - ECS service deployment
# - Terraform state management
# - Read-only access for terraform plan

data "aws_iam_policy_document" "github_actions_policy" {
  # --- ECR Permissions ---
  # Required for authenticating with ECR
  statement {
    sid = "ECRAuth"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"] # GetAuthorizationToken doesn't support resource-level permissions
  }

  # Push and pull images from our ECR repository
  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages"
    ]
    resources = [local.ecr_repository_arn]
  }

  # --- ECS Deployment Permissions ---
  # Update services and manage task definitions
  statement {
    sid = "ECSDeployment"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeClusters",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:ListServices"
    ]
    resources = ["*"]

    # Only allow operations on resources tagged with our project
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
  }

  # Task definition registration requires separate statement (not resource-taggable at creation)
  statement {
    sid = "ECSTaskDefinition"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:DeregisterTaskDefinition"
    ]
    resources = ["*"]
  }

  # Allow ECS to assume the task roles during deployment
  statement {
    sid = "IAMPassRole"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.ecs_task_execution.arn,
      aws_iam_role.ecs_task.arn
    ]
  }

  # --- CloudWatch Logs ---
  # View deployment logs for debugging
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:GetLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups"
    ]
    resources = [
      "${aws_cloudwatch_log_group.ecs_app.arn}:*"
    ]
  }

  # --- Terraform State Management ---
  # Read/write state file in S3
  statement {
    sid = "TerraformStateS3"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::backend-infra-tf-state",
      "arn:aws:s3:::backend-infra-tf-state/*"
    ]
  }

  # State locking via DynamoDB
  statement {
    sid = "TerraformStateLocking"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/backend-infra-tf-locks"
    ]
  }

  # --- Read-Only Permissions for Terraform Plan ---
  # Allows terraform plan to read current infrastructure state
  statement {
    sid = "TerraformPlanReadOnly"
    actions = [
      # VPC and networking
      "ec2:Describe*",
      "elasticloadbalancing:Describe*",
      # Database
      "rds:Describe*",
      # Monitoring
      "cloudwatch:Describe*",
      "cloudwatch:GetMetricData",
      "logs:Describe*",
      # IAM (read-only)
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      # Secrets (metadata only, not values)
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      # KMS
      "kms:DescribeKey",
      "kms:ListAliases",
      # Global Accelerator
      "globalaccelerator:Describe*",
      "globalaccelerator:List*",
      # S3
      "s3:GetBucketPolicy",
      "s3:GetBucketVersioning",
      "s3:GetBucketEncryption",
      "s3:GetBucketPublicAccessBlock",
      "s3:ListBucket",
      # Backup
      "backup:DescribeBackupVault",
      "backup:GetBackupPlan",
      "backup:ListBackupPlans"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_inline" {
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_policy.json
}
