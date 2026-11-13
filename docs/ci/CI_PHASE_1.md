# Capstone CI – Phase 1 (no AWS)

`capstone-ci.yaml` is an **automated CI quality gate**, not CD yet. It runs on
push to `feature/container-hardening` or `main`, PRs into `main`, and manual dispatch.

Sequence: Helm 4.3.0 offline lint/template validation; Docker `final` target
builds for amd64; Trivy HIGH/CRITICAL image scans; disposable five-service
Docker Compose environment; HTTP Vote and Results checks; Vote POST and
PostgreSQL persistence assertion; cleanup even on failures.

Trivy detects known vulnerabilities according to the vulnerability DB at the
time of the run. There are no guarantees that a currently clean image stays
clean after upstream advisories are published.

## Why the upstream workflows should be removed

The three `call-docker-build-*.yaml` files call `dockersamples/.github`'s
mutable shared workflow, publish to Docker's upstream Docker Hub and GHCR
namespaces, and request Docker Hub secrets. These are not appropriate for
this fork. Remove those three tracked workflow files **after reviewing**
this new pipeline.

The upstream `result/package.json` `npm test` exits 1 on purpose and its
legacy PhantomJS test suite assumes port 80 and an obsolete database image.
Do not claim these are working unit tests. Phase 1 implements an actual
end-to-end integration check instead.

## Local test

Requires Docker Engine and Compose, three hardened local `*-secure:local`
images, Helm 4.3.0, and curl:

```sh
bash scripts/validate_voting_helm.sh
docker compose -f ci/docker-compose.ci.yml config --quiet
docker compose -f ci/docker-compose.ci.yml up -d --no-build
bash scripts/test_voting_compose_ci.sh
docker compose -f ci/docker-compose.ci.yml down --volumes --remove-orphans
```

Ports `18080` and `18081` must be available locally. Services are exposed
only on loopback and the database password is an upstream **lab-only** value.
Local volumes are disposable and removed with `down --volumes`.

## Phase 2: AWS ECR publication – not enabled yet

After Phase 1 is green, configure a limited GitHub OIDC role scoped to your
actual repository identity and private ECR repositories, then add a separately
authorized publish job. Do not put AWS access keys in Actions secrets. Prefer
a restricted, protected GitHub Environment and explicit `workflow_dispatch`
for publication, with `id-token: write` only on that job. GitHub Actions
runners are not allowed into the narrow EKS API CIDRs; CD to EKS requires a
separate secure connectivity design. No cluster should be created by CI.

## Security and reproducibility notes

- Actions use released tags, not verified full commit digests. For production,
  resolve and pin each `uses:` reference to an immutable 40-character SHA.
- Pinned Docker base digests can require periodic maintenance when vulnerabilities
  are reported; fix them rather than disabling Trivy.
- The verification confirms a persisted Vote in PostgreSQL and HTTP access to
  the Results endpoint; visual rendering/socket updates remain part of the
  existing browser-based EKS evidence.
