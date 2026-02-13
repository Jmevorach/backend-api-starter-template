# =============================================================================
# ECS Fargate Configuration
# =============================================================================
# This file defines the ECS infrastructure for running the Phoenix application:
# - Application Load Balancer (ALB) for HTTPS traffic termination
# - ECS Cluster with Fargate launch type
# - Task definition with container configuration
# - Service with auto-scaling policies
#
# Traffic Flow:
# Global Accelerator -> ALB (HTTPS:443) -> ECS Tasks (HTTPS:443) -> App
# =============================================================================

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
# Security groups control network access using the principle of least privilege.
# We use separate ingress/egress rules for better visibility and auditability.

# ALB Security Group
# Allows inbound HTTPS traffic from the internet (via Global Accelerator)
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-alb-sg"
  description = "Security group for Application Load Balancer - allows HTTPS ingress"
  vpc_id      = aws_vpc.main.id

  tags = local.tags
}

# Allow HTTPS (443) from anywhere - traffic comes via Global Accelerator
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.tags
}

# ALB can only send traffic to ECS tasks - no other egress allowed
resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow traffic to ECS service"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_service.id

  tags = local.tags
}

# ECS Service Security Group
# Controls what traffic can reach the Fargate tasks
resource "aws_security_group" "ecs_service" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-ecs-sg"
  description = "Security group for ECS Fargate tasks - allows traffic from ALB"
  vpc_id      = aws_vpc.main.id

  tags = local.tags
}

# Only allow traffic from the ALB - not directly from the internet
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs_service.id
  description                  = "App traffic from ALB"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  tags = local.tags
}

# Allow ECS tasks to connect to the database via RDS Proxy
resource "aws_vpc_security_group_egress_rule" "ecs_to_db" {
  security_group_id            = aws_security_group.ecs_service.id
  description                  = "Allow traffic to RDS Proxy"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.rds_proxy.id

  tags = local.tags
}

# Allow HTTPS egress for AWS API calls (CloudWatch, Secrets Manager, etc.)
# and external OAuth providers (Google, Apple)
resource "aws_vpc_security_group_egress_rule" "ecs_to_https" {
  security_group_id = aws_security_group.ecs_service.id
  description       = "Allow HTTPS outbound for AWS APIs and external services"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.tags
}

# Allow ECS tasks to connect to ElastiCache (Valkey)
resource "aws_vpc_security_group_egress_rule" "ecs_to_elasticache" {
  security_group_id            = aws_security_group.ecs_service.id
  description                  = "Allow traffic to ElastiCache Serverless"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.elasticache.id

  tags = local.tags
}

# Allow ECS tasks to connect to ElastiCache TLS port
resource "aws_vpc_security_group_egress_rule" "ecs_to_elasticache_tls" {
  security_group_id            = aws_security_group.ecs_service.id
  description                  = "Allow TLS traffic to ElastiCache Serverless"
  from_port                    = 6380
  to_port                      = 6380
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.elasticache.id

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
# The ALB terminates HTTPS and forwards traffic to ECS tasks.
# It's placed in public subnets and accessed via Global Accelerator.

resource "aws_lb" "app_alb" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Connection settings
  idle_timeout = 60

  # Security settings
  enable_deletion_protection       = true # Prevent accidental deletion
  drop_invalid_header_fields       = true # Security: drop malformed headers
  enable_cross_zone_load_balancing = true # Better distribution across AZs

  # Access logging to S3 for compliance and debugging
  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = local.tags

  # Ensure bucket policy is applied before ALB tries to write logs
  depends_on = [aws_s3_bucket_policy.logs]
}

