# =============================================================================
# Secrets Manager Configuration
# =============================================================================
# This file manages sensitive credentials stored in AWS Secrets Manager.
#
# IAM Authentication:
# - Database: Uses IAM auth via RDS Proxy (no password needed)
# - ElastiCache: Uses IAM auth (no password needed)
#
# Only SECRET_KEY_BASE is stored here - everything else uses IAM!
#
# Note: OAuth credentials (Google, Apple) are stored externally and
# referenced via ARN variables to allow separate lifecycle management.
# =============================================================================

# -----------------------------------------------------------------------------
# Phoenix SECRET_KEY_BASE
# -----------------------------------------------------------------------------
# Used by Phoenix for signing/encrypting cookies and session data.
# Must be at least 64 characters for security.
# This secret is injected into the ECS container at runtime.

resource "random_password" "secret_key_base" {
  length           = 64 # Phoenix requires minimum 64 chars
  special          = true
  override_special = "_%@"
}

resource "aws_secretsmanager_secret" "secret_key_base" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-secret-key-base"
  description = "Phoenix SECRET_KEY_BASE for backend service"
  kms_key_id  = aws_kms_key.secrets.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "secret_key_base" {
  secret_id     = aws_secretsmanager_secret.secret_key_base.id
  secret_string = random_password.secret_key_base.result
}
