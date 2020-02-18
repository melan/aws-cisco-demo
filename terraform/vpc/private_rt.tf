resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route" "private-to-internet" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw.id
}

resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private.id
}

