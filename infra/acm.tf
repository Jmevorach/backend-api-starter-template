# =============================================================================
# ACM Certificate Configuration
# =============================================================================
# This file manages SSL/TLS certificates for the ALB.
#
# Two modes are supported:
# 1. Auto-create: Provide domain_name and route53_zone_name, and Terraform will
#    create and validate the certificate automatically.
# 2. Bring your own: Provide alb_acm_certificate_arn with an existing cert.
#
# If both are provided, the auto-created certificate takes precedence.
# =============================================================================

# -----------------------------------------------------------------------------
# Data Source: Route 53 Hosted Zone
# -----------------------------------------------------------------------------
# Look up the hosted zone by name

data "aws_route53_zone" "main" {
  count = var.route53_zone_name != "" ? 1 : 0
  name  = var.route53_zone_name
}

# -----------------------------------------------------------------------------
# ACM Certificate
# -----------------------------------------------------------------------------
# Create a certificate for the domain if domain_name is provided

resource "aws_acm_certificate" "app" {
  count             = var.domain_name != "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Also cover the www subdomain
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cert"
  })
}

# -----------------------------------------------------------------------------
# DNS Validation Records
# -----------------------------------------------------------------------------
# Create Route 53 records for DNS validation (only if zone_name is provided)

resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" && var.route53_zone_name != "" ? {
    for dvo in aws_acm_certificate.app[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

# -----------------------------------------------------------------------------
# Certificate Validation
# -----------------------------------------------------------------------------
# Wait for the certificate to be validated

resource "aws_acm_certificate_validation" "app" {
  count                   = var.domain_name != "" && var.route53_zone_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# DNS Record for Application
# -----------------------------------------------------------------------------
# Point the domain to the Global Accelerator (or ALB if GA is not used)

resource "aws_route53_record" "app" {
  count   = var.domain_name != "" && var.route53_zone_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_globalaccelerator_accelerator.app.dns_name
    zone_id                = aws_globalaccelerator_accelerator.app.hosted_zone_id
    evaluate_target_health = true
  }
}

# Also create a www subdomain record
resource "aws_route53_record" "app_www" {
  count   = var.domain_name != "" && var.route53_zone_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_globalaccelerator_accelerator.app.dns_name
    zone_id                = aws_globalaccelerator_accelerator.app.hosted_zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Local: Determine which certificate to use
# -----------------------------------------------------------------------------

locals {
  # Use auto-created cert if domain is provided and validated, otherwise use provided ARN
  acm_certificate_arn = var.domain_name != "" && var.route53_zone_name != "" ? (
    aws_acm_certificate_validation.app[0].certificate_arn
  ) : var.alb_acm_certificate_arn
}

# -----------------------------------------------------------------------------
# Validation Check
# -----------------------------------------------------------------------------
# Ensure a certificate is configured (either auto-created or provided)

check "certificate_configured" {
  assert {
    condition     = var.domain_name != "" || var.alb_acm_certificate_arn != ""
    error_message = "You must provide either (domain_name + route53_zone_name) for auto-certificate creation, or alb_acm_certificate_arn for an existing certificate."
  }
}
