provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket         = "terraform-state-seafile"
    key            = "seafile-terraform/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-locks"
  }
}

# Create an IAM policy for S3 and full SSM access (for EC2 role)
resource "aws_iam_policy" "seafile_s3_and_ssm_access_policy" {
  name        = "SeafileS3AndSSMAccessPolicy"
  description = "Policy for Seafile EC2 instance to access S3 and all SSM parameters under /seafile/*"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::seafile-storage-bucket-*",
          "arn:aws:s3:::seafile-storage-bucket-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["ssm:*"]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/seafile/*"
      }
    ]
  })
}

# Create an IAM role for the EC2 instance
resource "aws_iam_role" "seafile_ec2_role" {
  name = "SeafileEC2Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach the S3 and SSM policy to the EC2 role
resource "aws_iam_role_policy_attachment" "seafile_s3_and_ssm_access_policy_attachment" {
  role       = aws_iam_role.seafile_ec2_role.name
  policy_arn = aws_iam_policy.seafile_s3_and_ssm_access_policy.arn
}

# Create an IAM instance profile for the EC2 instance
resource "aws_iam_instance_profile" "seafile_instance_profile" {
  name = "seafile-instance-profile"
  role = aws_iam_role.seafile_ec2_role.name
}

# Create an IAM user for Seafile service account
resource "aws_iam_user" "seafile_service_account" {
  name = "seafile-service-account"
  tags = {
    Name = "Seafile Service Account"
  }
}

# Create an access key for the IAM user
resource "aws_iam_access_key" "seafile_service_account_key" {
  user = aws_iam_user.seafile_service_account.name
}

# Store the access key and secret key in Parameter Store
resource "aws_ssm_parameter" "seafile_iam_credentials" {
  name        = "/seafile/iam_user/credentials"
  description = "IAM credentials for Seafile service account"
  type        = "SecureString"
  value = jsonencode({
    access_key_id     = aws_iam_access_key.seafile_service_account_key.id
    secret_access_key = aws_iam_access_key.seafile_service_account_key.secret
  })
}

# Create a new S3 policy for the service account
resource "aws_iam_policy" "seafile_service_account_s3_policy" {
  name        = "SeafileServiceAccountS3Policy"
  description = "Policy for Seafile service account to access S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::seafile-storage-bucket-*",
          "arn:aws:s3:::seafile-storage-bucket-*/*"
        ]
      }
    ]
  })
}

# Attach the new S3 policy to the service account
resource "aws_iam_user_policy_attachment" "seafile_service_account_s3_policy_attachment" {
  user       = aws_iam_user.seafile_service_account.name
  policy_arn = aws_iam_policy.seafile_service_account_s3_policy.arn
}

# Generate a key pair for the EC2 instance
resource "tls_private_key" "seafile_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "seafile_key_pair" {
  key_name   = "seafile-key-pair"
  public_key = tls_private_key.seafile_key.public_key_openssh
}

# Store the private key in AWS SSM Parameter Store
resource "aws_ssm_parameter" "seafile_private_key" {
  name        = "/seafile/ec2/keypair"
  description = "Private key for Seafile EC2 instance"
  type        = "SecureString"
  value       = tls_private_key.seafile_key.private_key_pem
}

# Store additional parameters in AWS SSM Parameter Store
resource "aws_ssm_parameter" "seafile_additional_params" {
  for_each = local.seafile_parameters

  name        = "/seafile/${each.key}"
  description = each.value.description
  type        = "SecureString"
  value       = each.value.value
}

# Create the VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "seafile-vpc"
  cidr = "10.0.0.0/16"

  azs             = var.avz
  public_subnets  = ["10.0.1.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Name = "seafile-vpc"
  }
}

# Create S3 buckets
resource "aws_s3_bucket" "seafile_buckets" {
  for_each = local.seafile_buckets

  bucket = "seafile-storage-bucket-${each.key}-${random_id.bucket_suffix.hex}"
  tags = {
    Name = each.value
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# Create a security group for the EC2 instance
resource "aws_security_group" "seafile_sg" {
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["113.185.47.255/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "seafile-sg"
  }
}

# Create the EC2 instance
module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name                   = "seafile-instance"
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.seafile_sg.id]
  key_name               = aws_key_pair.seafile_key_pair.key_name
  iam_instance_profile   = aws_iam_instance_profile.seafile_instance_profile.name
  associate_public_ip_address = true

  root_block_device = [
    {
      volume_size          = 300
      volume_type          = "gp2"
      delete_on_termination = true
    }
  ]

  tags = {
    Name = "seafile-instance"
  }
}

# Create an Elastic IP
resource "aws_eip" "seafile_eip" {
  domain = "vpc"
  tags = {
    Name = "seafile-eip"
  }
}

# Associate the Elastic IP with the EC2 instance
resource "aws_eip_association" "seafile_eip_assoc" {
  instance_id   = module.ec2.id
  allocation_id = aws_eip.seafile_eip.id
}