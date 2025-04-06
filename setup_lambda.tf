# Zip the SetupEC2Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

# Lambda Role and Policy
resource "aws_iam_role" "seafile_lambda_role" {
  name = "SeafileLambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "seafile_lambda_policy" {
  name   = "SeafileLambdaPolicy"
  role   = aws_iam_role.seafile_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:SendCommand", "ssm:GetCommandInvocation"]
        Resource = [
          "*",
          "*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:*"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeTags", "ec2:CreateTags"]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "seafile_lambda" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "SetupEC2Lambda"
  role          = aws_iam_role.seafile_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 600

  environment {
    variables = {
      REGION        = var.region
      EIP_PUBLIC_IP = aws_eip.seafile_eip.public_ip
      COMMIT_BUCKET = aws_s3_bucket.seafile_buckets["commit"].id
      FS_BUCKET     = aws_s3_bucket.seafile_buckets["fs"].id
      BLOCK_BUCKET  = aws_s3_bucket.seafile_buckets["block"].id
    }
  }
  depends_on = [aws_iam_role_policy.seafile_lambda_policy]
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "seafile_setup" {
  name        = "SeafileSetupRule"
  description = "Trigger Lambda when any EC2 instance starts"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["running"]
    }
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.seafile_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.seafile_setup.arn
}

resource "aws_cloudwatch_event_target" "seafile_lambda_target" {
  rule      = aws_cloudwatch_event_rule.seafile_setup.name
  target_id = "SeafileLambda"
  arn       = aws_lambda_function.seafile_lambda.arn
}