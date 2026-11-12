# Capstone AWS infrastructure preflight — design only

**Status:** proposed, not provisioned. No EKS cluster or EC2 workers are created by the accompanying scripts.

## Account and region

- AWS CLI profile: `default` (overridable with `AWS_PROFILE`).
- Deployment region: `eu-north-1` (Stockholm), overridable with `AWS_REGION`.
- Network: use the existing **default VPC**; verify ID and exact subnets at runtime. Do not hardcode the VPC identifier: obtain it from the read-only account check.
- Kubernetes: EKS `1.36`, subject to availability/standard-support verification (matches the local `kubectl` 1.36 minor version).

## Proposed lower-cost lab topology

- One standard-support EKS control plane. Avoid extended support and Auto Mode charges unless explicitly required.
- EKS managed EC2 node group in **two existing public subnets in different AZs** with IGW routes and automatic public IPs. Start with desired capacity 2, max 3; consider `t3.large` as a test candidate, but check quotas and actual pricing first. The Robot Shop observability workload may need more memory than the Voting App.
- No new VPC, NAT gateway, bastion, Elastic IP, or ALB by default. These avoid extra resource classes, but EC2 compute, disks and public IPv4 addresses remain billable.
- SSH inbound disabled; prefer SSM if required. Restrict the EKS API public endpoint to the operator's current public IPv4 `/32` and also enable private endpoint access for nodes.
- **CI/CD caveat:** GitHub-hosted runner egress IPs are dynamic. A workstation-only EKS endpoint CIDR does not permit hosted runner `kubectl/helm` access. Decide on an approved runner/deployment architecture before implementing GitHub Actions deployment (e.g. a secured self-hosted runner in the VPC, or a reviewed temporary /32 allowlisting mechanism). Do not open the API to the world just to make CI work.
- Use Kubernetes secrets/external secret provider, not literal passwords in Git or Terraform state. Keep the Terraform backend and state secure; state may contain sensitive data.
- Scope Helm deployments to the capstone services; use EBS CSI and gp3 only where persistence is required, with deletion policy checked before destruction.
- Review cluster and node IAM roles, OIDC/Pod Identity and storage permissions; don't use long-lived AWS keys in GitHub Actions. Prefer OIDC.

## Cost risk and authorization gate

Published EKS **standard** control-plane pricing is USD $0.10/hour, approximately $2.40/day or $72 for 30 days per cluster, **before** compute and other services. EC2 nodes, EBS, in-use public IPv4 ($0.005 per IP-hour at the published VPC rate), data transfer and load balancers can add costs. A $30 monthly budget is an **alert threshold**, not a usable guarantee of a full-month EKS deployment. Budget data and notifications may be delayed.

Never run `terraform apply` without all of the following:

1. `scripts/aws_budget_guard.sh` confirms an email-alert budget exists and the alert destination is correct.
2. `scripts/aws_readonly_preflight.sh` passes VPC, subnet, DNS, EKS-version and budget checks.
3. Terraform code and `terraform plan` have been reviewed for resources, quotas, and expected hourly cost (especially NAT, load balancers, EC2, EBS and EKS control planes).
4. A specific destruction/checkpoint plan is set (`terraform destroy` when the exercise is finished, confirm resource deletion, capture screenshots and proof).
5. User explicitly approves chargeable resource creation.

## Evidence

Capture redacted CLI preflight output, budget name/threshold and notification configuration, infrastructure architecture diagram, Terraform plan summary, apply and destroy proof. **Never commit AWS account identifiers, email addresses, tokens, credential files, Terraform state, or live secrets.**

## Reference sources

- EKS pricing: https://aws.amazon.com/eks/pricing/
- EKS versions: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- EKS endpoint controls: https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
- VPC/public IPv4 pricing: https://aws.amazon.com/vpc/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
