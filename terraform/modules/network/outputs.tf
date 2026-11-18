output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.db[*].id
}

output "subnet_cidrs" {
  value = {
    public = aws_subnet.public[*].cidr_block
    app    = aws_subnet.app[*].cidr_block
    db     = aws_subnet.db[*].cidr_block
  }
}

output "nat_gateway_count" {
  value = length(aws_nat_gateway.this)
}

output "public_subnets_assign_public_ip" {
  value = anytrue(aws_subnet.public[*].map_public_ip_on_launch)
}

output "interface_endpoint_services" {
  value = sort(keys(aws_vpc_endpoint.interface))
}

output "flow_log_traffic_type" {
  value = aws_flow_log.this.traffic_type
}
