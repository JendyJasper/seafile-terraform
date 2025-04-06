output "seafile_elastic_ip" {
  value = aws_eip.seafile_eip.public_ip
}

output "seafile_s3_buckets" {
  value = { for key, bucket in aws_s3_bucket.seafile_buckets : key => bucket.id }
  description = "Map of Seafile S3 bucket names (commit, fs, block)"
}

# output "rotate_keys_lambda_name" {
#   description = "Name of the RotateKeysLambda function"
#   value       = aws_lambda_function.rotate_keys_lambda.function_name
# }