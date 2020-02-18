variable "name_prefix" {}

variable "vpc_cidr" {}

variable "instance_ssh_key" {}

variable "cisco_csr_product_code" {}

variable "deploy_router" {
  default = true
}
