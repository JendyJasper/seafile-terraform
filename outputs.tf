output "seafile_instance_public_ip" {
  value = module.ec2.public_ip
}

output "seafile_elastic_ip" {
  value = aws_eip.seafile_eip.public_ip
}

output "s3_bucket_name" {
  value = module.s3.s3_bucket_id
}