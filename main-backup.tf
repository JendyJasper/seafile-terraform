# provider "aws" {
#   region = var.region
# }

# terraform {
#   backend "s3" {
#     bucket         = "placeholder"
#     key            = "seafile-terraform/terraform.tfstate"
#     region         = "placeholder"
#     dynamodb_table = "placeholder"
#   }
# }

# # IAM Policy for EC2 (S3 and SSM access)
# resource "aws_iam_policy" "seafile_s3_and_ssm_access_policy" {
#   name        = "SeafileS3AndSSMAccessPolicy"
#   description = "Policy for Seafile EC2 instance to access S3 and SSM parameters under /seafile/*"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = ["s3:*"]
#         Resource = ["arn:aws:s3:::seafile-storage-bucket-*", "arn:aws:s3:::seafile-storage-bucket-*/*"]
#       },
#       {
#         Effect   = "Allow"
#         Action   = ["ssm:*"]
#         Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/seafile/*"
#       }
#     ]
#   })
# }

# # IAM Role for EC2
# resource "aws_iam_role" "seafile_ec2_role" {
#   name = "SeafileEC2Role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "seafile_s3_and_ssm_access_policy_attachment" {
#   role       = aws_iam_role.seafile_ec2_role.name
#   policy_arn = aws_iam_policy.seafile_s3_and_ssm_access_policy.arn
# }

# resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
#   role       = aws_iam_role.seafile_ec2_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }

# resource "aws_iam_instance_profile" "seafile_instance_profile" {
#   name = "seafile-instance-profile"
#   role = aws_iam_role.seafile_ec2_role.name
# }

# # IAM User for Seafile Service Account
# resource "aws_iam_user" "seafile_service_account" {
#   name = "seafile-service-account"
#   tags = { Name = "Seafile Service Account" }
# }

# resource "aws_iam_access_key" "seafile_service_account_key" {
#   user = aws_iam_user.seafile_service_account.name
# }

# resource "aws_ssm_parameter" "seafile_iam_credentials" {
#   name        = "/seafile/iam_user/credentials"
#   description = "IAM credentials for Seafile service account"
#   type        = "SecureString"
#   value = jsonencode({
#     access_key_id     = aws_iam_access_key.seafile_service_account_key.id
#     secret_access_key = aws_iam_access_key.seafile_service_account_key.secret
#   })
# }

# resource "aws_iam_policy" "seafile_service_account_s3_policy" {
#   name        = "SeafileServiceAccountS3Policy"
#   description = "Policy for Seafile service account to access S3"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = ["s3:*"]
#       Resource = ["arn:aws:s3:::seafile-storage-bucket-*", "arn:aws:s3:::seafile-storage-bucket-*/*"]
#     }]
#   })
# }

# resource "aws_iam_user_policy_attachment" "seafile_service_account_s3_policy_attachment" {
#   user       = aws_iam_user.seafile_service_account.name
#   policy_arn = aws_iam_policy.seafile_service_account_s3_policy.arn
# }

# # Key Pair for EC2
# resource "tls_private_key" "seafile_key" {
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# resource "aws_key_pair" "seafile_key_pair" {
#   key_name   = "seafile-key-pair"
#   public_key = tls_private_key.seafile_key.public_key_openssh
# }

# resource "aws_ssm_parameter" "seafile_private_key" {
#   name        = "/seafile/ec2/keypair"
#   description = "Private key for Seafile EC2 instance"
#   type        = "SecureString"
#   value       = tls_private_key.seafile_key.private_key_pem
# }

# # SSM Parameters
# resource "aws_ssm_parameter" "seafile_additional_params" {
#   for_each    = local.seafile_parameters
#   name        = "/seafile/${each.key}"
#   description = each.value.description
#   type        = "SecureString"
#   value       = each.value.value
# }

# # VPC
# module "vpc" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "~> 5.0"

#   name = "seafile-vpc"
#   cidr = "10.0.0.0/16"

#   azs            = var.avz
#   public_subnets = var.public_subnets

#   enable_nat_gateway = false
#   enable_vpn_gateway = false

#   tags = { Name = "seafile-vpc" }
# }

# # S3 Buckets
# resource "aws_s3_bucket" "seafile_buckets" {
#   for_each = local.seafile_buckets
#   bucket   = "seafile-storage-bucket-${each.key}-${random_id.bucket_suffix.hex}"
#   tags     = { Name = each.value }
# }

