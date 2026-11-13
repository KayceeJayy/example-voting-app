# Voting Application Helm chart

See [`docs/helm/HELM_DEPLOYMENT.md`](../../docs/helm/HELM_DEPLOYMENT.md) for the complete local validation, ECR publication, EKS installation, smoke test, rollback and teardown workflow.

This chart intentionally uses the upstream DNS names `redis` and `db`, with private `ClusterIP` services. Web services run on port 8080. For an inexpensive, temporary EKS demonstration, Redis and PostgreSQL data use `emptyDir` and **will not survive a Pod replacement**.

**Security limitation:** The demonstration application hardcodes its PostgreSQL password in Worker and Results code. The default chart secret contains that known demo password and is **not suitable for production**. Production use requires changing the application source to obtain database credentials from environment variables/Secrets and rebuilding the hardened images.