# Target Group for ECS Tasks
# The ALB routes traffic to this target group, which contains ECS task IPs
resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-${random_string.name_suffix.result}-tg"
  port        = 443
  protocol    = "HTTPS"
  target_type = "ip" # Required for Fargate awsvpc network mode
  vpc_id      = aws_vpc.main.id

  # Health check configuration - ALB will only route to healthy targets
  health_check {
    path                = "/healthz" # Phoenix health endpoint
    protocol            = "HTTPS"
    matcher             = "200-399" # Accept 2xx and 3xx responses
    interval            = 30        # Check every 30 seconds
    timeout             = 5         # Timeout after 5 seconds
    healthy_threshold   = 3         # 3 consecutive successes = healthy
    unhealthy_threshold = 3         # 3 consecutive failures = unhealthy
  }

  tags = local.tags
}

# HTTPS Listener
# Terminates TLS and forwards decrypted traffic to targets
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # Modern TLS 1.3 policy
  certificate_arn   = local.acm_certificate_arn             # From acm.tf

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
# The cluster is a logical grouping of ECS services and tasks.
# Container Insights provides detailed metrics and logs.

resource "aws_ecs_cluster" "app" {
  name = "${local.name_prefix}-${random_string.name_suffix.result}-cluster"

  # Enable Container Insights for enhanced monitoring
  # Provides CPU, memory, network, and storage metrics at task level
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------
# Defines how to run the Phoenix application container, including:
# - Resource allocation (CPU, memory)
# - Environment variables and secrets
# - Logging configuration
# - Health checks

# Build the list of secrets to inject into the container
# These are pulled from Secrets Manager at container startup
#
# Note: Database and Valkey use IAM authentication - no passwords needed!
locals {
  ecs_app_secrets = concat(
    # Required secrets - only SECRET_KEY_BASE now (IAM auth for DB/cache)
    [
      {
        name      = "SECRET_KEY_BASE"
        valueFrom = aws_secretsmanager_secret.secret_key_base.arn
      }
    ],
    # Optional secrets - only included if ARN is provided
    # Google OAuth credentials
    var.google_oauth_client_id_secret_arn != "" ? [
      {
        name      = "GOOGLE_CLIENT_ID"
        valueFrom = var.google_oauth_client_id_secret_arn
      }
    ] : [],
    var.google_oauth_client_secret_secret_arn != "" ? [
      {
        name      = "GOOGLE_CLIENT_SECRET"
        valueFrom = var.google_oauth_client_secret_secret_arn
      }
    ] : [],
    # Apple OAuth credentials
    var.apple_oauth_client_id_secret_arn != "" ? [
      {
        name      = "APPLE_CLIENT_ID"
        valueFrom = var.apple_oauth_client_id_secret_arn
      }
    ] : [],
    var.apple_oauth_client_secret_secret_arn != "" ? [
      {
        name      = "APPLE_CLIENT_SECRET"
        valueFrom = var.apple_oauth_client_secret_secret_arn
      }
    ] : [],
    var.apple_oauth_team_id_secret_arn != "" ? [
      {
        name      = "APPLE_TEAM_ID"
        valueFrom = var.apple_oauth_team_id_secret_arn
      }
    ] : [],
    var.apple_oauth_key_id_secret_arn != "" ? [
      {
        name      = "APPLE_KEY_ID"
        valueFrom = var.apple_oauth_key_id_secret_arn
      }
    ] : [],
    var.apple_oauth_private_key_secret_arn != "" ? [
      {
        name      = "APPLE_PRIVATE_KEY"
        valueFrom = var.apple_oauth_private_key_secret_arn
      }
    ] : [],
    # Database/Cache password fallback (optional)
    var.db_password_secret_arn != "" ? [
      {
        name      = "DB_PASSWORD"
        valueFrom = var.db_password_secret_arn
      }
    ] : [],
    var.valkey_password_secret_arn != "" ? [
      {
        name      = "VALKEY_PASSWORD"
        valueFrom = var.valkey_password_secret_arn
      }
    ] : []
  )
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-${random_string.name_suffix.result}-task"
  network_mode             = "awsvpc" # Required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"                               # 0.5 vCPU
  memory                   = "1024"                              # 1 GB RAM
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn # For pulling images/secrets
  task_role_arn            = aws_iam_role.ecs_task.arn           # For app AWS API calls

  # Platform configuration
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  # Container definition - the Phoenix application
  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true

      # Port mapping for HTTPS traffic
      portMappings = [
        {
          containerPort = 443
          hostPort      = 443
          protocol      = "tcp"
        }
      ]

      # Environment variables (non-sensitive configuration)
      # Note: Database and Valkey use IAM authentication - no passwords in env vars!
      environment = [
        { name = "MIX_ENV", value = "prod" },
        { name = "PHX_SERVER", value = "true" },
        { name = "PORT", value = "443" },
        # Database configuration (IAM auth via RDS Proxy)
        { name = "DB_HOST", value = aws_db_proxy.app.endpoint },
        { name = "DB_NAME", value = "app_db" },
        { name = "DB_USERNAME", value = "app_user" },
        { name = "DB_IAM_AUTH", value = "true" },
        { name = "AWS_REGION", value = var.aws_region },
        # Valkey configuration (IAM auth)
        { name = "VALKEY_HOST", value = aws_elasticache_serverless_cache.app.endpoint[0].address },
        { name = "VALKEY_PORT", value = tostring(aws_elasticache_serverless_cache.app.endpoint[0].port) },
        { name = "VALKEY_USER", value = local.elasticache_app_user_final_id },
        { name = "VALKEY_IAM_AUTH", value = "true" },
        { name = "VALKEY_CLUSTER_ID", value = aws_elasticache_serverless_cache.app.name },
        # Security setting - disable password fallback in production
        { name = "REQUIRE_IAM_AUTH", value = tostring(var.require_iam_auth) },
        # S3 uploads configuration
        { name = "UPLOADS_BUCKET", value = aws_s3_bucket.uploads.id },
        { name = "UPLOADS_REGION", value = var.aws_region },
        { name = "UPLOADS_MAX_SIZE_MB", value = tostring(var.uploads_max_file_size_mb) },
        { name = "UPLOADS_PRESIGNED_URL_EXPIRY", value = tostring(var.uploads_presigned_url_expiry_seconds) }
      ]

      # Secrets from Secrets Manager (injected at runtime)
      secrets = local.ecs_app_secrets

      # CloudWatch Logs configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      # Container health check (in addition to ALB health checks)
      healthCheck = {
        command     = ["CMD-SHELL", "curl -kf https://localhost:443/healthz || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60 # Grace period for app startup
      }
    }
  ])

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
# The service maintains the desired number of tasks and handles deployments.
# It's configured for rolling deployments with zero downtime.

