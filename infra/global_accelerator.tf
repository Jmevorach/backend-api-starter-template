# =============================================================================
# AWS Global Accelerator Configuration
# =============================================================================
# Global Accelerator provides static anycast IP addresses that route traffic
# to the optimal AWS endpoint based on health, geography, and routing policies.
#
# Benefits over CloudFront for API workloads:
# - Static IP addresses (useful for allowlisting)
# - TCP/UDP protocol support (not just HTTP)
# - Lower latency for real-time applications
# - Client IP preservation
# - Automatic failover between regions
#
# Traffic Flow:
# Users -> Global Accelerator (anycast IPs) -> ALB -> ECS Tasks
#
# Note: Global Accelerator is a global service but endpoints are regional.
# For multi-region deployments, add endpoint groups in each region.
# =============================================================================

# -----------------------------------------------------------------------------
# Global Accelerator
# -----------------------------------------------------------------------------
# Creates the accelerator with two static anycast IP addresses.
# These IPs are advertised from AWS edge locations worldwide.

resource "aws_globalaccelerator_accelerator" "app" {
  name            = "${local.name_prefix}-${random_string.name_suffix.result}-ga"
  ip_address_type = "IPV4"
  enabled         = true

  # Flow logs for traffic analysis and troubleshooting
  # Logs are stored in the same S3 bucket as other infrastructure logs
  attributes {
    flow_logs_enabled   = true
    flow_logs_s3_bucket = aws_s3_bucket.logs.id
    flow_logs_s3_prefix = "global-accelerator/"
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Listener
# -----------------------------------------------------------------------------
# Defines which ports and protocols the accelerator accepts.
# Using TCP for HTTPS traffic (TLS termination happens at ALB).

resource "aws_globalaccelerator_listener" "https" {
  accelerator_arn = aws_globalaccelerator_accelerator.app.id
  protocol        = "TCP" # TCP passthrough to ALB

  # Accept traffic on port 443 only
  port_range {
    from_port = 443
    to_port   = 443
  }
}

# -----------------------------------------------------------------------------
# Endpoint Group
# -----------------------------------------------------------------------------
# Defines the regional endpoints that receive traffic.
# The ALB is the target - Global Accelerator routes traffic directly to it.

resource "aws_globalaccelerator_endpoint_group" "app" {
  listener_arn          = aws_globalaccelerator_listener.https.id
  endpoint_group_region = var.aws_region # Region where the ALB is deployed

  # Health check configuration
  # Global Accelerator will only route to healthy endpoints
  health_check_interval_seconds = 30         # Check every 30 seconds
  health_check_path             = "/healthz" # Phoenix health endpoint
  health_check_port             = 443
  health_check_protocol         = "HTTPS"
  threshold_count               = 3 # 3 failures = unhealthy

  # Traffic routing
  traffic_dial_percentage = 100 # Route 100% of traffic to this endpoint group

  # ALB endpoint configuration
  endpoint_configuration {
    endpoint_id = aws_lb.app_alb.arn
    weight      = 100 # Full weight (only one endpoint)

    # Preserve client IP address for logging and rate limiting
    # The original client IP is passed in X-Forwarded-For header
    client_ip_preservation_enabled = true
  }

  # Port mapping (optional, but explicit is better)
  port_override {
    endpoint_port = 443
    listener_port = 443
  }
}
