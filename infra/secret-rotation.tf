# =============================================================================
# Secret Rotation Configuration
# =============================================================================
# With IAM authentication for database and ElastiCache, only SECRET_KEY_BASE
# needs rotation. This dramatically simplifies the infrastructure.
#
# What we DON'T need anymore:
# - Database password rotation Lambda
# - ElastiCache auth token rotation Lambda
# - Complex rotation coordination logic
#
# What we DO keep:
# - SECRET_KEY_BASE rotation (required for Phoenix security)
#
# Note: When SECRET_KEY_BASE rotates, the application will need to restart
# to pick up the new value. This is handled gracefully via ECS rolling updates.
# =============================================================================

# -----------------------------------------------------------------------------
# SECRET_KEY_BASE Rotation
# -----------------------------------------------------------------------------
# Custom rotation for Phoenix SECRET_KEY_BASE.
# Note: When this rotates, the application needs to restart to pick up the new value.
# ECS will handle this via rolling updates when the task definition is updated.

resource "aws_secretsmanager_secret_rotation" "secret_key_base" {
  secret_id           = aws_secretsmanager_secret.secret_key_base.id
  rotation_lambda_arn = aws_lambda_function.secret_key_base_rotation.arn

  rotation_rules {
    automatically_after_days = 90 # Rotate every 90 days
  }

  depends_on = [
    aws_lambda_permission.secret_key_base_rotation,
    aws_iam_role_policy.secret_key_base_rotation
  ]
}

# Lambda function for SECRET_KEY_BASE rotation
resource "aws_lambda_function" "secret_key_base_rotation" {
  filename      = data.archive_file.secret_key_base_rotation_zip.output_path
  function_name = "${local.name_prefix}-${random_string.name_suffix.result}-secret-key-base-rotation"
  role          = aws_iam_role.secret_key_base_rotation.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_python_runtime
  timeout       = 60
  memory_size   = 128

  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.app.name
      ECS_SERVICE = aws_ecs_service.app_service.name
    }
  }

  tags = local.tags
}

# Lambda code for SECRET_KEY_BASE rotation
data "archive_file" "secret_key_base_rotation_zip" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/secret_key_base_rotation.zip"
  source_dir  = "${path.module}/lambdas/secret_key_base_rotation"
}

# IAM Role for SECRET_KEY_BASE rotation Lambda
resource "aws_iam_role" "secret_key_base_rotation" {
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-secret-key-base-rotation"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Permissions for SECRET_KEY_BASE rotation
data "aws_iam_policy_document" "secret_key_base_rotation" {
  # Secrets Manager permissions
  statement {
    sid = "SecretsManagerAccess"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = [
      aws_secretsmanager_secret.secret_key_base.arn
    ]
  }

  # KMS permissions
  statement {
    sid = "KMSDecrypt"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [
      aws_kms_key.secrets.arn
    ]
  }

  # CloudWatch Logs
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-${random_string.name_suffix.result}-*"
    ]
  }

  # ECS permissions to trigger service update
  statement {
    sid = "ECSUpdateService"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices"
    ]
    resources = [
      aws_ecs_service.app_service.id
    ]
  }
}

resource "aws_iam_role_policy" "secret_key_base_rotation" {
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-secret-key-base-rotation-policy"
  role   = aws_iam_role.secret_key_base_rotation.id
  policy = data.aws_iam_policy_document.secret_key_base_rotation.json
}

# Allow Secrets Manager to invoke the Lambda
# source_arn restricts invocation to only the specific secret, preventing
# other secrets (including from other accounts) from invoking this Lambda
resource "aws_lambda_permission" "secret_key_base_rotation" {
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_key_base_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.secret_key_base.arn
}

# CloudWatch Log Group for rotation Lambda
resource "aws_cloudwatch_log_group" "secret_key_base_rotation" {
  name              = "/aws/lambda/${aws_lambda_function.secret_key_base_rotation.function_name}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.logs.arn

  tags = local.tags
}

# =============================================================================
# Database Password Rotation (Optional)
# =============================================================================
# Only created when db_password_secret_arn is provided.
# This is for environments that use password authentication instead of IAM.

resource "aws_secretsmanager_secret_rotation" "db_password" {
  count               = var.db_password_secret_arn != "" ? 1 : 0
  secret_id           = var.db_password_secret_arn
  rotation_lambda_arn = aws_lambda_function.db_password_rotation[0].arn

  rotation_rules {
    automatically_after_days = 90
  }

  depends_on = [
    aws_lambda_permission.db_password_rotation,
    aws_iam_role_policy.db_password_rotation
  ]
}

resource "aws_lambda_function" "db_password_rotation" {
  count         = var.db_password_secret_arn != "" ? 1 : 0
  filename      = data.archive_file.db_password_rotation_zip[0].output_path
  function_name = "${local.name_prefix}-${random_string.name_suffix.result}-db-password-rotation"
  role          = aws_iam_role.db_password_rotation[0].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_python_runtime
  timeout       = 60
  memory_size   = 128

  environment {
    variables = {
      RDS_CLUSTER_IDENTIFIER = aws_rds_cluster.app.cluster_identifier
      ECS_CLUSTER            = aws_ecs_cluster.app.name
      ECS_SERVICE            = aws_ecs_service.app_service.name
    }
  }

  tags = local.tags
}

