# ---------------------------------------------------------
# EKS POD IDENTITY AND EBS CSI DRIVER
# ---------------------------------------------------------

# Dedicated IAM role for the EBS CSI controller.
resource "aws_iam_role" "ebs_csi" {
  name        = "${var.cluster_name}-ebs-csi-role"
  description = "EKS Pod Identity role for the AWS EBS CSI controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEbsCsiControllerPodIdentity"
      Effect = "Allow"

      Principal = {
        Service = "pods.eks.amazonaws.com"
      }

      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]

      Condition = {
        StringEquals = {
          "aws:RequestTag/kubernetes-namespace"       = "kube-system"
          "aws:RequestTag/kubernetes-service-account" = "ebs-csi-controller-sa"
        }
      }
    }]
  })

  tags = local.common_tags
}

# AWS-managed, scoped EBS CSI permissions.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role = aws_iam_role.ebs_csi.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

# Install EKS Pod Identity Agent.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.lab.name

  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.4.1-eksbuild.3"

  tags = local.common_tags

  depends_on = [
    aws_eks_node_group.lab
  ]
}

# Install AWS-managed EBS CSI Driver.
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.lab.name

  addon_name    = "aws-ebs-csi-driver"
  addon_version = "v1.68.0-eksbuild.1"

  # Associate the controller service account with its IAM role.
  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  tags = local.common_tags

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.ebs_csi,
    aws_eks_node_group.lab
  ]
}
