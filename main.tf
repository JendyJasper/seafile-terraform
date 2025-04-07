provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket         = "placeholder"
    key            = "seafile-terraform/terraform.tfstate"
    region         = "placeholder"
    dynamodb_table = "placeholder"
  }
}

# Random ID for bucket suffix
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# IAM User for Seafile Service Account
resource "aws_iam_user" "seafile_service_account" {
  name = "seafile-service-account"
  tags = { Name = "Seafile Service Account" }
}

resource "aws_iam_access_key" "seafile_service_account_key" {
  user = aws_iam_user.seafile_service_account.name

  lifecycle {
    ignore_changes = [
      id     # Ignore changes to the access key ID
    ]
  }
}

resource "aws_ssm_parameter" "seafile_iam_credentials" {
  name        = "/seafile/iam_user/credentials"
  description = "IAM credentials for Seafile service account"
  type        = "SecureString"
  value = jsonencode({
    access_key_id     = aws_iam_access_key.seafile_service_account_key.id
    secret_access_key = aws_iam_access_key.seafile_service_account_key.secret
  })
  lifecycle {
    ignore_changes = [
      value  # Ignore changes to the parameter value
    ]
  }
}

# Key Pair for EC2
resource "tls_private_key" "seafile_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_ssm_parameter" "seafile_private_key" {
  name        = "/seafile/ec2/keypair"
  description = "Private key for Seafile EC2 instance"
  type        = "SecureString"
  value       = tls_private_key.seafile_key.private_key_pem
}

# SSM Parameters
resource "aws_ssm_parameter" "seafile_additional_params" {
  for_each    = local.seafile_parameters
  name        = "/seafile/${each.key}"
  description = each.value.description
  type        = "SecureString"
  value       = each.value.value
}