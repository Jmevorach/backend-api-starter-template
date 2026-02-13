# =============================================================================
# Logging and Audit Configuration
# =============================================================================
# This file configures centralized logging infrastructure:
# - S3 bucket for log storage (ALB, CloudTrail, Global Accelerator)
# - CloudWatch Log Groups for application and VPC logs
# - CloudTrail for AWS API audit logging
#
# Log Retention:
# - CloudWatch Logs: 365 days (1 year)
# - S3 objects: 730 days (2 years) then deleted
# - Old S3 versions: 90 days then deleted
#
# Cost Optimization:
# - Intelligent-Tiering after 30 days
# - Lifecycle rules to expire old data
# =============================================================================

# -----------------------------------------------------------------------------
# S3 Logs Bucket
# -----------------------------------------------------------------------------
# Central storage for all infrastructure logs.
# Protected with versioning, encryption, and public access blocks.

resource "aws_s3_bucket" "logs" {
  bucket = "${local.name_prefix}-${random_string.name_suffix.result}-logs-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion of audit logs
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-logs"
  })
}

# Block all public access - logs should never be public
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt all objects with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.logs.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Enable versioning for audit trail and accidental deletion protection
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# S3 Lifecycle Rules
# -----------------------------------------------------------------------------
# Manage storage costs and retention requirements.

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  # Move infrequently accessed logs to cheaper storage
  rule {
    id     = "transition-to-intelligent-tiering"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  # Clean up old versions (from overwrites/deletes)
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Clean up incomplete multipart uploads
  rule {
    id     = "expire-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Delete logs after 2 years (adjust based on compliance requirements)
  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 730 # 2 years
    }

    filter {
      prefix = ""
    }
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Policy
# -----------------------------------------------------------------------------
# Grants necessary permissions for AWS services to write logs.

data "aws_iam_policy_document" "logs_bucket" {
  # Deny any non-HTTPS access
  statement {
    sid = "AllowSSLRequestsOnly"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"

      values = ["false"]
    }

    effect = "Deny"
  }

  # Allow ALB to write access logs
  # Uses aws_elb_service_account for older regions (pre-August 2022)
  statement {
    sid = "AllowELBLogDeliveryAccount"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }

  # Allow ALB to write access logs via service principal (newer regions post-August 2022)
  statement {
    sid = "AllowELBLogDeliveryService"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }

  # Allow Global Accelerator to write flow logs
  statement {
    sid = "AllowGlobalAcceleratorLogging"

    principals {
      type        = "Service"
      identifiers = ["globalaccelerator.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = ["${aws_s3_bucket.logs.arn}/global-accelerator/*"]
  }

  # Allow CloudTrail to write audit logs
  statement {
    sid = "AllowCloudTrailLogging"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for ECS Application
# -----------------------------------------------------------------------------
# Stores application logs from the Phoenix container.
# ECS tasks write here via the awslogs driver.

resource "aws_cloudwatch_log_group" "ecs_app" {
  name              = "/ecs/${local.name_prefix}-${random_string.name_suffix.result}"
  retention_in_days = 365 # 1 year retention

  # Encrypt logs at rest
  kms_key_id = aws_kms_key.logs.arn

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudTrail
# -----------------------------------------------------------------------------
# Audit trail for all AWS API calls across all regions.
# Essential for security monitoring and compliance.

resource "aws_cloudtrail" "main" {
  name                          = "${local.name_prefix}-${random_string.name_suffix.result}-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  kms_key_id                    = aws_kms_key.logs.arn
  include_global_service_events = true  # Include IAM, CloudFront, etc.
  is_multi_region_trail         = true  # Capture events from all regions
  enable_log_file_validation    = true  # Detect log tampering
  is_organization_trail         = false # Single account trail

  tags = local.tags
}
