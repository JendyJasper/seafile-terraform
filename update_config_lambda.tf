# Zip the UpdateConfigLambda function
data "archive_file" "update_config_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/update_config_lambda.py"
  output_path = "${path.module}/update_config_lambda.zip"
}

# IAM Role for UpdateConfigLambda
resource "aws_iam_role" "update_config_lambda_execution_role" {
  name = "UpdateConfigLambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "update_config_lambda_policy" {
  name   = "UpdateConfigLambdaPolicy"
  role   = aws_iam_role.update_config_lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:*"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/seafile/*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:DeleteAccessKey"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/seafile-service-account"
      }
    ]
  })
}

# Lambda Function for UpdateConfigLambda
resource "aws_lambda_function" "update_config_lambda" {
  filename      = data.archive_file.update_config_lambda_zip.output_path
  function_name = "UpdateConfigLambda"
  role          = aws_iam_role.update_config_lambda_execution_role.arn
  handler       = "update_config_lambda.lambda_handler"
  runtime       = "python3.9"
  timeout       = 600

  environment {
    variables = {
      REGION      = var.region
      INSTANCE_ID = aws_instance.seafile_instance.id
    }
  }

  depends_on = [aws_iam_role_policy.update_config_lambda_policy]
}

# EventBridge Rule for Parameter Store Changes
resource "aws_cloudwatch_event_rule" "parameter_store_change" {
  name        = "ParameterStoreChangeRule"
  description = "Trigger UpdateConfigLambda on Parameter Store changes for /seafile/iam_user/credentials"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Parameter Store Change"]
    detail = {
      name = ["/seafile/iam_user/credentials"]
    }
  })
}

resource "aws_cloudwatch_event_target" "update_config_target" {
  rule      = aws_cloudwatch_event_rule.parameter_store_change.name
  target_id = "UpdateConfigLambda"
  arn       = aws_lambda_function.update_config_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge_update_config" {
  statement_id  = "AllowExecutionFromEventBridgeUpdateConfig"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_config_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.parameter_store_change.arn
}