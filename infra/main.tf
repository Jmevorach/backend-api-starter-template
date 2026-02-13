# =============================================================================
# Main Terraform Configuration
# =============================================================================
# This file defines the Terraform settings, providers, and shared resources
# used across the entire infrastructure deployment.
#
# Architecture Overview:
# - VPC with public/private subnets across 2 AZs
# - ECS Fargate for containerized Phoenix application
# - Aurora PostgreSQL Serverless v2 with RDS Proxy
# - Global Accelerator for low-latency global traffic routing
# - S3 for logging and CloudTrail for audit trails
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Allow latest 5.x and 6.x without forcing a lock-step upgrade.
      # This provides flexibility while avoiding breaking changes in major versions.
      version = ">= 5.0, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0, < 4.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0, < 3.0"
    }
  }

  # Remote state backend using S3 for state storage with native S3 locking.
  # This enables team collaboration and prevents concurrent modifications.
  # The S3 bucket is created by the separate `state-backend/` Terraform configuration.
  backend "s3" {
    bucket       = "backend-infra-tf-state"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# AWS Provider Configuration
# The region is configurable via variables to support multi-region deployments.
provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
# These data sources fetch information about the current AWS account and region,
# which are used throughout the configuration for ARN construction and policies.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ELB service account for ALB access logging - automatically resolves the
# correct account ID for the current region
data "aws_elb_service_account" "current" {}

# -----------------------------------------------------------------------------
# Random Suffix for Resource Names
# -----------------------------------------------------------------------------
# A random 6-character suffix is appended to resource names to ensure uniqueness
# and prevent naming collisions during blue-green deployments or when running
# multiple environments in the same account.

resource "random_string" "name_suffix" {
  length  = 6
  upper   = false
  special = false
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------
# Common values used across all resources for consistent naming and tagging.

locals {
  # Standard prefix for all resource names: project-environment-suffix
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags applied to all taggable resources for cost allocation,
  # resource organization, and operational visibility.
  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# =============================================================================
# Infrastructure Components (defined in separate files)
# =============================================================================
# - acm.tf              : ACM certificate auto-creation and DNS validation
# - network.tf          : VPC, subnets, route tables, NAT gateway, flow logs
# - ecs.tf              : ECS cluster, service, task definition, ALB, auto-scaling
# - rds.tf              : Aurora PostgreSQL cluster, RDS Proxy, security groups
# - iam.tf              : IAM roles and policies for ECS, GitHub Actions OIDC
# - kms.tf              : KMS keys for encryption (logs, database, secrets)
# - logging.tf          : S3 bucket for logs, CloudTrail, CloudWatch log groups
# - secrets.tf          : Secrets Manager for database credentials
# - backup.tf           : AWS Backup plans for Aurora snapshots
# - global_accelerator.tf : Global Accelerator for worldwide traffic routing
# - ecr.tf              : ECR repository for container images
# - outputs.tf          : Exported values for use by other systems
# - variables.tf        : Input variable definitions
