variable "aws_region" {
  type        = string
  description = "AWS region verified by the preflight script."
  default     = "eu-north-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI credential_process profile that bridges browser-based login to Terraform."
  default     = "terraform-process"
}

variable "cluster_name" {
  type        = string
  description = "Temporary EKS lab name."
  default     = "devops-capstone-eks"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS standard-support Kubernetes version."
  default     = "1.36"
}

variable "vpc_id" {
  type        = string
  description = "Existing default VPC: Terraform will not create or destroy the VPC."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Existing public subnets across at least two AZs."

  validation {
    condition     = length(distinct(var.public_subnet_ids)) >= 2
    error_message = "At least two distinct existing subnet IDs are required."
  }
}

variable "public_api_cidr" {
  type        = string
  description = "Your current public IPv4 address as a /32. Do not use 0.0.0.0/0."

  validation {
    condition = (
      can(cidrnetmask(var.public_api_cidr)) &&
      endswith(var.public_api_cidr, "/32") &&
      var.public_api_cidr != "0.0.0.0/0"
    )
    error_message = "Specify exactly one public IPv4 /32 (for example the IP returned by checkip.amazonaws.com)."
  }
}

variable "node_instance_type" {
  type        = string
  description = "On-demand EC2 instance size; cost review is required before applying."
  default     = "m7i-flex.large"
}

variable "node_desired_size" {
  type        = number
  description = "Initial node count: start with one to reduce cost; increase when workload capacity requires."
  default     = 1

  validation {
    condition     = contains([1, 2, 3], var.node_desired_size)
    error_message = "Node count for this lab must be 1, 2, or 3."
  }
}


variable "additional_public_api_cidrs" {
  description = "Additional restricted public API source CIDRs"
  type        = list(string)
  default     = []
}
