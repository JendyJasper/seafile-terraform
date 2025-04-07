# S3 Buckets
resource "aws_s3_bucket" "seafile_buckets" {
  for_each = local.seafile_buckets
  bucket   = "seafile-storage-bucket-${each.key}-${random_id.bucket_suffix.hex}"
  tags     = { Name = each.value }
}

# Enable versioning for each Seafile bucket
resource "aws_s3_bucket_versioning" "seafile_buckets_versioning" {
  for_each = aws_s3_bucket.seafile_buckets

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Policy for Seafile Service Account S3 Access
resource "aws_iam_policy" "seafile_service_account_s3_policy" {
  name        = "SeafileServiceAccountS3Policy"
  description = "Policy for Seafile service account to access S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["arn:aws:s3:::seafile-storage-bucket-*", "arn:aws:s3:::seafile-storage-bucket-*/*"]
    }]
  })
}

resource "aws_iam_user_policy_attachment" "seafile_service_account_s3_policy_attachment" {
  user       = aws_iam_user.seafile_service_account.name
  policy_arn = aws_iam_policy.seafile_service_account_s3_policy.arn
}