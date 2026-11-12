# Terraform EKS plan-only preparation kit

This kit creates **no** AWS infrastructure. It adds an isolated `infra/eks/` Terraform project and scripts for preparing and reviewing a plan. **Do not run `terraform apply` until a separate cost, permissions and security review is complete.**

## Design

- Region: `eu-north-1` (Stockholm).
- Existing default VPC and the three public subnets that passed the 12 Nov 2026 preflight. Does not create/destroy VPC, NAT gateways or subnets.
- EKS version 1.36, STANDARD support (no extended support charges while version is supported).
- Managed EC2 node group: starts at **one** `t3.large` on-demand instance, AL2023, 30 GiB disk; configurable up to three nodes for workload sizing.
- EKS API endpoint: **public access from a single user-controlled IPv4 /32 only**, private endpoint enabled for VPC communication. Dynamic client IPs need manual updates. GitHub-hosted runners **cannot deploy** without designing controlled API connectivity; do not broaden to `0.0.0.0/0` just to fix CI.
- IAM roles with AWS-managed policies. For this small lab, node role also gets AmazonEKS_CNI_Policy; later move it to a dedicated service-account role for least privilege.
- Uses existing AWS browser-login credentials via a separate `terraform-process` credential_process profile, not static access keys.
- No load balancers, NAT gateways, EBS CSI driver, EBS volumes for application PVCs, ECR repositories, Kubernetes workloads, or DNS records are created at this stage. Future workloads, service exposure and storage can add charges.

## 1. Extract the zip in the repo root

```
cd ~/projects/devops-capstone/example-voting-app
unzip -n ~/Downloads/devops_capstone_terraform_plan_kit.zip
```

## 2. Create the Terraform AWS profile once

```
aws configure set credential_process \
  'aws configure export-credentials --profile default --format process' \
  --profile terraform-process
aws configure set region eu-north-1 --profile terraform-process
aws sts get-caller-identity --profile terraform-process
```

This does not save a permanent access key. Never print, paste or commit `aws configure export-credentials` output. If AWS authentication expires, refresh with `aws login --profile default`.

## 3. Configure local-only Terraform variables

```
bash scripts/prepare_eks_plan_inputs.sh
```

The script retrieves your current public IPv4 via AWS's checkip service and creates `infra/eks/terraform.tfvars` (Git-ignored and mode 600). Review it, including the region, VPC ID, subnets, chosen node size and node count. If IP discovery fails, copy the example and replace the placeholder manually.

## 4. Read-only Terraform plan

```
bash scripts/plan_eks_only.sh
```

This invokes `terraform init -backend=false`, `fmt -check`, `validate`, and `plan`, with an AWS budget and identity check. `init` downloads provider plugins locally; `plan` reads AWS metadata but **does not provision infrastructure**. A binary `tfplan` file remains in the ignored directory. Don't share it publicly: Terraform plan and state can contain sensitive values.

If `fmt -check` fails, run `terraform -chdir=infra/eks fmt -recursive`, then rerun the plan. The files were prepared without live provider initialization in this environment, so local validation is required.

Review with `terraform -chdir=infra/eks show -no-color tfplan`. In an empty state expect the EKS cluster, node group, two IAM roles, and four IAM policy attachments (8 resources), plus data-source reads. Do not interpret a plan as proof that AWS will accept quota/capacity/permissions when applying.

## 5. Cost approval is a separate gate

AWS EKS standard control-plane fee is currently **$0.10/hour**, or **$2.40/day**, regardless of nodes. EC2 `t3.large` on-demand, 30 GiB EBS, public IPv4 ($0.005/hour per IP), service load balancers, storage, data transfer and CloudWatch usage are additional. Your **$25 monthly AWS Budget only sends alerts** and billing updates may be delayed. Verify current Stockholm-region unit prices in AWS Pricing Calculator; decide exact hours needed for capstone evidence, then destroy promptly.

Do not apply or destroy without a deliberate review of the Terraform state and confirmation of cost exposure. After any eventual deployment, capture the required screenshots before destroying it. A later stage will plan the teardown and recreation proof.

## 6. Version control

Add and commit only the code and provider lockfile:

```
git add infra/eks/versions.tf infra/eks/variables.tf infra/eks/main.tf \
  infra/eks/outputs.tf infra/eks/terraform.tfvars.example infra/eks/.gitignore \
  scripts/prepare_eks_plan_inputs.sh scripts/plan_eks_only.sh
# After terraform init, stage infra/eks/.terraform.lock.hcl as well.
git diff --cached --check
```

Do **not** add `infra/eks/terraform.tfvars`, `infra/eks/tfplan`, `.terraform/`, Terraform state, or AWS credentials.
