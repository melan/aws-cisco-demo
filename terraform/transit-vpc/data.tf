data "aws_region" "current" {}

data "aws_caller_identity" "me" {}

data "aws_availability_zones" "zones" {
  state = "available"
}