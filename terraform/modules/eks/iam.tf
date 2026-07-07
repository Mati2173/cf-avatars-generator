# ==========================================
# 1. IAM ROLE PARA EL CONTROL PLANE (CLUSTER)
# ==========================================

# Política de Confianza: Le dice a AWS "Permito que el servicio EKS asuma este rol"
data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "eks-cluster-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

# Política Administrada por AWS: Le da permiso a EKS para administrar ENIs, Load Balancers, etc.
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}


# ==========================================
# 2. IAM ROLE PARA LOS WORKER NODES (EC2)
# ==========================================

# Política de Confianza: Le dice a AWS "Permito que instancias EC2 asuman este rol"
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node_group" {
  name               = "eks-nodegroup-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Política Administrada 1: Permite a los workers registrarse en el clúster
resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

# Política Administrada 2: Plugin CNI de VPC. Permite a los workers pedir IPs privadas a la VPC para dárselas a los Pods.
resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

# Política Administrada 3: Permite a los workers descargar imágenes de Docker desde Amazon ECR (si lo usáramos)
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# ==========================================
# 3. OIDC PROVIDER PARA EKS (IRSA)
# ==========================================
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ==========================================
# 4. IAM ROLE PARA EBS CSI DRIVER (IRSA)
# ==========================================
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "ebs-csi-irsa-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

# Política Administrada 4: Permite al rol del CSI Driver administrar discos EBS
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}
