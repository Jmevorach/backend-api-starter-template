# =============================================================================
# AWS Backup Configuration
# =============================================================================
# This file configures automated backups for the Aurora database using AWS Backup.
#
# Backup Strategy:
# - Weekly backups: Every Sunday at 5 AM UTC, retained 30 days
# - Monthly backups: 1st of each month at 6 AM UTC, retained 1 year
# - Yearly backups: January 1st at 7 AM UTC, retained 7 years
#
# Note: This is in addition to Aurora's native automated backups (7-day retention).
# AWS Backup provides:
# - Cross-region copy capability (if needed)
# - Centralized backup management
# - Compliance reporting
# =============================================================================

# -----------------------------------------------------------------------------
# Backup Vault
# -----------------------------------------------------------------------------
# Encrypted storage location for backup recovery points.
# Uses the database KMS key for encryption.

resource "aws_backup_vault" "aurora" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-backup-vault"
  kms_key_arn = aws_kms_key.db.arn

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Backup Plan
# -----------------------------------------------------------------------------
# Defines the backup schedule and retention policies.

resource "aws_backup_plan" "aurora" {
  name = "${local.name_prefix}-${random_string.name_suffix.result}-aurora-backup-plan"

  # Weekly backup - good for recent point-in-time recovery
  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.aurora.name
    schedule          = "cron(0 5 ? * SUN *)" # Every Sunday at 5 AM UTC

    lifecycle {
      delete_after = 30 # Keep for 30 days
    }
  }

  # Monthly backup - good for monthly restore points
  rule {
    rule_name         = "monthly-backup"
    target_vault_name = aws_backup_vault.aurora.name
    schedule          = "cron(0 6 1 * ? *)" # 1st of each month at 6 AM UTC

    lifecycle {
      delete_after = 365 # Keep for 1 year
    }
  }

  # Yearly backup - good for compliance/audit requirements
  rule {
    rule_name         = "yearly-backup"
    target_vault_name = aws_backup_vault.aurora.name
    schedule          = "cron(0 7 1 1 ? *)" # January 1st at 7 AM UTC

    lifecycle {
      delete_after = 2555 # Keep for ~7 years (2555 days)
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Backup Selection
# -----------------------------------------------------------------------------
# Defines which resources are backed up by this plan.

resource "aws_backup_selection" "aurora" {
  name         = "${local.name_prefix}-${random_string.name_suffix.result}-aurora-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.aurora.id

  # Back up the Aurora cluster
  resources = [
    aws_rds_cluster.app.arn
  ]
}
