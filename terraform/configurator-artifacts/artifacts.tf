resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name_prefix}-artifacts"
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    enabled = true
    id      = "non-last-version"

    noncurrent_version_expiration {
      days = 2
    }
  }
}

data "archive_file" "ansible-code" {
  type        = "zip"
  source_dir  = "${path.module}/../../code/ansible/build"
  output_path = "${path.module}/archives/ansible.zip"
}

data "archive_file" "instance-filter-lambda-code" {
  type        = "zip"
  source_dir  = "${path.module}/../../code/instance-filter-lambda/build"
  output_path = "${path.module}/archives/instance-filter-lambda.zip"
}

resource "aws_s3_bucket_object" "ansible" {
  bucket = aws_s3_bucket.artifacts.bucket
  key    = "code/ansible.zip"
  source = data.archive_file.ansible-code.output_path
  etag   = data.archive_file.ansible-code.output_md5
}

resource "aws_s3_bucket_object" "instance-filter-lambda-code" {
  bucket = aws_s3_bucket.artifacts.bucket
  key    = "code/instance-filter-lambda.zip"
  source = data.archive_file.instance-filter-lambda-code.output_path
  etag   = data.archive_file.instance-filter-lambda-code.output_md5
}