# resource "random_id" "bucket_suffix" {
#   byte_length = 8
# }

# # Security Group
# resource "aws_security_group" "seafile_sg" {
#   vpc_id = module.vpc.vpc_id
#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   ingress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["113.185.47.255/32"]
#   }
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   tags = { Name = "seafile-sg" }
# }

# # Lambda Role and Policy
# resource "aws_iam_role" "seafile_lambda_role" {
#   name = "SeafileLambdaExecutionRole"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy" "seafile_lambda_policy" {
#   name   = "SeafileLambdaPolicy"
#   role   = aws_iam_role.seafile_lambda_role.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = ["ssm:SendCommand", "ssm:GetCommandInvocation"]
#         Resource = [
#           "*",
#           "*"
#         ]
#       },
#       {
#         Effect   = "Allow"
#         Action   = ["logs:*"]
#         Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
#       },
#       {
#         Effect   = "Allow"
#         Action   = ["ec2:DescribeTags", "ec2:CreateTags"]
#         Resource = "*"
#       }
#     ]
#   })
# }

# # Lambda Function
# data "archive_file" "lambda_zip" {
#   type        = "zip"
#   source_file = "${path.module}/lambda_function.py"
#   output_path = "${path.module}/lambda.zip"
# }

# resource "aws_lambda_function" "seafile_lambda" {
#   filename      = data.archive_file.lambda_zip.output_path
#   function_name = "SetupEC2Lambda"
#   role          = aws_iam_role.seafile_lambda_role.arn
#   handler       = "lambda_function.lambda_handler"
#   runtime       = "python3.9"
#   timeout       = 600

#   environment {
#     variables = {
#       REGION        = var.region
#       EIP_PUBLIC_IP = aws_eip.seafile_eip.public_ip
#       COMMIT_BUCKET = aws_s3_bucket.seafile_buckets["commit"].id
#       FS_BUCKET     = aws_s3_bucket.seafile_buckets["fs"].id
#       BLOCK_BUCKET  = aws_s3_bucket.seafile_buckets["block"].id
#     }
#   }
#   depends_on = [aws_iam_role_policy.seafile_lambda_policy]
# }

# # EventBridge Rule 
# resource "aws_cloudwatch_event_rule" "seafile_setup" {
#   name        = "SeafileSetupRule"
#   description = "Trigger Lambda when any EC2 instance starts"
#   event_pattern = jsonencode({
#     source      = ["aws.ec2"]
#     detail-type = ["EC2 Instance State-change Notification"]
#     detail = {
#       state = ["running"]
#     }
#   })
# }

# resource "aws_lambda_permission" "allow_eventbridge" {
#   statement_id  = "AllowExecutionFromEventBridge"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.seafile_lambda.function_name
#   principal     = "events.amazonaws.com"
#   source_arn    = aws_cloudwatch_event_rule.seafile_setup.arn
# }

# resource "aws_cloudwatch_event_target" "seafile_lambda_target" {
#   rule      = aws_cloudwatch_event_rule.seafile_setup.name
#   target_id = "SeafileLambda"
#   arn       = aws_lambda_function.seafile_lambda.arn
# }

# # EC2 Instance 
# module "ec2" {
#   source  = "terraform-aws-modules/ec2-instance/aws"
#   version = "~> 5.0"

#   name                   = "seafile-instance"
#   ami                    = data.aws_ami.amazon_linux_2.id
#   instance_type          = var.instance_type
#   subnet_id              = module.vpc.public_subnets[0]
#   vpc_security_group_ids = [aws_security_group.seafile_sg.id]
#   key_name               = aws_key_pair.seafile_key_pair.key_name
#   iam_instance_profile   = aws_iam_instance_profile.seafile_instance_profile.name
#   associate_public_ip_address = true

#   root_block_device = [{
#     volume_size           = 300
#     volume_type           = "gp2"
#     delete_on_termination = true
#   }]

#   tags = {
#     Name         = "seafile-instance"
#     SetupPending = "true"
#   }
#   depends_on = [aws_cloudwatch_event_target.seafile_lambda_target]
# }

# # Elastic IP
# resource "aws_eip" "seafile_eip" {
#   domain = "vpc"
#   tags   = { Name = "seafile-eip" }
# }

# resource "aws_eip_association" "seafile_eip_assoc" {
#   instance_id   = module.ec2.id
#   allocation_id = aws_eip.seafile_eip.id
# }