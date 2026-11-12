# Capstone safeguard kit

Extract this archive into the **root of your existing** `example-voting-app` repo. It adds scripts and AWS notes without overwriting your project README or current Dockerfiles. Only the lock script edits `vote/Dockerfile`, and only when you run it.

## 1. Pin Python production dependencies

```bash
bash scripts/lock_vote_dependencies.sh
```

The script uses your already-tested local image `vote-secure:local` to create `vote/requirements-prod.lock`, changes **only the final** stage of `vote/Dockerfile`, rebuilds, checks versions, runs a HIGH/CRITICAL Trivy gate, and runs a Docker smoke test on 127.0.0.1:18088. Docker Compose Redis must be running.

Inspect and commit when successful:

```bash
git diff --check
git diff -- vote/Dockerfile
cat vote/requirements-prod.lock
git add vote/Dockerfile vote/requirements-prod.lock docs/security/vote-trivy-pinned.json
git diff --cached --check && git commit -m 'build: pin verified Vote Python dependencies'
```

## 2. Configure or inspect AWS budget (explicit approval required)

```bash
bash scripts/aws_budget_guard.sh
```

The script checks existing budgets and, only if the named budget does not exist, prompts for your **monthly USD limit, email**, and typed `yes` to create an account-wide COST budget with four ACTUAL spend alerts. It does not create EKS or EC2 resources.

If it finds an existing budget, verify the email subscribers through the AWS Billing console; it will **not** silently modify it.

## 3. Verify infrastructure prerequisites (read-only)

```bash
bash scripts/aws_readonly_preflight.sh
```

It checks the default VPC, subnets, routes, IGW, DNS, EKS 1.36 standard support, existing clusters, and budgets. An IAM denial or missing prerequisite means **do not proceed with Terraform apply**.

## 4. Preserve files in Git

```bash
git add scripts/lock_vote_dependencies.sh scripts/aws_budget_guard.sh scripts/aws_readonly_preflight.sh docs/aws/INFRASTRUCTURE_DESIGN.md
git diff --cached --check && git commit -m 'chore: add AWS cost and infrastructure preflight safeguards'
```

**Security:** Do not commit terminal transcripts containing the complete AWS account ID, budget subscriber emails, Terraform state files or credentials. The scripts do not save account-specific results into the repository.

**Limitations:** AWS Budgets alerts are not a hard spending cap. No AWS infrastructure is provisioned by this kit; an account-connected AWS CLI run is required to verify the user's live AWS account.
