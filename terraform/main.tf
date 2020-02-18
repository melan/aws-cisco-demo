locals {
  address_space          = "10.0.0.0/8"
  transit_asn            = 65000
  cisco_csr_product_code = "5tiyrfb5tasxk9gmnab39b843"
}

resource "aws_key_pair" "router-ssh-us-east-1" {
  public_key = var.ssh-public-key
  key_name   = "cisco-demo-router-key"
  provider   = aws.us-east-1
}

resource "aws_secretsmanager_secret" "router-ssh-key" {
  name                    = aws_key_pair.router-ssh-us-east-1.key_name
  recovery_window_in_days = 0
  provider                = aws.us-east-1
}

resource "aws_key_pair" "instance-ssh-us-east-1" {
  public_key = var.ssh-public-key
  key_name   = "cisco-demo-key"
  provider   = aws.us-east-1
}

resource "aws_key_pair" "instance-ssh-us-east-2" {
  public_key = var.ssh-public-key
  key_name   = "cisco-demo-key"
  provider   = aws.us-east-2
}

resource "aws_key_pair" "instance-ssh-us-west-2" {
  public_key = var.ssh-public-key
  key_name   = "cisco-demo-key"
  provider   = aws.us-west-2
}

module "configurator-artifacts" {
  source      = "./configurator-artifacts"
  name_prefix = "cisco-demo-configurator"

  providers = {
    aws = aws.us-east-1
  }
}

module "vpc-1" {
  source                = "./vpc"
  name_prefix           = "cisco-demo-vpc1"
  vpc_cidr              = cidrsubnet(local.address_space, 8, 1)
  asn                   = 65001
  private_address_space = local.address_space
  transit_public_ip     = module.transit-vpc.router-public-ip
  router-public-sg      = module.transit-vpc.router-public-sg
  instance_ssh_key      = aws_key_pair.instance-ssh-us-east-1.key_name
  transit_asn           = local.transit_asn

  providers = {
    aws        = aws.us-east-1
    aws.router = aws.us-east-1
  }
}

module "vpc-2" {
  source                = "./vpc"
  name_prefix           = "cisco-demo-vpc2"
  vpc_cidr              = cidrsubnet(local.address_space, 8, 2)
  asn                   = 65002
  private_address_space = local.address_space
  transit_public_ip     = module.transit-vpc.router-public-ip
  router-public-sg      = module.transit-vpc.router-public-sg
  instance_ssh_key      = aws_key_pair.instance-ssh-us-east-2.key_name
  transit_asn           = local.transit_asn

  providers = {
    aws        = aws.us-east-2
    aws.router = aws.us-east-1
  }
}

module "vpc-3" {
  source                = "./vpc"
  name_prefix           = "cisco-demo-vpc3"
  vpc_cidr              = cidrsubnet(local.address_space, 8, 3)
  asn                   = 65003
  private_address_space = local.address_space
  transit_public_ip     = module.transit-vpc.router-public-ip
  router-public-sg      = module.transit-vpc.router-public-sg
  instance_ssh_key      = aws_key_pair.instance-ssh-us-west-2.key_name
  transit_asn           = local.transit_asn

  providers = {
    aws        = aws.us-west-2
    aws.router = aws.us-east-1
  }
}

module "transit-vpc" {
  source                 = "./transit-vpc"
  name_prefix            = "cisco-demo-transit-vpc"
  vpc_cidr               = cidrsubnet(local.address_space, 8, 0)
  instance_ssh_key       = aws_key_pair.router-ssh-us-east-1.key_name
  cisco_csr_product_code = local.cisco_csr_product_code
  deploy_router          = var.deploy_router

  providers = {
    aws = aws.us-east-1
  }
}

module "configurator" {
  source                         = "./configurator"
  name_prefix                    = "cisco-demo-csr-config"
  artifacts_bucket               = module.configurator-artifacts.artifacts_bucket
  ansible_object                 = module.configurator-artifacts.ansible_object_key
  instance_filter_lambda_object  = module.configurator-artifacts.instance_filter_lambda_object_key
  aws_vpn_regions                = "us-east-1,us-east-2,us-west-2"
  cisco_csr_product_code         = local.cisco_csr_product_code
  configurator_security_group_id = module.transit-vpc.configurator-sg
  management_subnet_id           = module.transit-vpc.configurator-subnet
  private_address_space          = local.address_space
  router_ssh_key                 = aws_secretsmanager_secret.router-ssh-key.name
  vpc_id                         = module.transit-vpc.vpc_id

  providers = {
    aws = aws.us-east-1
  }
}
