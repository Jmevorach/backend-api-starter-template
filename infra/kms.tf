# =============================================================================
# KMS Key Management
# =============================================================================
# This file defines customer-managed KMS keys for encryption at rest:
# - Logs key: CloudTrail, CloudWatch Logs, S3 log bucket
# - Database key: Aurora data, Performance Insights, backups
# - Secrets key: Secrets Manager secrets
#
# Why separate keys?
# - Different retention requirements (logs vs secrets)
# - Different access patterns (services vs applications)
# - Easier key rotation and audit
# =============================================================================

# -----------------------------------------------------------------------------
# Logs KMS Key
# -----------------------------------------------------------------------------
# Used for encrypting:
# - CloudTrail logs in S3
# - CloudWatch Log Groups (VPC flow logs, ECS logs)
# - S3 bucket objects
#
# The key policy grants access to CloudTrail and CloudWatch Logs services.

data "aws_iam_policy_document" "kms_logs" {
  # Root account has full access for key management
  # This is required - without it, the key becomes unmanageable
  statement {
    sid = "EnableRootAccountPermissions"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"] # Required for key policies
  }

  # Allow CloudTrail to encrypt log files
  statement {
    sid = "AllowCloudTrailEncrypt"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    # Only allow encryption in CloudTrail context
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"]
    }
  }

  # Allow CloudTrail to describe the key (for validation)
  statement {
    sid = "AllowCloudTrailDescribe"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  # Allow CloudWatch Logs to encrypt/decrypt log data
  statement {
    sid = "AllowCloudWatchLogs"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.id}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]

    # Only allow operations from CloudWatch Logs in this account
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudTrail and log bucket encryption"
  enable_key_rotation     = true # Automatic annual key rotation
  deletion_window_in_days = 30   # 30-day waiting period before deletion
  policy                  = data.aws_iam_policy_document.kms_logs.json

  tags = local.tags
}

# Human-readable alias for the logs key
resource "aws_kms_alias" "logs" {
  name          = "alias/${local.name_prefix}-${random_string.name_suffix.result}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

# -----------------------------------------------------------------------------
# Database KMS Key
# -----------------------------------------------------------------------------
# Used for encrypting:
# - Aurora cluster data at rest
# - Aurora Performance Insights data
# - AWS Backup snapshots
#
# Uses default key policy (account root has full access via IAM)

resource "aws_kms_key" "db" {
  description             = "KMS key for Aurora and AWS Backup"
  enable_key_rotation     = true # Automatic annual key rotation
  deletion_window_in_days = 30   # 30-day waiting period before deletion

  tags = local.tags
}

resource "aws_kms_alias" "db" {
  name          = "alias/${local.name_prefix}-${random_string.name_suffix.result}-db"
  target_key_id = aws_kms_key.db.key_id
}

# -----------------------------------------------------------------------------
# Secrets KMS Key
# -----------------------------------------------------------------------------
# Used for encrypting:
# - Secrets Manager secrets (database passwords, API keys, etc.)
#
# Uses default key policy (account root has full access via IAM)

resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager"
  enable_key_rotation     = true # Automatic annual key rotation
  deletion_window_in_days = 30   # 30-day waiting period before deletion

  tags = local.tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-${random_string.name_suffix.result}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# -----------------------------------------------------------------------------
# Uploads KMS Key
# -----------------------------------------------------------------------------
# Used for encrypting:
# - S3 uploads bucket (user-uploaded files)
#
# Uses default key policy (account root has full access via IAM)

resource "aws_kms_key" "uploads" {
  description             = "KMS key for S3 uploads bucket"
  enable_key_rotation     = true # Automatic annual key rotation
  deletion_window_in_days = 30   # 30-day waiting period before deletion

  tags = local.tags
}

resource "aws_kms_alias" "uploads" {
  name          = "alias/${local.name_prefix}-${random_string.name_suffix.result}-uploads"
  target_key_id = aws_kms_key.uploads.key_id
}
