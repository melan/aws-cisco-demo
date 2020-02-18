output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "ansible_object_key" {
  value = aws_s3_bucket_object.ansible.key
}

output "instance_filter_lambda_object_key" {
  value = aws_s3_bucket_object.instance-filter-lambda-code.key
}