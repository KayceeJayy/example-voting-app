# CI/CD Phase 2: Manual opt-in GHCR publishing

## Why GHCR instead of direct AWS ECR CI

The AWS Organizations SCP in AWS account `410133709895` explicitly denies IAM
`ListOpenIDConnectProviders` and `GetOpenIDConnectProvider`. We cannot verify
or safely provision GitHub OIDC in this account using the available role.
Avoid putting long-lived AWS access keys or the full-access local role on a
GitHub runner. The previously validated CI workflow remains unchanged.

## What this workflow proves

A deliberately pushed Git tag `capstone-publish-<12-character commit SHA>`
starts an isolated GitHub Actions run on the tagged commit. The job:

1. Checks the tag refers to the expected commit.
2. Validates the Helm chart.
3. Builds the three AMD64 hardened production images.
4. Requires all three Trivy HIGH/CRITICAL checks to pass.
5. Starts Docker Compose and verifies vote persistence in PostgreSQL.
6. Logs in to GHCR using the scoped repository `GITHUB_TOKEN`.
7. Publishes the scanned images with the 12-character commit SHA as tag.

No AWS credentials are used and no AWS infrastructure is created.

## Start a release (only after committing the new workflow)

```bash
cd ~/projects/devops-capstone/example-voting-app

git status -sb
TAG="capstone-publish-$(git rev-parse --short=12 HEAD)"

git tag -a "$TAG" -m "Publish tested, scanned capstone images to GHCR"
git push origin "$TAG"
```

The workflow triggers on the tag push, even though the separate
`workflow_dispatch`-based CI manual trigger may require the workflow to exist
on the default branch.

## Expected images

Replace `<sha12>` with the actual commit prefix:

- `ghcr.io/kayceejayy/example-voting-app-vote:<sha12>`
- `ghcr.io/kayceejayy/example-voting-app-worker:<sha12>`
- `ghcr.io/kayceejayy/example-voting-app-result:<sha12>`

New GHCR packages may start with private visibility even when the repository is
public. Review package access/visibility before retrieving from a local Docker
client, and never post an access token in logs or commit it.

## Scope and caveats

- GHCR commit tags are not intrinsically immutable. Never force-move/reuse a
  publication tag. The ECR repositories are immutable.
- This is automatic publishing to GitHub Container Registry, **not** automatic
  GitHub-to-AWS-ECR publishing. ECR promotion can be done separately with the
  local AWS CLI profile after the GHCR run succeeds.
- Never run the local ECR promotion until the workflow succeeded and the
  GHCR source images are verified.
- EKS stays destroyed until a later deliberately authorized lab deployment.
- Trivy vulnerability intelligence is time-dependent; new findings may cause
  later rebuilds to fail despite a previous successful scan.
