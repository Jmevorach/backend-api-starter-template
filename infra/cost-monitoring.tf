# =============================================================================
# Cost Monitoring and Budget Alerts
# =============================================================================
# This file configures:
# - AWS Budgets for cost tracking
# - Cost Anomaly Detection
# - Cost allocation tags

# -----------------------------------------------------------------------------
# AWS Budgets
# -----------------------------------------------------------------------------
# Monthly budget with alerts at 50%, 80%, and 100% thresholds
# Only created if budget_alert_emails is provided

resource "aws_budgets_budget" "monthly" {
  count = length(var.budget_alert_emails) > 0 ? 1 : 0

  name              = "${local.name_prefix}-${random_string.name_suffix.result}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = var.monthly_budget_amount
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project_name}"]
  }

  # 50% threshold notification
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # 80% threshold notification
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # 100% threshold notification
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # Forecasted to exceed budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Cost Anomaly Detection
# -----------------------------------------------------------------------------
# Monitors for unexpected cost spikes
# Only created if budget_alert_emails is provided

resource "aws_ce_anomaly_monitor" "main" {
  count = length(var.budget_alert_emails) > 0 ? 1 : 0

  name              = "${local.name_prefix}-${random_string.name_suffix.result}-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = local.tags
}

resource "aws_ce_anomaly_subscription" "main" {
  count = length(var.budget_alert_emails) > 0 ? 1 : 0

  name = "${local.name_prefix}-${random_string.name_suffix.result}-anomaly-subscription"

  monitor_arn_list = [aws_ce_anomaly_monitor.main[0].arn]

  frequency = "DAILY"

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [var.cost_anomaly_threshold]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  subscriber {
    type    = "EMAIL"
    address = var.budget_alert_emails[0]
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Variables for Cost Monitoring
# -----------------------------------------------------------------------------

variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD"
  type        = string
  default     = "500"
}

variable "budget_alert_emails" {
  description = "Email addresses to receive budget alerts"
  type        = list(string)
  default     = []
}

variable "cost_anomaly_threshold" {
  description = "Minimum dollar impact to trigger cost anomaly alert"
  type        = string
  default     = "50"
}
