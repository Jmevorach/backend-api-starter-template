# =============================================================================
# Terraform Outputs
# =============================================================================
# This file exports key resource identifiers and endpoints for use by:
# - CI/CD pipelines (GitHub Actions)
# - DNS configuration (Route 53)
# - Monitoring and alerting
# - Other Terraform configurations
# =============================================================================

# -----------------------------------------------------------------------------
# Network Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID for network peering or additional resources."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block for security group rules."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs for internet-facing resources (ALB, NAT)."
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Private subnet IDs for application workloads (ECS tasks)."
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "Private subnet IDs for database resources (Aurora, RDS Proxy)."
  value       = aws_subnet.private_db[*].id
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "ALB security group ID for additional ingress rules."
  value       = aws_security_group.alb.id
}

output "ecs_service_security_group_id" {
  description = "ECS service security group ID for service mesh or debugging."
  value       = aws_security_group.ecs_service.id
}

output "db_security_group_id" {
  description = "Database security group ID for bastion host access."
  value       = aws_security_group.db.id
}

output "elasticache_security_group_id" {
  description = "ElastiCache security group ID."
  value       = aws_security_group.elasticache.id
}

# -----------------------------------------------------------------------------
# Global Accelerator Outputs
# -----------------------------------------------------------------------------
# Use these for DNS configuration (CNAME to dns_name or A record to IPs)

output "global_accelerator_dns_name" {
  description = "Global Accelerator DNS name. Create a CNAME record pointing to this."
  value       = aws_globalaccelerator_accelerator.app.dns_name
}

output "global_accelerator_ips" {
  description = "Global Accelerator static anycast IP addresses. Use for A records or allowlisting."
  value       = [for ip_set in aws_globalaccelerator_accelerator.app.ip_sets : ip_set.ip_addresses]
}

output "global_accelerator_arn" {
  description = "Global Accelerator ARN for IAM policies or monitoring."
  value       = aws_globalaccelerator_accelerator.app.id
}

# -----------------------------------------------------------------------------
# ALB Outputs
# -----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "ALB DNS name (internal use - prefer Global Accelerator for external traffic)."
  value       = aws_lb.app_alb.dns_name
}

output "alb_arn" {
  description = "ALB ARN for WAF association or monitoring."
  value       = aws_lb.app_alb.arn
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route 53 alias records."
  value       = aws_lb.app_alb.zone_id
}

# -----------------------------------------------------------------------------
# ECS Outputs
# -----------------------------------------------------------------------------
# Used by CI/CD for deployments

output "ecs_service_name" {
  description = "ECS service name for deployment commands."
  value       = aws_ecs_service.app_service.name
}

output "ecs_cluster_name" {
  description = "ECS cluster name for deployment commands."
  value       = aws_ecs_cluster.app.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN for IAM policies."
  value       = aws_ecs_cluster.app.arn
}

output "ecs_task_definition_arn" {
  description = "Current ECS task definition ARN."
  value       = aws_ecs_task_definition.app.arn
}

# -----------------------------------------------------------------------------
# Database Outputs
# -----------------------------------------------------------------------------

output "aurora_cluster_endpoint" {
  description = "Aurora primary endpoint (write operations). Use RDS Proxy instead for applications."
  value       = aws_rds_cluster.app.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint (read replicas). Use RDS Proxy instead for applications."
  value       = aws_rds_cluster.app.reader_endpoint
}

output "aurora_cluster_arn" {
  description = "Aurora cluster ARN for backup selection or IAM policies."
  value       = aws_rds_cluster.app.arn
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint. Applications should connect here, not directly to Aurora."
  value       = aws_db_proxy.app.endpoint
}

# -----------------------------------------------------------------------------
# ElastiCache Outputs
# -----------------------------------------------------------------------------

output "elasticache_endpoint" {
  description = "ElastiCache Serverless endpoint address."
  value       = aws_elasticache_serverless_cache.app.endpoint[0].address
}

output "elasticache_port" {
  description = "ElastiCache Serverless port."
  value       = aws_elasticache_serverless_cache.app.endpoint[0].port
}

