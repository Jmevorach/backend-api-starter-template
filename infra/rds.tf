# =============================================================================
# Aurora PostgreSQL Database Configuration
# =============================================================================
# This file configures the database infrastructure:
# - Aurora PostgreSQL Serverless v2 cluster (auto-scaling capacity)
# - RDS Proxy for connection pooling and improved reliability
# - Security groups following least-privilege principles
# - Enhanced monitoring and performance insights
#
# Connection Flow:
# ECS Tasks -> RDS Proxy -> Aurora Cluster
#
# Why RDS Proxy?
# - Connection pooling reduces database load
# - Automatic failover handling
# - IAM authentication support
# - Improved connection management for serverless workloads
# =============================================================================

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
# Database security is enforced at multiple layers:
# 1. Aurora cluster only accepts connections from RDS Proxy
# 2. RDS Proxy only accepts connections from ECS service
# 3. All connections use TLS encryption

# Aurora Cluster Security Group
# Only allows connections from the RDS Proxy - not directly accessible
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-db-sg"
  description = "Security group for Aurora PostgreSQL cluster - allows connections from RDS Proxy only"
  vpc_id      = aws_vpc.main.id

  tags = local.tags
}

# Allow PostgreSQL (5432) traffic from RDS Proxy only
resource "aws_vpc_security_group_ingress_rule" "db_from_proxy" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from RDS Proxy"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.rds_proxy.id

  tags = local.tags
}

# RDS Proxy Security Group
# Acts as an intermediary between the application and database
resource "aws_security_group" "rds_proxy" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-rds-proxy-sg"
  description = "Security group for RDS Proxy - allows connections from ECS service"
  vpc_id      = aws_vpc.main.id

  tags = local.tags
}

# Allow connections from ECS tasks
resource "aws_vpc_security_group_ingress_rule" "proxy_from_ecs" {
  security_group_id            = aws_security_group.rds_proxy.id
  description                  = "PostgreSQL from ECS service"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_service.id

  tags = local.tags
}

# Allow RDS Proxy to connect to Aurora cluster
resource "aws_vpc_security_group_egress_rule" "proxy_to_db" {
  security_group_id            = aws_security_group.rds_proxy.id
  description                  = "PostgreSQL to Aurora cluster"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.db.id

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Database Subnet Group
# -----------------------------------------------------------------------------
# Places database instances in private subnets for security

resource "aws_db_subnet_group" "db" {
  name       = "${local.name_prefix}-${random_string.name_suffix.result}-db-subnets"
  subnet_ids = aws_subnet.private_db[*].id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-db-subnets"
  })
}

# -----------------------------------------------------------------------------
# Cluster Parameter Group
# -----------------------------------------------------------------------------
# Custom PostgreSQL parameters for performance and logging

resource "aws_rds_cluster_parameter_group" "app" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-aurora-pg17"
  family      = "aurora-postgresql17"
  description = "Parameter group for Aurora PostgreSQL Serverless v2"

  # Log DDL statements (CREATE, ALTER, DROP) for audit purposes
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  # Log queries taking longer than 1 second for performance analysis
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Aurora PostgreSQL Cluster
# -----------------------------------------------------------------------------
# Serverless v2 provides automatic capacity scaling based on workload.
# Scales from min_capacity to max_capacity ACUs (Aurora Capacity Units).

resource "aws_rds_cluster" "app" {
  cluster_identifier   = "${local.name_prefix}-${random_string.name_suffix.result}-aurora"
  engine               = "aurora-postgresql"
  engine_version       = "17.7"
  engine_mode          = "provisioned" # Required for Serverless v2
  database_name        = "app_db"
  master_username      = "app_user"
  db_subnet_group_name = aws_db_subnet_group.db.name

  # AWS-managed master password - no need to store/rotate ourselves
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.secrets.arn

  # Security configuration
  vpc_security_group_ids              = [aws_security_group.db.id]
  storage_encrypted                   = true               # Encrypt data at rest
  kms_key_id                          = aws_kms_key.db.arn # Use custom KMS key
  iam_database_authentication_enabled = true               # Allow IAM auth
  deletion_protection                 = true               # Prevent accidental deletion

  # Backup configuration
  backup_retention_period = 7             # Keep backups for 7 days
  preferred_backup_window = "03:00-04:00" # Backup at 3 AM UTC
  copy_tags_to_snapshot   = true          # Inherit tags on snapshots

  # Maintenance configuration
  preferred_maintenance_window    = "sun:05:00-sun:06:00" # Sunday 5 AM UTC
  apply_immediately               = true
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.app.name

  # Serverless v2 auto-scaling configuration
  # ACU = Aurora Capacity Unit (2 GB RAM per ACU)
  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity # Minimum ACUs (0.5 = 1 GB RAM)
    max_capacity = var.aurora_max_capacity # Maximum ACUs
  }

  # Export PostgreSQL logs to CloudWatch for troubleshooting
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Enhanced Monitoring IAM Role
# -----------------------------------------------------------------------------
# Required for RDS Enhanced Monitoring feature

