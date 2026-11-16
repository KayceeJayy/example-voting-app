output "cluster_name" {
  description = "EKS cluster name after apply."
  value       = aws_eks_cluster.lab.name
}

output "cluster_endpoint" {
  description = "EKS Kubernetes API endpoint after apply."
  value       = aws_eks_cluster.lab.endpoint
}

output "node_group_name" {
  value = aws_eks_node_group.lab.node_group_name
}

output "vpc_id" {
  value = data.aws_vpc.existing.id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --profile ${var.aws_profile}"
}

output "ebs_csi_iam_role_arn" {
  description = "IAM role assigned to the EBS CSI controller."
  value       = aws_iam_role.ebs_csi.arn
}

output "pod_identity_agent_version" {
  description = "Installed EKS Pod Identity Agent version."
  value       = aws_eks_addon.pod_identity_agent.addon_version
}

output "ebs_csi_driver_version" {
  description = "Installed AWS EBS CSI Driver version."
  value       = aws_eks_addon.ebs_csi_driver.addon_version
}
