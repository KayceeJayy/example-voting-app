# Voting Application — Helm deployment workflow

This chart is designed for the tested five-component `dockersamples/example-voting-app` fork and a temporary one-node AWS EKS lab. It is **not** a production-ready, durable data system.

## What this chart does

- 5 Kubernetes `Deployment`s: `vote`, `redis`, `worker`, `db`, `result`
- 4 internal-only `ClusterIP` Services: `vote`, `redis`, `db`, `result`
- 1 Kubernetes Secret for PostgreSQL's *known demo credential* (`postgres`)
- Configurable Git-SHA-tagged image references for Vote, Worker, Results
- Non-root runtime for all five containers, resource requests/limits, web and database probes, `emptyDir` data volumes
- No LoadBalancer, NodePort, Ingress, EBS volume, or additional AWS resource from this chart itself

> **Crucial limitation:** The upstream Worker and Results source uses `postgres/postgres` directly in its database connection strings. Storing the same demo password in a Kubernetes Secret does not fix that hardcoded credential. Keep this a closed lab and change the source, rebuild, rescan, and rotate passwords before any real-world use.

The application source uses DNS names `redis` and `db`, so this chart intentionally creates those exact services. Install **one** release per namespace.

`emptyDir` storage is temporary. Restarting a PostgreSQL or Redis Pod loses data, and Helm rollback does not restore data. Database persistence requires a separate PVC/EBS CSI design.

## 1. Safe local checks (no AWS changes)

```bash
cd ~/projects/devops-capstone/example-voting-app
bash scripts/validate_voting_helm.sh
helm template capstone-voting helm/voting-app -n voting | less
```

The three application image values are placeholders in `helm/voting-app/values.yaml`, so **do not install using only the default values**.

## 2. Publish hardened images to ECR (explicit opt-in)

Requires the already-verified `terraform-process` AWS profile, local `vote-secure:local`, `worker-secure:local`, `result-secure:local`, Docker, Helm and Trivy. The script checks account identity, architecture, and the absence of HIGH/CRITICAL Trivy findings. It creates up to three private ECR repos (`devops-capstone/vote`, `.../worker`, `.../result`) with immutable tags, then pushes the images.

**ECR storage and traffic may cost money**; these repositories are **not** managed by the existing EKS Terraform configuration, so `terraform destroy` will **not** delete them.

```bash
bash scripts/publish_voting_images_ecr.sh
# Only after authorizing ECR repo creation and image storage:
bash scripts/publish_voting_images_ecr.sh --publish
```

The script writes the gitignored `helm/voting-app/values-ecr.local.yaml` (no credentials). It tags images using the current Git commit SHA; ensure the three local images were built from the source at that revision before using the tag as provenance. Helm deploys the exact tag specified in the file. To avoid mistaken provenance on a fresh source change, rebuild, rescan and commit before republishing.

Private ECR pulls work from this EKS managed node group because its role has `AmazonEC2ContainerRegistryPullOnly`. Do not copy AWS login credentials to Kubernetes.

## 3. Deploy the five components (creates workloads; only after confirming EKS is ready)

```bash
export AWS_PROFILE=terraform-process
export AWS_DEFAULT_REGION=eu-north-1
kubectl --context devops-capstone-eks get nodes

helm upgrade --install capstone-voting helm/voting-app \
  --namespace voting --create-namespace \
  -f helm/voting-app/values-ecr.local.yaml \
  --wait --timeout 6m

kubectl --context devops-capstone-eks -n voting get deployments,pods,services
kubectl --context devops-capstone-eks -n voting logs deploy/worker --tail=80
```

Confirm all **five Pods are Running/Ready**; look for Worker `Connected to db`, `Connecting to redis`, then vote processing logs. The Worker has no HTTP probe, so logs and end-to-end voting are the functional checks. If Pods do not become Ready, inspect `kubectl describe pod` and `kubectl get events` and resolve the cause rather than repeatedly reinstalling.

## 4. Smoke test with local port forwards

In **terminal A**:

```bash
kubectl --context devops-capstone-eks -n voting port-forward svc/vote 18080:8080
```

In **terminal B**:

```bash
kubectl --context devops-capstone-eks -n voting port-forward svc/result 18081:8080
```

Open `http://127.0.0.1:18080` and `http://127.0.0.1:18081`. Cast a vote in a fresh browser session and confirm the Results page updates. Alternatively test HTTP from a third terminal:

```bash
curl -fsSI http://127.0.0.1:18080/ || curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18080/
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18081/
```

Record screenshots and Helm release history in `docs/evidence/helm/`, but do not commit secrets, kubeconfig, Terraform state or rendered Kubernetes Secrets.

## 5. Intentional failing rollout + explicit rollback (later milestone)

Record the known-good revision with `helm history capstone-voting -n voting`. A deliberately nonexistent Vote image tag can demonstrate a failed upgrade and an explicit `helm rollback`, but perform this test **only after all Pods work** and with sufficient time for recovery. Avoid using `--atomic` when you need to show a manual rollback; it rolls back automatically. Do not destroy the database Pod as part of rollback evidence because its storage is ephemeral.

## 6. Cleanup today (cluster incurs charges until destroyed)

First uninstall the chart if installed:

```bash
helm uninstall capstone-voting -n voting
```

Before logging off, destroy the paid EKS infrastructure and verify no cluster remains:

```bash
terraform -chdir=infra/eks plan -destroy -out=destroy.tfplan
# Inspect: only 8 capstone resources should be affected; default VPC/subnets remain.
terraform -chdir=infra/eks apply -input=false destroy.tfplan
aws eks list-clusters --region eu-north-1 --profile terraform-process
terraform -chdir=infra/eks state list
```

ECR repositories persist after EKS destruction and can have a small storage charge. To delete them later, first verify their images are no longer needed for a redeployment and then use the AWS ECR cleanup process with explicit consent.
