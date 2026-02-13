# =============================================================================
# ECR Repository Configuration
# =============================================================================
# This file defines the Elastic Container Registry repository for storing
# the Phoenix application Docker images.
#
# Note: The ECR repository is created by the deploy script BEFORE terraform
# runs (to allow image push). Terraform just references it via data source.
#
# Lifecycle Policy:
# - Keeps last 30 tagged release images
# - Removes untagged images after 7 days
# =============================================================================

# Reference the ECR repository created by deploy script
data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

locals {
  ecr_repository_name = data.aws_ecr_repository.app.name
  ecr_repository_url  = data.aws_ecr_repository.app.repository_url
  ecr_repository_arn  = data.aws_ecr_repository.app.arn
}

# -----------------------------------------------------------------------------
# Lifecycle Policy
# -----------------------------------------------------------------------------
# Automatically clean up old images to reduce storage costs and clutter.

resource "aws_ecr_lifecycle_policy" "app" {
  repository = local.ecr_repository_name

  policy = jsonencode({
    rules = [
      {
        # Rule 1: Keep last 30 release images
        # Matches images tagged with v*, release*, prod*, staging*
        rulePriority = 1
        description  = "Keep last 30 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "prod", "staging"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      },
      {
        # Rule 2: Clean up untagged images (build artifacts)
        # These are typically intermediate layers or failed builds
        rulePriority = 2
        description  = "Remove untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
