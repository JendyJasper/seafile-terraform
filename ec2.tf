# IAM Policy for EC2 (S3 and SSM access)
resource "aws_iam_policy" "seafile_s3_and_ssm_access_policy" {
  name        = "SeafileS3AndSSMAccessPolicy"
  description = "Policy for Seafile EC2 instance to access S3 and SSM parameters under /seafile/*"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["arn:aws:s3:::seafile-storage-bucket-*", "arn:aws:s3:::seafile-storage-bucket-*/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:*"]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/seafile/*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/seafile-service-account"
      }
    ]
  })
}

# IAM Role for EC2
resource "aws_iam_role" "seafile_ec2_role" {
  name = "SeafileEC2Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "seafile_s3_and_ssm_access_policy_attachment" {
  role       = aws_iam_role.seafile_ec2_role.name
  policy_arn = aws_iam_policy.seafile_s3_and_ssm_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.seafile_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "seafile_instance_profile" {
  name = "seafile-instance-profile"
  role = aws_iam_role.seafile_ec2_role.name
}

# EC2 Key Pair
resource "aws_key_pair" "seafile_key_pair" {
  key_name   = "seafile-key-pair"
  public_key = tls_private_key.seafile_key.public_key_openssh
}

# EC2 Instance
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

  root_block_device = [{
    volume_size           = 300
    volume_type           = "gp2"
    delete_on_termination = true
  }]

  tags = {
    Name         = "seafile-instance"
    SetupPending = "true"
  }
  depends_on = [aws_cloudwatch_event_target.seafile_lambda_target]
}

# Elastic IP
resource "aws_eip" "seafile_eip" {
  domain = "vpc"
  tags   = { Name = "seafile-eip" }
}

resource "aws_eip_association" "seafile_eip_assoc" {
  instance_id   = module.ec2.id
  allocation_id = aws_eip.seafile_eip.id
}