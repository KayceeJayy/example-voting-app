# Voting App — Helm deployment on AWS EKS

This guide describes the **verified Capstone 1 lab deployment**, not a production-ready service. Its current Helm release is `voting-app` in namespace `voting-app`, running on cluster `devops-capstone-eks` in AWS region `eu-north-1`.

## What the chart deploys

- Five Kubernetes Deployments: `vote`, `result`, `worker`, `redis`, `db` (PostgreSQL).
- Four internal `ClusterIP` Services: `vote`, `result`, `redis`, `db`.
- One Kubernetes Secret containing the upstream sample PostgreSQL password. **This is not sufficient credential hardening**: the Worker and Result application source uses `postgres/postgres` directly.
- One `db-data` PersistentVolumeClaim requesting **8 GiB**, `ReadWriteOnce`, StorageClass `gp3`, mounted by PostgreSQL.
- Redis uses `emptyDir` and remains **ephemeral**.
- Resource requests/limits and probes; no public `LoadBalancer` or `Ingress` is created by this chart.

The `gp3` StorageClass is defined separately in `k8s-specifications/storageclass-gp3.yaml`, with EBS CSI provisioner `ebs.csi.aws.com`, encryption enabled, `WaitForFirstConsumer`, and **Retain** reclaim policy. Terraform under `infra/eks/` manages the EKS Pod Identity Agent, EBS CSI driver and its IAM role. The StorageClass itself must be applied to Kubernetes before installing Helm.

## 1. Validate the chart (no cluster changes)

From the repository root:

```bash
bash scripts/validate_voting_helm.sh
helm lint ./helm/voting-app
```

The three application image references in `helm/voting-app/values.yaml` are intentionally invalid placeholders; never install the chart with only default values. Use a verified image override, such as the local Git-ignored `helm/voting-app/values-ecr.local.yaml`.

To render the deployment with the existing local ECR override:

```bash
helm template voting-app ./helm/voting-app \
  --namespace voting-app \
  -f helm/voting-app/values-ecr.local.yaml \
  > /tmp/voting-app-rendered.yaml
```

Do not commit rendered Kubernetes Secrets, Terraform state, credentials or local overrides.

## 2. Prepare AWS and storage

AWS CLI access must be authorized for the target account. The Terraform plan must be reviewed before changes, and the current public IPv4 `/32` must match the EKS endpoint allowlist. Existing EKS access is verified with:

```bash
export AWS_PROFILE=terraform-process
export AWS_REGION=eu-north-1
kubectl get nodes
kubectl get pods -n kube-system
```

After EBS CSI and Pod Identity are operational, apply or verify the StorageClass:

```bash
kubectl apply -f k8s-specifications/storageclass-gp3.yaml
kubectl get storageclass gp3
```

This step does **not** create an EBS volume by itself; the volume is dynamically provisioned when the PostgreSQL PVC is consumed.

## 3. Images and publication boundary

GitHub Actions CI on branch pushes builds, scans and integration-tests custom images but does **not** deploy to EKS automatically. An explicitly pushed release tag triggers a separate GHCR publishing workflow; promotion to private AWS ECR is operator-controlled and documented in `docs/ci/GHCR_PHASE_2.md` and `docs/evidence/ci/ghcr-to-ecr-promotion-2026-11-13.txt`.

The actual EKS deployment used commit-tagged Vote, Worker and Result images in private ECR. The worker-node IAM role allows ECR pulls. The local Helm image override must reference images that really exist. ECR repositories are **not** destroyed with the EKS Terraform stack and may incur storage charges.

## 4. Install or update the current release

Only run after confirming AWS access, EKS node readiness, StorageClass and valid image tags:

```bash
helm upgrade --install voting-app ./helm/voting-app \
  --namespace voting-app --create-namespace \
  -f helm/voting-app/values-ecr.local.yaml \
  --wait --timeout 8m

helm status voting-app -n voting-app
kubectl get deployments,pods,svc -n voting-app
kubectl get pvc db-data -n voting-app
kubectl get pv
```

Expected: five Deployments available, and PVC `db-data` **Bound** to an 8 GiB gp3 persistent volume. The verified deployment used an **encrypted** AWS EBS volume, `vol-0fed301f9a1574c6f` in `eu-north-1b` on 15 November 2026. Volume IDs change if storage is recreated.

## 5. Test the voting websites

Run these commands in **separate terminals**:

```bash
kubectl -n voting-app port-forward svc/vote 18080:8080
```

```bash
kubectl -n voting-app port-forward svc/result 18081:8080
```

Open http://127.0.0.1:18080 and http://127.0.0.1:18081. Cast a vote from a fresh browser session and verify the Result page updates. Port forwarding exposes the sites only on your local machine and requires working Kubernetes API connectivity.

## 6. Data persistence, rollback and limitations

**Persistence:** On 15 November 2026, a PostgreSQL test record was inserted, the database Pod was deleted, the deployment recovered and the record was queried again successfully. See `docs/evidence/eks/postgres-persistence-2026-11-15.txt`. This confirms survival of **Pod replacement**, not cross-AZ failover or backup/restore.

During that test, Worker and Result each restarted once when PostgreSQL terminated their connections with `SQLSTATE 57P01`. Both recovered through Kubernetes. The Result service also experienced a first-start query before Worker had initialized the `votes` table. Graceful application-level database reconnection remains an improvement opportunity.

**Rollback:** On 13 November 2026 an intentionally failing release was followed by a successful manual Helm rollback, documented in `docs/evidence/helm/revision-3-rollback-2026-11-13.txt`. This was an **earlier** release named `capstone-voting` in namespace `voting`, not the currently running `voting-app` release. Do not use its revision numbers for the current release. To inspect current history:

```bash
helm history voting-app -n voting-app
# Only after selecting a known-good CURRENT revision:
# helm rollback voting-app <REVISION> -n voting-app --wait
```

**Security:** This is a lab-only upstream example with hardcoded PostgreSQL credentials, a single worker node, one-AZ EBS storage and ephemeral Redis. Do not treat it as production-ready.

## 7. Cost and cleanup safeguards

AWS EKS, EC2 nodes, public IPv4, EBS and ECR can incur charges. A PVC using **Retain** can leave behind a billable EBS volume after Helm uninstall or cluster destruction. **Do not run `helm uninstall` or `terraform destroy` as a routine end-of-session step.** Before deliberate teardown, inspect PV/PVCs, EBS volume IDs and intended retention, review Terraform's destroy plan, and separately verify any ECR or retained EBS cleanup. This chart does not manage the gp3 StorageClass, the EBS CSI add-on or the ECR repositories.
