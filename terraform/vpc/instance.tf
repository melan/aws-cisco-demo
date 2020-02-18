data "aws_ami" "amzn_linux2" {
  owners      = ["137112412989"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_security_group" "instance-sg" {
  name   = "${var.name_prefix}-instance-nic"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group_rule" "instance-inbound-icmp" {
  from_port         = -1
  protocol          = "icmp"
  security_group_id = aws_security_group.instance-sg.id
  to_port           = -1
  type              = "ingress"
  cidr_blocks       = [var.private_address_space]
}

resource "aws_security_group_rule" "instance-egress" {
  from_port         = -1
  protocol          = "-1"
  security_group_id = aws_security_group.instance-sg.id
  to_port           = -1
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_network_interface" "instance-nic" {
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.instance-sg.id]

  tags = {
    Name = "${var.name_prefix}-instance-nic"
  }
}

resource "aws_instance" "bastion" {
  ami               = data.aws_ami.amzn_linux2.id
  instance_type     = "t3.micro"
  key_name          = var.instance_ssh_key
  availability_zone = aws_subnet.private.availability_zone

  network_interface {
    device_index          = 0
    network_interface_id  = aws_network_interface.instance-nic.id
    delete_on_termination = false
  }

  tags = {
    Name = "${var.name_prefix}-instance"
  }
}