data "archive_file" "db_password_rotation_zip" {
  count       = var.db_password_secret_arn != "" ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/db_password_rotation.zip"
  source_dir  = "${path.module}/lambdas/db_password_rotation"
}

resource "aws_iam_role" "db_password_rotation" {
  count              = var.db_password_secret_arn != "" ? 1 : 0
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-db-password-rotation"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "db_password_rotation" {
  count = var.db_password_secret_arn != "" ? 1 : 0

  statement {
    sid = "SecretsManagerAccess"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = [var.db_password_secret_arn]
  }

  statement {
    sid = "KMSDecrypt"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [aws_kms_key.secrets.arn]
  }

  statement {
    sid       = "RDSModifyCluster"
    actions   = ["rds:ModifyDBCluster"]
    resources = [aws_rds_cluster.app.arn]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-${random_string.name_suffix.result}-db-password-rotation:*"
    ]
  }

  statement {
    sid       = "ECSUpdateService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [aws_ecs_service.app_service.id]
  }
}

resource "aws_iam_role_policy" "db_password_rotation" {
  count  = var.db_password_secret_arn != "" ? 1 : 0
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-db-password-rotation-policy"
  role   = aws_iam_role.db_password_rotation[0].id
  policy = data.aws_iam_policy_document.db_password_rotation[0].json
}

resource "aws_lambda_permission" "db_password_rotation" {
  count         = var.db_password_secret_arn != "" ? 1 : 0
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_password_rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = var.db_password_secret_arn
}

resource "aws_cloudwatch_log_group" "db_password_rotation" {
  count             = var.db_password_secret_arn != "" ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.db_password_rotation[0].function_name}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.logs.arn

  tags = local.tags
}

# =============================================================================
# Valkey Password Rotation (Optional)
# =============================================================================
# Only created when valkey_password_secret_arn is provided.
# This is for environments that use password authentication instead of IAM.

resource "aws_secretsmanager_secret_rotation" "valkey_password" {
  count               = var.valkey_password_secret_arn != "" ? 1 : 0
  secret_id           = var.valkey_password_secret_arn
  rotation_lambda_arn = aws_lambda_function.valkey_password_rotation[0].arn

  rotation_rules {
    automatically_after_days = 90
  }

  depends_on = [
    aws_lambda_permission.valkey_password_rotation,
    aws_iam_role_policy.valkey_password_rotation
  ]
}

resource "aws_lambda_function" "valkey_password_rotation" {
  count         = var.valkey_password_secret_arn != "" ? 1 : 0
  filename      = data.archive_file.valkey_password_rotation_zip[0].output_path
  function_name = "${local.name_prefix}-${random_string.name_suffix.result}-valkey-password-rotation"
  role          = aws_iam_role.valkey_password_rotation[0].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_python_runtime
  timeout       = 60
  memory_size   = 128

  environment {
    variables = {
      ELASTICACHE_USER_ID = local.elasticache_app_user_final_id
      ECS_CLUSTER         = aws_ecs_cluster.app.name
      ECS_SERVICE         = aws_ecs_service.app_service.name
    }
  }

  tags = local.tags
}

data "archive_file" "valkey_password_rotation_zip" {
  count       = var.valkey_password_secret_arn != "" ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/valkey_password_rotation.zip"
  source_dir  = "${path.module}/lambdas/elasticache_auth_rotation"
}

resource "aws_iam_role" "valkey_password_rotation" {
  count              = var.valkey_password_secret_arn != "" ? 1 : 0
  name               = "${local.name_prefix}-${random_string.name_suffix.result}-valkey-password-rotation"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "valkey_password_rotation" {
  count = var.valkey_password_secret_arn != "" ? 1 : 0

  statement {
    sid = "SecretsManagerAccess"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = [var.valkey_password_secret_arn]
  }

  statement {
    sid = "KMSDecrypt"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [aws_kms_key.secrets.arn]
  }

  statement {
    sid       = "ElastiCacheModifyUser"
    actions   = ["elasticache:ModifyUser"]
    resources = ["arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:user:${local.elasticache_app_user_final_id}"]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-${random_string.name_suffix.result}-valkey-password-rotation:*"
    ]
  }

  statement {
    sid       = "ECSUpdateService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [aws_ecs_service.app_service.id]
  }
}

resource "aws_iam_role_policy" "valkey_password_rotation" {
  count  = var.valkey_password_secret_arn != "" ? 1 : 0
  name   = "${local.name_prefix}-${random_string.name_suffix.result}-valkey-password-rotation-policy"
  role   = aws_iam_role.valkey_password_rotation[0].id
  policy = data.aws_iam_policy_document.valkey_password_rotation[0].json
}

resource "aws_lambda_permission" "valkey_password_rotation" {
  count         = var.valkey_password_secret_arn != "" ? 1 : 0
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.valkey_password_rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = var.valkey_password_secret_arn
}

resource "aws_cloudwatch_log_group" "valkey_password_rotation" {
  count             = var.valkey_password_secret_arn != "" ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.valkey_password_rotation[0].function_name}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.logs.arn

  tags = local.tags
}
