data "aws_region" "current" {}

data "aws_availability_zones" "zones" {
  state = "available"
}

data "aws_security_group" "router_public_sg" {
  id       = var.router-public-sg
  provider = aws.router
}