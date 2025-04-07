# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "seafile-vpc"
  cidr = "10.0.0.0/16"

  azs            = var.avz
  public_subnets = var.public_subnets

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = { Name = "seafile-vpc" }
}

# Security Group
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
  tags = { Name = "seafile-sg" }
}