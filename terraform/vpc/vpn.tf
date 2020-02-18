resource "aws_vpn_gateway" "vgw" {
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.zones.names[0]
  amazon_side_asn   = var.asn

  tags = {
    Name = "${var.name_prefix}-vpn-gw"
  }
}

resource "aws_customer_gateway" "transit-cgw" {
  bgp_asn    = var.transit_asn
  ip_address = var.transit_public_ip
  type       = "ipsec.1"

  tags = {
    Name = "${var.name_prefix}-transit-cgw"
  }
}

resource "aws_vpn_connection" "transit-connection" {
  vpn_gateway_id      = aws_vpn_gateway.vgw.id
  customer_gateway_id = aws_customer_gateway.transit-cgw.id
  type                = aws_customer_gateway.transit-cgw.type

  tags = {
    Name = "${var.name_prefix}-transit-vpn-connection"
  }
}

resource "aws_vpn_gateway_route_propagation" "private" {
  route_table_id = aws_route_table.private.id
  vpn_gateway_id = aws_vpn_gateway.vgw.id
}

resource "aws_security_group_rule" "router_egress_500" {
  from_port         = 500
  protocol          = "udp"
  security_group_id = data.aws_security_group.router_public_sg.id
  to_port           = 500
  type              = "egress"
  cidr_blocks = [
    "${aws_vpn_connection.transit-connection.tunnel1_address}/32",
    "${aws_vpn_connection.transit-connection.tunnel2_address}/32",
  ]
  provider = aws.router
}

resource "aws_security_group_rule" "router_egress_4500" {
  from_port         = 4500
  protocol          = "udp"
  security_group_id = data.aws_security_group.router_public_sg.id
  to_port           = 4500
  type              = "egress"
  cidr_blocks = [
    "${aws_vpn_connection.transit-connection.tunnel1_address}/32",
    "${aws_vpn_connection.transit-connection.tunnel2_address}/32",
  ]
  provider = aws.router
}

resource "aws_security_group_rule" "router_ingress_500" {
  from_port         = 500
  protocol          = "udp"
  security_group_id = data.aws_security_group.router_public_sg.id
  to_port           = 500
  type              = "ingress"
  cidr_blocks = [
    "${aws_vpn_connection.transit-connection.tunnel1_address}/32",
    "${aws_vpn_connection.transit-connection.tunnel2_address}/32",
  ]
  provider = aws.router
}

resource "aws_security_group_rule" "router_ingress_4500" {
  from_port         = 4500
  protocol          = "udp"
  security_group_id = data.aws_security_group.router_public_sg.id
  to_port           = 4500
  type              = "ingress"
  cidr_blocks = [
    "${aws_vpn_connection.transit-connection.tunnel1_address}/32",
    "${aws_vpn_connection.transit-connection.tunnel2_address}/32",
  ]
  provider = aws.router
}