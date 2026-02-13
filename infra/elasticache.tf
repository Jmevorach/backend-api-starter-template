# =============================================================================
# ElastiCache Serverless Configuration
# =============================================================================
# This file defines the ElastiCache Serverless (Valkey) infrastructure:
# - Serverless cache for session storage
# - Security groups for network access
# - Auth token managed in Secrets Manager with automatic rotation
#
# ElastiCache Serverless automatically scales capacity based on demand.
# =============================================================================

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
# Controls what can connect to the ElastiCache cluster.
# Only ECS tasks should have access.

resource "aws_security_group" "elasticache" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-elasticache-sg"
  description = "Security group for ElastiCache Serverless - allows connections from ECS service"
  vpc_id      = aws_vpc.main.id

  tags = local.tags
}

# Allow traffic from ECS tasks
resource "aws_vpc_security_group_ingress_rule" "elasticache_from_ecs" {
  security_group_id            = aws_security_group.elasticache.id
  description                  = "Redis/Valkey from ECS service"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_service.id

  tags = local.tags
}

# Allow TLS traffic (6380) from ECS tasks - some clients use this port for TLS
resource "aws_vpc_security_group_ingress_rule" "elasticache_tls_from_ecs" {
  security_group_id            = aws_security_group.elasticache.id
  description                  = "Redis/Valkey TLS from ECS service"
  from_port                    = 6380
  to_port                      = 6380
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_service.id

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ElastiCache Serverless
# -----------------------------------------------------------------------------
# Serverless Valkey cache for session storage.
# Automatically scales and manages capacity.

resource "aws_elasticache_serverless_cache" "app" {
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-cache"
  engine = "valkey"

  # Use a cache subnet group for proper VPC placement
  subnet_ids         = aws_subnet.private_db[*].id
  security_group_ids = [aws_security_group.elasticache.id]

  # Enable encryption
  kms_key_id = aws_kms_key.secrets.arn

  # Capacity configuration (ElastiCache Units)
  # Serverless automatically scales within these bounds
  cache_usage_limits {
    data_storage {
      minimum = 1  # 1 GB minimum
      maximum = 10 # 10 GB maximum
      unit    = "GB"
    }
    ecpu_per_second {
      minimum = 1000  # Minimum ECPU/s
      maximum = 10000 # Maximum ECPU/s
    }
  }

  # Snapshot configuration
  daily_snapshot_time      = "03:00"
  snapshot_retention_limit = 7

  # User group for AUTH (RBAC)
  user_group_id = aws_elasticache_user_group.app.user_group_id

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ElastiCache User and User Group (RBAC with IAM)
# -----------------------------------------------------------------------------
# ElastiCache Serverless uses Role-Based Access Control (RBAC).
# Both users use IAM authentication - no passwords to manage!
#
# Note: For IAM auth, user_id and user_name MUST be the same.
# Note: User IDs must be unique across your AWS account, not just this stack.
#
# This configuration uses a "create if not exists" pattern:
# - Check if users already exist in AWS
# - If they exist, use data sources to reference them
# - If they don't exist, create them as resources

locals {
  elasticache_default_user_id = "${local.name_prefix}-${random_string.name_suffix.result}-dflt"
  elasticache_app_user_id     = "${local.name_prefix}-${random_string.name_suffix.result}-app"
}

# Check if ElastiCache users already exist
data "external" "elasticache_user_default_exists" {
  program = ["bash", "-c", <<-EOF
    if aws elasticache describe-users --user-id "${local.elasticache_default_user_id}" --query 'Users[0].UserId' --output text 2>/dev/null | grep -qE "^${local.elasticache_default_user_id}$"; then
      echo '{"exists": "true"}'
    else
      echo '{"exists": "false"}'
    fi
  EOF
  ]
}

data "external" "elasticache_user_app_exists" {
  program = ["bash", "-c", <<-EOF
    if aws elasticache describe-users --user-id "${local.elasticache_app_user_id}" --query 'Users[0].UserId' --output text 2>/dev/null | grep -qE "^${local.elasticache_app_user_id}$"; then
      echo '{"exists": "true"}'
    else
      echo '{"exists": "false"}'
    fi
  EOF
  ]
}

# Data sources to reference existing users (if they exist)
data "aws_elasticache_user" "default_existing" {
  count   = data.external.elasticache_user_default_exists.result.exists == "true" ? 1 : 0
  user_id = local.elasticache_default_user_id
}

data "aws_elasticache_user" "app_existing" {
  count   = data.external.elasticache_user_app_exists.result.exists == "true" ? 1 : 0
  user_id = local.elasticache_app_user_id
}

# Create users only if they don't exist
resource "aws_elasticache_user" "default" {
  count         = data.external.elasticache_user_default_exists.result.exists == "false" ? 1 : 0
  user_id       = local.elasticache_default_user_id
  user_name     = local.elasticache_default_user_id
  access_string = "off ~* -@all"
  engine        = "valkey"

  authentication_mode {
    type = "iam"
  }

  tags = local.tags
}

resource "aws_elasticache_user" "app" {
  count         = data.external.elasticache_user_app_exists.result.exists == "false" ? 1 : 0
  user_id       = local.elasticache_app_user_id
  user_name     = local.elasticache_app_user_id
  access_string = "on ~* +@all"
  engine        = "valkey"

  authentication_mode {
    type = "iam"
  }

  tags = local.tags
}

# Locals to get the final user IDs (whether from data source or resource)
locals {
  elasticache_default_user_final_id = (
    data.external.elasticache_user_default_exists.result.exists == "true"
    ? data.aws_elasticache_user.default_existing[0].user_id
    : aws_elasticache_user.default[0].user_id
  )
  elasticache_app_user_final_id = (
    data.external.elasticache_user_app_exists.result.exists == "true"
    ? data.aws_elasticache_user.app_existing[0].user_id
    : aws_elasticache_user.app[0].user_id
  )
}

# User group containing both users
resource "aws_elasticache_user_group" "app" {
  engine        = "valkey"
  user_group_id = "${local.name_prefix}-${random_string.name_suffix.result}-users"
  user_ids      = [local.elasticache_default_user_final_id, local.elasticache_app_user_final_id]

  tags = local.tags
}
