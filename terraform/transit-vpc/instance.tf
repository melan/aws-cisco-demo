data "aws_ami" "cisco_csr" {
  most_recent = true
  owners      = ["679593333241"]

  filter {
    name   = "name"
    values = ["cisco-CSR*BYOL*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "product-code"
    values = [var.cisco_csr_product_code]
  }
}

resource "aws_security_group" "router-public-sg" {
  name   = "${var.name_prefix}-router-public-sg"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "router-private-sg" {
  name   = "${var.name_prefix}-router-private-sg"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "configurator_sg" {
  name   = "${var.name_prefix}-configurator-sg"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group_rule" "configurator_egress" {
  from_port         = -1
  protocol          = "-1"
  security_group_id = aws_security_group.configurator_sg.id
  to_port           = -1
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "router-ssh-ingress" {
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.router-private-sg.id
  to_port                  = 22
  type                     = "ingress"
  source_security_group_id = aws_security_group.configurator_sg.id
}

resource "aws_network_interface" "nic" {
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.router-private-sg.id, aws_security_group.router-public-sg.id]

  tags = {
    Name = "${var.name_prefix}-router-nic"
  }
}

resource "aws_eip" "router-eip" {
  vpc               = true
  network_interface = aws_network_interface.nic.id

  tags = {
    Name = "${var.name_prefix}-router-eip"
  }
}

resource "aws_instance" "router" {
  count             = var.deploy_router ? 1 : 0
  ami               = data.aws_ami.cisco_csr.id
  instance_type     = "t3.medium"
  key_name          = var.instance_ssh_key
  availability_zone = aws_subnet.public.availability_zone

  network_interface {
    device_index          = 0
    network_interface_id  = aws_network_interface.nic.id
    delete_on_termination = false
  }

  tags = {
    Name = "${var.name_prefix}-router"
  }
}