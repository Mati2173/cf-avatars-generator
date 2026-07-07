output "vpc_id" {
  description = "El ID de la VPC creada"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Lista de IDs de las subredes públicas"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "Lista de IDs de las subredes privadas"
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "igw_id" {
  description = "ID del Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID del NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "public_route_table_id" {
  description = "ID de la tabla de ruteo pública"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID de la tabla de ruteo privada"
  value       = aws_route_table.private.id
}
