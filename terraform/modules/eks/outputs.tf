output "cluster_name" {
  description = "Nombre del clúster de EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint del API Server del clúster"
  value       = aws_eks_cluster.main.endpoint
}
