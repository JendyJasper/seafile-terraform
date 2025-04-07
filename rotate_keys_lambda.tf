# Zip the RotateKeysLambda function
data "archive_file" "rotate_keys_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/rotate_keys_lambda.py"
  output_path = "${path.module}/rotate_keys_lambda.zip"
}

# IAM Role for RotateKeysLambda
resource "aws_iam_role" "rotate_keys_lambda_execution_role" {
  name = "RotateKeysLambdaExecutionRole"

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

resource "aws_iam_role_policy" "rotate_keys_lambda_policy" {
  name   = "RotateKeysLambdaPolicy"
  role   = aws_iam_role.rotate_keys_lambda_execution_role.id
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
      }
    ]
  })
}

# Lambda Function for RotateKeysLambda
resource "aws_lambda_function" "rotate_keys_lambda" {
  filename      = data.archive_file.rotate_keys_lambda_zip.output_path
  function_name = "RotateKeysLambda"
  role          = aws_iam_role.rotate_keys_lambda_execution_role.arn
  handler       = "rotate_keys_lambda.lambda_handler"
  runtime       = "python3.9"
  timeout       = 600

  environment {
    variables = {
      REGION      = var.region  # Changed from AWS_REGION to REGION
      INSTANCE_ID = aws_instance.seafile_instance.id
    }
  }

  depends_on = [aws_iam_role_policy.rotate_keys_lambda_policy]
}

# EventBridge Scheduled Rule for RotateKeysLambda
resource "aws_cloudwatch_event_rule" "rotate_keys_schedule" {
  name                = "RotateKeysSchedule"
  description         = "Trigger RotateKeysLambda on the 7th of every month at 12:00 AM UTC"
  schedule_expression = "cron(0 0 7 * ? *)"
}

resource "aws_cloudwatch_event_target" "rotate_keys_target" {
  rule      = aws_cloudwatch_event_rule.rotate_keys_schedule.name
  target_id = "RotateKeysLambda"
  arn       = aws_lambda_function.rotate_keys_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge_rotate_keys" {
  statement_id  = "AllowExecutionFromEventBridgeRotateKeys"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_keys_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rotate_keys_schedule.arn
}