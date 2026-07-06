# ==========================================
# 1. EL CONTROL PLANE (CLUSTER)
# ==========================================
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-cluster"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.30" # Buena práctica: fijar la versión de K8s

  vpc_config {
    # El cluster necesita conocer todas las subredes (públicas y privadas) 
    # para inyectar ENIs y saber dónde colocar Load Balancers en el futuro.
    subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)
    
    # Práctica de seguridad: El API Server es accesible desde internet (para que podamos usar kubectl desde nuestra laptop), 
    # pero los Workers solo hablan por la red privada.
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Configuramos la API moderna de autenticación de EKS (Adiós aws-auth ConfigMap)
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Habilitamos logs del Control Plane hacia CloudWatch (Cero overhead en Workers)
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Terraform debe esperar a que el rol tenga permisos antes de intentar crear el clúster
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# ==========================================
# 2. EL DATA PLANE (NODE GROUPS / WORKERS)
# ==========================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-node-group"
  node_role_arn   = aws_iam_role.node_group.arn

  # MUY IMPORTANTE: Los workers SOLO viven en las subredes privadas.
  subnet_ids = var.private_subnet_ids

  # Tamaño de instancia reducido (Restricción Free Tier)
  instance_types = ["t3.micro"]

  scaling_config {
    desired_size = 2 # Uno en cada zona de disponibilidad
    max_size     = 3
    min_size     = 1
  }

  # Terraform debe esperar a que el clúster exista y que el rol tenga los permisos necesarios
  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_readonly
  ]
}
