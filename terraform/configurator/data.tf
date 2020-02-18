data "aws_caller_identity" "me" {}

data "aws_region" "current" {}

data "aws_s3_bucket_object" "ansible_object" {
  bucket = var.artifacts_bucket
  key    = var.ansible_object
}

data "aws_s3_bucket_object" "instance_filter_lambda_object" {
  bucket = var.artifacts_bucket
  key    = var.instance_filter_lambda_object
}

data "aws_secretsmanager_secret" "router-ssh-key" {
  name = var.router_ssh_key
}

data "aws_vpc" "transit" {
  id = var.vpc_id
}

data "aws_subnet" "management_subnet" {
  id = var.management_subnet_id
}

data "aws_security_group" "configurator_sg" {
  id = var.configurator_security_group_id
}