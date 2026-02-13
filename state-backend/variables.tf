variable "project_name" {
  description = "Logical name for this project (used as prefix for backend resources)."
  type        = string
  default     = "backend-infra"
}

variable "environment" {
  description = "Environment name (e.g. prod, staging)."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region where the backend resources will be created."
  type        = string
  default     = "us-east-1"
}


