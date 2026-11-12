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