resource "aws_iam_role" "rds_monitoring" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# Aurora Cluster Instances
# -----------------------------------------------------------------------------
# Two instances for high availability across different AZs.
# Serverless v2 instances scale independently based on workload.

resource "aws_rds_cluster_instance" "app" {
  count              = 2 # Two instances for HA
  identifier         = "${local.name_prefix}-${random_string.name_suffix.result}-db-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.app.id
  instance_class     = "db.serverless" # Serverless v2 instance type

  # Engine configuration (inherited from cluster)
  engine         = aws_rds_cluster.app.engine
  engine_version = aws_rds_cluster.app.engine_version

  # Network configuration
  publicly_accessible  = false # Not accessible from internet
  db_subnet_group_name = aws_db_subnet_group.db.name

  # Automatic updates for security patches
  auto_minor_version_upgrade = true

  # Performance monitoring
  performance_insights_enabled    = true               # Enable Performance Insights
  performance_insights_kms_key_id = aws_kms_key.db.arn # Encrypt PI data
  monitoring_interval             = 60                 # Enhanced monitoring every 60s
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  tags = local.tags
}

# -----------------------------------------------------------------------------
# RDS Proxy IAM Role
# -----------------------------------------------------------------------------
# Minimal role for RDS Proxy - only needs to assume role for IAM auth

resource "aws_iam_role" "rds_proxy" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-rds-proxy"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "rds_proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# RDS Proxy
# -----------------------------------------------------------------------------
# Provides connection pooling and automatic failover handling with IAM auth.
# Applications connect using IAM credentials instead of passwords.
#
# Authentication flow:
# 1. RDS Proxy uses AWS-managed secret to connect TO Aurora
# 2. Applications use IAM auth tokens to connect to RDS Proxy
# 3. No passwords in application code or config!

resource "aws_db_proxy" "app" {
  name          = "${local.name_prefix}-${random_string.name_suffix.result}-proxy"
  engine_family = "POSTGRESQL"

  # RDS Proxy authenticates to Aurora using AWS-managed master user secret
  auth {
    auth_scheme = "SECRETS"
    description = "RDS Proxy to Aurora authentication"
    iam_auth    = "REQUIRED" # Require IAM auth for client connections
    secret_arn  = aws_rds_cluster.app.master_user_secret[0].secret_arn
  }

  # Connection settings
  debug_logging       = false # Disable debug logging in production
  idle_client_timeout = 1800  # 30 minutes idle timeout
  require_tls         = true  # Enforce TLS for all connections

  # IAM and network configuration
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  vpc_subnet_ids         = aws_subnet.private_db[*].id

  tags = local.tags

  depends_on = [aws_rds_cluster.app]
}

# Associate the proxy with the Aurora cluster
resource "aws_db_proxy_target" "app" {
  db_proxy_name         = aws_db_proxy.app.name
  target_group_name     = "default"
  db_cluster_identifier = aws_rds_cluster.app.id
}

# RDS Proxy needs permission to read the AWS-managed master user secret
data "aws_iam_policy_document" "rds_proxy" {
  statement {
    sid = "SecretsManagerAccess"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_rds_cluster.app.master_user_secret[0].secret_arn]
  }

  statement {
    sid       = "KMSDecrypt"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.secrets.arn]
  }
}

resource "aws_iam_role_policy" "rds_proxy" {
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-rds-proxy-policy"
  role   = aws_iam_role.rds_proxy.id
  policy = data.aws_iam_policy_document.rds_proxy.json
}