#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="terraform-process"
REGION="eu-north-1"
TF_DIR="$ROOT/infra/eks"

command -v aws >/dev/null || { echo 'ERROR: aws CLI not found'; exit 1; }
command -v terraform >/dev/null || { echo 'ERROR: terraform not found'; exit 1; }
command -v python3 >/dev/null || { echo 'ERROR: python3 not found'; exit 1; }
[[ -f "$TF_DIR/terraform.tfvars" ]] || { echo 'ERROR: Run scripts/prepare_eks_plan_inputs.sh first'; exit 1; }

printf '===== AWS TEMPORARY IDENTITY CHECK =====\n'
ACCOUNT_ID="$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query Account --output text)"
[[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo 'ERROR: AWS identity invalid'; exit 1; }
echo 'PASS: Authenticated with terraform-process profile.'

printf '===== AWS BUDGET GUARD =====\n'
BUDGET_JSON="$(aws budgets describe-budget --profile "$PROFILE" --region us-east-1 --account-id "$ACCOUNT_ID" --budget-name 'DevOps-Capstone-Monthly' --output json)"
python3 -c 'import json,sys; b=json.load(sys.stdin)["Budget"]; amount=float(b["BudgetLimit"]["Amount"]); assert b["BudgetLimit"]["Unit"]=="USD" and b["TimeUnit"]=="MONTHLY" and amount>0; print(f"PASS: Existing USD {amount:g}/month budget verified (alerts, NOT a hard cap).")' <<< "$BUDGET_JSON"

printf '===== TERRAFORM INIT / VALIDATE / PLAN =====\n'
terraform -chdir="$TF_DIR" init -backend=false -input=false
terraform -chdir="$TF_DIR" fmt -check -recursive
terraform -chdir="$TF_DIR" validate
terraform -chdir="$TF_DIR" plan -input=false -out=tfplan

printf '===== PLANNED RESOURCES =====\n'
terraform -chdir="$TF_DIR" show -json tfplan | python3 -c 'import json,sys,collections; p=json.load(sys.stdin); a=collections.Counter("/".join(c["change"]["actions"]) for c in p.get("resource_changes",[])); print(dict(a)); print("NO RESOURCES CREATED. terraform apply intentionally not invoked.")'
printf '\nSTOP: Review the plan, obtain a regional cost estimate, and explicitly approve charges before terraform apply.\n'