resource "aws_ecs_service" "app_service" {
  name             = "${local.name_prefix}-${random_string.name_suffix.result}-service"
  cluster          = aws_ecs_cluster.app.id
  task_definition  = aws_ecs_task_definition.app.arn
  desired_count    = var.service_desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  # Deployment configuration for rolling updates
  # These settings allow for zero-downtime deployments
  deployment_minimum_healthy_percent = 50  # At least 50% healthy during deploy
  deployment_maximum_percent         = 200 # Can spin up 2x tasks during deploy

  # Network configuration - tasks run in private subnets
  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false # No public IPs - egress via NAT Gateway
  }

  # Register tasks with the ALB target group
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 443
  }

  # Ignore desired_count changes - managed by auto-scaling
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Auto Scaling
# -----------------------------------------------------------------------------
# Automatically adjusts the number of tasks based on CPU utilization.
# This ensures the service can handle traffic spikes while minimizing costs.

# Define the scalable target (the ECS service)
resource "aws_appautoscaling_target" "ecs_service" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.app.name}/${aws_ecs_service.app_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based target tracking policy
# Automatically scales to maintain target CPU utilization
resource "aws_appautoscaling_policy" "ecs_cpu_target" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-ecs-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.ecs_cpu_target_utilization
    scale_in_cooldown  = 120 # Wait 2 min before scaling in (prevent flapping)
    scale_out_cooldown = 60  # Wait 1 min before scaling out (responsive to load)

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
