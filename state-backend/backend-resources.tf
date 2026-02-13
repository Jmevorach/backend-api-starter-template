# =============================================================================
# KMS Key for State Backend Encryption
# =============================================================================

resource "aws_kms_key" "state_backend" {
  description             = "KMS key for ${local.name_prefix} Terraform state backend encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tf-state-key"
  })
}

# KMS key policy - grants account root full access and allows key administration
# Note: In KMS key policies, "Resource": "*" refers to the key itself (self-referential)
# This is the standard pattern recommended by AWS for key policies
data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid = "EnableRootAccountAccess"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_kms_alias" "state_backend" {
  name          = "alias/${local.name_prefix}-tf-state"
  target_key_id = aws_kms_key.state_backend.key_id
}

# =============================================================================
# S3 Access Logging Bucket
# =============================================================================
# Note: Access logging is intentionally not enabled on the logging bucket itself
# to avoid circular dependencies. This is a standard pattern for S3 log buckets.

#checkov:skip=CKV_AWS_18:Access logging bucket cannot log to itself
#checkov:skip=CKV2_AWS_62:Event notifications not needed for logging bucket
#checkov:skip=CKV_AWS_144:Cross-region replication adds cost/complexity not justified for state logs
resource "aws_s3_bucket" "access_logs" {
  bucket = "${local.name_prefix}-tf-state-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tf-state-logs"
  })
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state_backend.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "access_logs_bucket" {
  statement {
    sid = "DenyInsecureTransport"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"

      values = ["false"]
    }

    effect = "Deny"
  }

  # Allow S3 logging service to write logs
  statement {
    sid = "AllowS3LogDelivery"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.access_logs.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.terraform_state.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs_bucket.json
}

# =============================================================================
# Terraform State Bucket
# =============================================================================

#checkov:skip=CKV2_AWS_62:Event notifications not needed for state bucket
#checkov:skip=CKV_AWS_144:Cross-region replication adds cost/complexity - state is versioned and backed up
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${local.name_prefix}-tf-state-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tf-state"
  })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state_backend.arn
    }
  }
}

resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "state-bucket-logs/"
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for state bucket - keeps current versions indefinitely
# but cleans up old versions and incomplete uploads
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    # Keep old versions for 90 days for recovery purposes
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "terraform_state_bucket" {
  statement {
    sid = "DenyInsecureTransport"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"

      values = ["false"]
    }

    effect = "Deny"
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state_bucket.json
}

# =============================================================================
# DynamoDB Table for State Locking (Legacy - kept for compatibility)
# =============================================================================
# Note: Terraform 1.10+ supports native S3 locking via use_lockfile = true
# This table is kept for backward compatibility with older configurations.

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${local.name_prefix}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state_backend.arn
  }

  deletion_protection_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tf-locks"
  })
}


