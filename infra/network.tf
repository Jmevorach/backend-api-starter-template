# =============================================================================
# VPC Network Configuration
# =============================================================================
# This file defines the network infrastructure:
# - VPC with DNS support for private hosted zones
# - Public subnets for ALB and NAT Gateway
# - Private subnets for ECS tasks (application tier)
# - Private subnets for RDS (database tier)
# - NAT Gateway for outbound internet access from private subnets
# - VPC Flow Logs for network monitoring and security analysis
#
# Network Architecture:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                              VPC (10.0.0.0/16)                          │
# │  ┌─────────────────────────┐  ┌─────────────────────────┐               │
# │  │   Public Subnet (AZ-a)  │  │   Public Subnet (AZ-b)  │               │
# │  │      10.0.0.0/20        │  │      10.0.16.0/20       │               │
# │  │  [ALB] [NAT Gateway]    │  │        [ALB]            │               │
# │  └─────────────────────────┘  └─────────────────────────┘               │
# │  ┌─────────────────────────┐  ┌─────────────────────────┐               │
# │  │  Private App (AZ-a)     │  │  Private App (AZ-b)     │               │
# │  │      10.0.32.0/20       │  │      10.0.48.0/20       │               │
# │  │     [ECS Tasks]         │  │     [ECS Tasks]         │               │
# │  └─────────────────────────┘  └─────────────────────────┘               │
# │  ┌─────────────────────────┐  ┌─────────────────────────┐               │
# │  │  Private DB (AZ-a)      │  │  Private DB (AZ-b)      │               │
# │  │      10.0.64.0/20       │  │      10.0.80.0/20       │               │
# │  │  [Aurora] [RDS Proxy]   │  │  [Aurora] [RDS Proxy]   │               │
# │  └─────────────────────────┘  └─────────────────────────┘               │
# └─────────────────────────────────────────────────────────────────────────┘
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get available AZs in the current region for high availability
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
# Main VPC with a /16 CIDR block providing 65,536 IP addresses.
# DNS support is enabled for Route 53 private hosted zones.

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true # Enable DNS resolution
  enable_dns_hostnames = true # Enable DNS hostnames for EC2 instances

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-vpc"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
# Provides internet access for resources in public subnets.
# Required for ALB to receive traffic and NAT Gateway to function.

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-igw"
  })
}

# -----------------------------------------------------------------------------
# Public Subnets
# -----------------------------------------------------------------------------
# Subnets with direct internet access via Internet Gateway.
# Used for: ALB, NAT Gateway
# Note: map_public_ip_on_launch is true for ALB requirements

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index) # /20 subnets
  map_public_ip_on_launch = true                                                # Required for ALB
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-public-${count.index + 1}"
    Tier = "public"
  })
}

# -----------------------------------------------------------------------------
# Private Application Subnets
# -----------------------------------------------------------------------------
# Subnets for ECS Fargate tasks. No direct internet access.
# Outbound traffic flows through NAT Gateway.

resource "aws_subnet" "private_app" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index + 2) # /20 subnets
  map_public_ip_on_launch = false                                                   # No public IPs
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-private-app-${count.index + 1}"
    Tier = "private-app"
  })
}

# -----------------------------------------------------------------------------
# Private Database Subnets
# -----------------------------------------------------------------------------
# Isolated subnets for Aurora and RDS Proxy.
# No internet access (even outbound) for maximum security.

resource "aws_subnet" "private_db" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index + 4) # /20 subnets
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-private-db-${count.index + 1}"
    Tier = "private-db"
  })
}

# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------
# Provides outbound internet access for private subnets.
# Required for ECS tasks to pull images, call AWS APIs, and reach OAuth providers.
# Single NAT Gateway (cost-optimized); for production HA, add one per AZ.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-nat-eip"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Place in first public subnet

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-nat"
  })
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------

# Public route table - routes internet traffic through IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-public-rt"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table - routes internet traffic through NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-private-rt"
  })
}

# Associate private app subnets with private route table
resource "aws_route_table_association" "private_app" {
  count          = length(aws_subnet.private_app)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private.id
}

# Associate private db subnets with private route table
resource "aws_route_table_association" "private_db" {
  count          = length(aws_subnet.private_db)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# VPC Flow Logs
# -----------------------------------------------------------------------------
# Capture network traffic metadata for security analysis and troubleshooting.
# Logs are encrypted with KMS and retained for 1 year.

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/vpc/${local.name_prefix}-${random_string.name_suffix.result}"
  retention_in_days = 365                  # 1 year retention for compliance
  kms_key_id        = aws_kms_key.logs.arn # Encrypt logs at rest

  tags = local.tags
}

# IAM role for VPC Flow Logs to write to CloudWatch
resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "vpc_flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

# Least-privilege policy for writing flow logs
data "aws_iam_policy_document" "vpc_flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = [
      "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
    ]
  }

  statement {
    actions = [
      "logs:DescribeLogGroups"
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"
    ]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-vpc-flow-logs-policy"
  role   = aws_iam_role.vpc_flow_logs.id
  policy = data.aws_iam_policy_document.vpc_flow_logs.json
}

# Enable VPC Flow Logs - capture ALL traffic (accepted and rejected)
resource "aws_flow_log" "vpc" {
  log_destination = aws_cloudwatch_log_group.vpc_flow.arn
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # Capture both accepted and rejected traffic

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${random_string.name_suffix.result}-vpc-flow-logs"
  })
}
