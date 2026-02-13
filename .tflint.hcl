# TFLint configuration
# https://github.com/terraform-linters/tflint

config {
  # Enable module inspection
  call_module_type = "local"
}

# AWS provider rules
plugin "aws" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Terraform rules
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Custom rule configurations
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

# AWS-specific rules
rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Project", "Environment"]
}

rule "aws_iam_policy_document_gov_friendly_arns" {
  enabled = false  # Disable if not using GovCloud
}
