output "seafile_elastic_ip" {
  value = aws_eip.seafile_eip.public_ip
}

output "s3_commit_bucket_name" {
  value = module.s3-commit.s3_bucket_id
}

output "s3_fs_bucket_name" {
  value = module.s3-fs.s3_bucket_id
}

output "s3_block_bucket_name" {
  value = module.s3-block.s3_bucket_id
}