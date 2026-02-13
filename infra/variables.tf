# =============================================================================
# Input Variables
# =============================================================================
# This file defines all configurable parameters for the infrastructure.
# Variables are organized by category:
# - Project Configuration
# - Compute (ECS)
# - Database (Aurora)
# - Networking (ACM, ECR)
# - External Services (Valkey, OAuth)
# - CI/CD (GitHub OIDC)
# =============================================================================

# -----------------------------------------------------------------------------
# Project Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Logical name for this project (used as prefix for most resources)."
  type        = string
  default     = "phoenix-backend"
}

variable "environment" {
  description = "Environment name (e.g. prod, staging). Used in resource naming and tagging."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "lambda_python_runtime" {
  description = "Python runtime for rotation Lambdas. Must be a supported AWS Lambda runtime."
  type        = string
  default     = "python3.14"
}

variable "additional_tags" {
  description = "Additional tags to apply to all taggable resources."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# ECS Compute Configuration
# -----------------------------------------------------------------------------

variable "container_image" {
  description = "ECR image URI (including tag) for the Phoenix backend service. Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/backend-service:v1.0.0"
  type        = string
}

variable "service_desired_count" {
  description = "Desired number of ECS tasks for the service. Auto-scaling may adjust this."
  type        = number
  default     = 2
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks for auto scaling. Set to 0 for cost savings in dev."
  type        = number
  default     = 1

  validation {
    condition     = var.ecs_min_capacity >= 0
    error_message = "ECS minimum capacity must be non-negative."
  }
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks for auto scaling. Limits cost and resource usage."
  type        = number
  default     = 4

  validation {
    condition     = var.ecs_max_capacity >= 1
    error_message = "ECS maximum capacity must be at least 1."
  }
}

variable "ecs_cpu_target_utilization" {
  description = "Target average CPU utilization percentage for ECS service auto scaling. Lower values scale out sooner."
  type        = number
  default     = 60

  validation {
    condition     = var.ecs_cpu_target_utilization > 0 && var.ecs_cpu_target_utilization <= 100
    error_message = "ECS CPU target utilization must be between 1 and 100 percent."
  }
}

variable "ecs_cpu_architecture" {
  description = "CPU architecture for ECS tasks. Options: X86_64 (Intel/AMD) or ARM64 (Graviton). ARM64 typically offers better price/performance."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.ecs_cpu_architecture)
    error_message = "ECS CPU architecture must be either X86_64 or ARM64."
  }
}

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Domain name for the application (e.g., api.example.com). If provided with route53_zone_name, an ACM certificate will be created automatically."
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Route 53 hosted zone name (e.g., example.com). The zone will be looked up by name. Required if domain_name is provided for auto-certificate creation."
  type        = string
  default     = ""
}

variable "alb_acm_certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. Only required if domain_name is not provided."
  type        = string
  default     = ""
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository that will store the Phoenix app image."
  type        = string
  default     = "backend-service"
}

# -----------------------------------------------------------------------------
# Aurora Database Configuration
# -----------------------------------------------------------------------------

variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs. 1 ACU = 2 GB RAM. Minimum 0.5 ACU."
  type        = number
  default     = 0.5

  validation {
    condition     = var.aurora_min_capacity >= 0.5
    error_message = "Aurora Serverless v2 minimum capacity must be at least 0.5 ACU."
  }
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs. Controls cost ceiling. Max 128 ACU."
  type        = number
  default     = 4

  validation {
    condition     = var.aurora_max_capacity >= 0.5 && var.aurora_max_capacity <= 128
    error_message = "Aurora Serverless v2 maximum capacity must be between 0.5 and 128 ACUs."
  }
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC Configuration
# -----------------------------------------------------------------------------
# These variables configure the trust relationship between GitHub Actions and AWS.

variable "github_owner" {
  description = "GitHub organization or user that owns the repository (for OIDC conditions)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without owner) for which OIDC access is granted."
  type        = string
}

