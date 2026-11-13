#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REGION='eu-north-1'
PROFILE='terraform-process'
EXPECTED_ACCOUNT='410133709895'

if [[ "${1:-}" != '--publish' ]]; then
  cat <<'NOTE'
DRY-RUN INFORMATION: This script would create up to three private ECR
repositories, upload hardened local images, and create a Git-ignored Helm
values file. Private ECR storage and transfer can incur AWS charges.

To opt in after reviewing the commands, run:
  bash scripts/publish_voting_images_ecr.sh --publish
The script will request an additional typed confirmation before modifying AWS.
NOTE
  exit 0
fi

for tool in aws docker git helm trivy; do
  command -v "$tool" >/dev/null || { echo "ERROR: $tool is required." >&2; exit 1; }
done

ACCOUNT="$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)"
[[ "$ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || {
  echo 'ERROR: Unexpected AWS account; nothing was created.' >&2; exit 1;
}

TAG="$(git rev-parse --short=12 HEAD)"
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

for app in vote worker result; do
  image="${app}-secure:local"
  docker image inspect "$image" >/dev/null || { echo "ERROR: Missing $image" >&2; exit 1; }
  architecture="$(docker image inspect "$image" --format '{{.Architecture}}')"
  [[ "$architecture" == 'amd64' ]] || { echo "ERROR: $image is $architecture, not amd64." >&2; exit 1; }
  echo "===== SCAN $image ====="
  trivy image --image-src docker --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --quiet "$image"
done

printf 'AWS account: %s\nRegion: %s\nGit tag: %s\n' "$ACCOUNT" "$REGION" "$TAG"
printf '%s\n' 'Repositories to create if absent: devops-capstone/vote, devops-capstone/worker, devops-capstone/result'
printf '%s\n' 'Storage and image transfer may incur AWS charges. This does not create an EKS cluster.'
read -r -p 'Type PUBLISH to create/reuse ECR repositories and push images: ' approval
[[ "$approval" == 'PUBLISH' ]] || { echo 'Cancelled before AWS changes.'; exit 1; }

for app in vote worker result; do
  repo="devops-capstone/$app"
  if ! output="$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --repository-names "$repo" 2>&1)"; then
    if [[ "$output" != *RepositoryNotFoundException* ]]; then
      echo "ERROR: Cannot inspect $repo: $output" >&2
      exit 1
    fi
    aws ecr create-repository --profile "$PROFILE" --region "$REGION" \
      --repository-name "$repo" --image-tag-mutability IMMUTABLE \
      --image-scanning-configuration scanOnPush=true \
      --query 'repository.{Name:repositoryName,Uri:repositoryUri}' --output json
  else
    echo "Reusing existing ECR repository: $repo"
  fi

  if aws ecr describe-images --profile "$PROFILE" --region "$REGION" \
      --repository-name "$repo" --image-ids "imageTag=$TAG" \
      --query 'imageDetails[0].imageDigest' --output text >/dev/null 2>&1; then
    echo "ERROR: Image tag $TAG already exists in $repo. Do not overwrite an immutable Git tag." >&2
    exit 1
  fi
done

echo '===== DOCKER LOGIN TO ECR ====='
aws ecr get-login-password --profile "$PROFILE" --region "$REGION" |
  docker login --username AWS --password-stdin "$REGISTRY"

for app in vote worker result; do
  remote="$REGISTRY/devops-capstone/$app:$TAG"
  docker tag "${app}-secure:local" "$remote"
  docker push "$remote"
  echo "PASS: Uploaded $app"
done

values="$ROOT/helm/voting-app/values-ecr.local.yaml"
(
  umask 077
  cat > "$values" <<YAML
# Generated from local, scanned images; intentionally gitignored.
vote:
  image:
    repository: "$REGISTRY/devops-capstone/vote"
    tag: "$TAG"
worker:
  image:
    repository: "$REGISTRY/devops-capstone/worker"
    tag: "$TAG"
result:
  image:
    repository: "$REGISTRY/devops-capstone/result"
    tag: "$TAG"
YAML
)

helm lint "$ROOT/helm/voting-app" -f "$values" --strict
helm template capstone-voting "$ROOT/helm/voting-app" -n voting -f "$values" >/dev/null
printf 'PASS: ECR images published. Local Helm overrides written: %s\n' "$values"
echo 'No Kubernetes workloads or load balancers were created.'
