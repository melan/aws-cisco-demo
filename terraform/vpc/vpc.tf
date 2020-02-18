resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 0)
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.zones.names[0]

  tags = {
    Name = "${var.name_prefix}-public-subnet"
  }
}

resource "aws_subnet" "private" {
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 1)
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.zones.names[0]

  tags = {
    Name = "${var.name_prefix}-private-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_eip" "nat-eip" {
  vpc = true

  tags = {
    Name = "${var.name_prefix}-ngw-eip"
  }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat-eip.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.name_prefix}-ngw"
  }
}

