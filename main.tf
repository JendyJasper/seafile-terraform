provider "aws" {
  region = var.region
}

# Get the current AWS account ID
data "aws_caller_identity" "current" {}

# Create an IAM policy for the EC2 instance to access S3
resource "aws_iam_policy" "seafile_s3_access_policy" {
  name        = "SeafileS3AccessPolicy"
  description = "Policy for Seafile EC2 instance to access S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::seafile-storage-bucket-*",
          "arn:aws:s3:::seafile-storage-bucket-*/*"
        ]
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

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "seafile_s3_access_policy_attachment" {
  role       = aws_iam_role.seafile_ec2_role.name
  policy_arn = aws_iam_policy.seafile_s3_access_policy.arn
}

# Create an IAM instance profile for the EC2 instance
resource "aws_iam_instance_profile" "seafile_instance_profile" {
  name = "seafile-instance-profile"
  role = aws_iam_role.seafile_ec2_role.name
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
  name        = "/seafile-key-pair"
  description = "Private key for Seafile EC2 instance"
  type        = "SecureString"
  value       = tls_private_key.seafile_key.private_key_pem
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

# Create the S3 bucket which seafile will use
module "s3" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "seafile-storage-bucket-${random_id.bucket_suffix.hex}"
  tags = {
    Name = "seafile-storage-bucket"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# Fetch the latest Amazon Linux 2 AMI so the code won't fail when the AMI becomes invalid
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
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
  instance_type          = "t2.micro"
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.seafile_sg.id]
  key_name               = aws_key_pair.seafile_key_pair.key_name
  iam_instance_profile   = aws_iam_instance_profile.seafile_instance_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              docker pull seafileltd/seafile:latest
              docker run -d --name seafile -p 80:80 -p 443:443 -v /opt/seafile:/shared seafileltd/seafile:latest
              EOF

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