output "elasticache_arn" {
  description = "ElastiCache Serverless ARN for IAM policies."
  value       = aws_elasticache_serverless_cache.app.arn
}

output "elasticache_connection_string" {
  description = "ElastiCache connection string template (requires password substitution)."
  value       = "rediss://app_user@${aws_elasticache_serverless_cache.app.endpoint[0].address}:${aws_elasticache_serverless_cache.app.endpoint[0].port}/0"
  sensitive   = false
}

# -----------------------------------------------------------------------------
# ECR Outputs
# -----------------------------------------------------------------------------
# Used by CI/CD for image push

output "ecr_repository_url" {
  description = "ECR repository URL for docker push. Format: {account}.dkr.ecr.{region}.amazonaws.com/{name}"
  value       = local.ecr_repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN for IAM policies."
  value       = local.ecr_repository_arn
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------
# Used by CI/CD configuration

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC. Configure as AWS_ROLE_TO_ASSUME in workflows."
  value       = aws_iam_role.github_actions.arn
}

output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN. Used by ECS agent for image pull and secret retrieval."
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN. Used by the application container for AWS API calls."
  value       = aws_iam_role.ecs_task.arn
}

# -----------------------------------------------------------------------------
# KMS Outputs
# -----------------------------------------------------------------------------
# Used for encryption configuration in other resources

output "kms_logs_key_arn" {
  description = "KMS key ARN for logs encryption (CloudTrail, CloudWatch, S3)."
  value       = aws_kms_key.logs.arn
}

output "kms_db_key_arn" {
  description = "KMS key ARN for database encryption (Aurora, backups)."
  value       = aws_kms_key.db.arn
}

output "kms_secrets_key_arn" {
  description = "KMS key ARN for Secrets Manager encryption."
  value       = aws_kms_key.secrets.arn
}

output "kms_uploads_key_arn" {
  description = "KMS key ARN for S3 uploads bucket encryption."
  value       = aws_kms_key.uploads.arn
}

# -----------------------------------------------------------------------------
# Logging Outputs
# -----------------------------------------------------------------------------

output "logs_bucket_name" {
  description = "S3 bucket name for logs. Used by ALB, CloudTrail, Global Accelerator."
  value       = aws_s3_bucket.logs.id
}

output "ecs_log_group_name" {
  description = "CloudWatch log group name for ECS application logs."
  value       = aws_cloudwatch_log_group.ecs_app.name
}

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN for monitoring configuration."
  value       = aws_cloudtrail.main.arn
}

# -----------------------------------------------------------------------------
# ACM Certificate Outputs
# -----------------------------------------------------------------------------

output "acm_certificate_arn" {
  description = "ACM certificate ARN used by the ALB (auto-created or provided)."
  value       = local.acm_certificate_arn
}

output "app_domain_name" {
  description = "Application domain name (if configured)."
  value       = var.domain_name != "" ? var.domain_name : null
}

output "app_url" {
  description = "Application URL. Uses domain if configured, otherwise Global Accelerator DNS."
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_globalaccelerator_accelerator.app.dns_name}"
}

# -----------------------------------------------------------------------------
# S3 Uploads Outputs
# -----------------------------------------------------------------------------

output "uploads_bucket_name" {
  description = "S3 bucket name for user uploads. Configure as UPLOADS_BUCKET in application."
  value       = aws_s3_bucket.uploads.id
}

output "uploads_bucket_arn" {
  description = "S3 uploads bucket ARN for IAM policies."
  value       = aws_s3_bucket.uploads.arn
}

output "uploads_bucket_regional_domain" {
  description = "S3 uploads bucket regional domain name for direct access."
  value       = aws_s3_bucket.uploads.bucket_regional_domain_name
}

output "uploads_cloudfront_domain" {
  description = "CloudFront distribution domain for uploads (if enabled)."
  value       = var.uploads_enable_cloudfront ? aws_cloudfront_distribution.uploads[0].domain_name : null
}

output "uploads_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for cache invalidation (if enabled)."
  value       = var.uploads_enable_cloudfront ? aws_cloudfront_distribution.uploads[0].id : null
}
