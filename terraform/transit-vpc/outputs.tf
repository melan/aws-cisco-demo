output "router-public-ip" {
  value = aws_eip.router-eip.public_ip
}

output "configurator-sg" {
  value = aws_security_group.configurator_sg.id
}

output "router-public-sg" {
  value = aws_security_group.router-public-sg.id
}

output "configurator-subnet" {
  value = aws_subnet.private.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}