variable "github_oidc_thumbprints" {
  description = "Thumbprints for the GitHub Actions OIDC provider certificates. Include primary and backup."
  type        = list(string)
  default = [
    # Primary GitHub Actions OIDC certificate thumbprint
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    # Backup certificate thumbprint (for resilience during rotation)
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# -----------------------------------------------------------------------------
# OAuth Configuration (Optional)
# -----------------------------------------------------------------------------
# OAuth credentials are stored in Secrets Manager and injected at runtime.
# Leave empty to disable the corresponding OAuth provider.

# Google OAuth
variable "google_oauth_client_id_secret_arn" {
  description = "Secrets Manager ARN for Google OAuth client ID. Leave empty to disable Google login."
  type        = string
  default     = ""
}

variable "google_oauth_client_secret_secret_arn" {
  description = "Secrets Manager ARN for Google OAuth client secret."
  type        = string
  default     = ""
}

# Apple OAuth (Sign in with Apple)
variable "apple_oauth_client_id_secret_arn" {
  description = "Secrets Manager ARN for Apple OAuth client ID (Services ID). Leave empty to disable Apple login."
  type        = string
  default     = ""
}

variable "apple_oauth_client_secret_secret_arn" {
  description = "Secrets Manager ARN for Apple OAuth client secret."
  type        = string
  default     = ""
}

variable "apple_oauth_team_id_secret_arn" {
  description = "Secrets Manager ARN for Apple Developer Team ID."
  type        = string
  default     = ""
}

variable "apple_oauth_key_id_secret_arn" {
  description = "Secrets Manager ARN for Apple OAuth key ID."
  type        = string
  default     = ""
}

variable "apple_oauth_private_key_secret_arn" {
  description = "Secrets Manager ARN for Apple OAuth private key (P8 format)."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Database/Cache Password Authentication (Optional)
# -----------------------------------------------------------------------------
# Password secrets for non-IAM environments or fallback authentication.
# IAM authentication is preferred in production.

variable "db_password_secret_arn" {
  description = "Secrets Manager ARN for database password. Optional fallback when IAM auth is disabled."
  type        = string
  default     = ""
}

variable "valkey_password_secret_arn" {
  description = "Secrets Manager ARN for Valkey/Redis password. Optional fallback when IAM auth is disabled."
  type        = string
  default     = ""
}

variable "require_iam_auth" {
  description = "When true, disables password authentication fallback. Set to true in production for maximum security."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# S3 Uploads Configuration
# -----------------------------------------------------------------------------
# Configuration for user file uploads (images, documents, etc.)

variable "uploads_cors_origins" {
  description = "List of allowed origins for CORS on the uploads bucket. Use ['*'] for development, specific domains for production."
  type        = list(string)
  default     = ["*"]
}

variable "uploads_enable_cloudfront" {
  description = "Enable CloudFront CDN for serving uploaded files. Improves download performance globally."
  type        = bool
  default     = false
}

variable "uploads_enable_intelligent_tiering" {
  description = "Enable S3 Intelligent-Tiering for automatic cost optimization of infrequently accessed files."
  type        = bool
  default     = false
}

variable "uploads_max_file_size_mb" {
  description = "Maximum allowed file size for uploads in megabytes. Enforced by presigned URL policy."
  type        = number
  default     = 50

  validation {
    condition     = var.uploads_max_file_size_mb > 0 && var.uploads_max_file_size_mb <= 5000
    error_message = "Upload max file size must be between 1 and 5000 MB."
  }
}

variable "uploads_presigned_url_expiry_seconds" {
  description = "Expiration time for presigned upload URLs in seconds."
  type        = number
  default     = 3600 # 1 hour

  validation {
    condition     = var.uploads_presigned_url_expiry_seconds >= 60 && var.uploads_presigned_url_expiry_seconds <= 604800
    error_message = "Presigned URL expiry must be between 60 seconds and 7 days (604800 seconds)."
  }
}
