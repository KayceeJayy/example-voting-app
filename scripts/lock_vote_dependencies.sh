#!/usr/bin/env bash
# Pin the exact Python distributions from the already-tested vote-secure:local image.
# Run from anywhere after extracting the kit into the root of example-voting-app.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for command in docker python3 trivy curl; do
  command -v "$command" >/dev/null || { echo "ERROR: missing $command" >&2; exit 1; }
done

docker image inspect vote-secure:local >/dev/null || {
  echo "ERROR: Build/locate the already verified vote-secure:local image first." >&2
  exit 1
}

mkdir -p docs/security
TMP="$(mktemp -d)"
SMOKE_NAME="capstone-vote-lock-smoke"
cleanup() {
  docker rm -f "$SMOKE_NAME" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo '== 1/5: Extracting exact installed Python versions from verified image =='
docker run --rm --entrypoint python vote-secure:local -m pip freeze > "$TMP/freeze.txt"

python3 - "$TMP/freeze.txt" vote/requirements-prod.lock <<'PY'
import re
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
entries = []
seen = set()
for line in source.read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    m = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9._-]*)==([^=\s]+)", line)
    if not m:
        raise SystemExit(f"ERROR: Dependency is not an exact version pin: {line!r}")
    canonical = re.sub(r"[-_.]+", "-", m.group(1)).lower()
    if canonical in seen:
        raise SystemExit(f"ERROR: Duplicate dependency: {canonical}")
    seen.add(canonical)
    entries.append(line)

required = {"flask", "redis", "gunicorn"}
if not required.issubset(seen):
    raise SystemExit(f"ERROR: Missing expected direct dependencies: {sorted(required - seen)}")

new_text = ("# Exact Python runtime dependencies from verified vote-secure:local image.\n"
            "# Refresh deliberately after tests and a security review.\n"
            + "\n".join(sorted(entries, key=str.casefold)) + "\n")
destination.write_text(new_text)
print(f"Wrote {destination} with {len(entries)} exact pins.")
print(new_text, end="")
PY

echo '== 2/5: Updating only the final production Dockerfile stage =='
python3 - <<'PY'
from pathlib import Path
import re

path = Path("vote/Dockerfile")
original = path.read_text()
markers = list(re.finditer(r"(?im)^FROM\s+\S+\s+AS\s+final\s*$", original))
if len(markers) != 1:
    raise SystemExit("ERROR: Expected exactly one final stage; Dockerfile unchanged.")
idx = markers[0].start()
head, final = original[:idx], original[idx:]
old_copy = "COPY requirements.txt ./requirements.txt"
new_copy = "COPY requirements-prod.lock ./requirements-prod.lock"
old_install = "python -m pip install --no-cache-dir -r requirements.txt"
new_install = "python -m pip install --no-cache-dir --no-deps -r requirements-prod.lock"
if old_copy in final and old_install in final:
    final = final.replace(old_copy, new_copy, 1).replace(old_install, new_install, 1)
elif new_copy in final and new_install in final:
    print("Production Dockerfile already uses the lockfile.")
else:
    raise SystemExit("ERROR: Unexpected production installation instructions; Dockerfile unchanged.")
path.write_text(head + final)
print("Production stage now installs only pinned runtime distributions. Development stage unchanged.")
PY

git diff --check
echo '== 3/5: Rebuilding production image =='
docker build --target final --tag vote-secure:local ./vote

echo '== 4/5: Verifying exact dependency set, runtime UID, and Trivy =='
docker run --rm --entrypoint id vote-secure:local
docker run --rm --entrypoint python vote-secure:local -m pip freeze > "$TMP/rebuilt.txt"
python3 - "$TMP/rebuilt.txt" vote/requirements-prod.lock <<'PY'
from pathlib import Path
import sys
actual = sorted(Path(sys.argv[1]).read_text().splitlines(), key=str.casefold)
expected = sorted([x for x in Path(sys.argv[2]).read_text().splitlines() if x and not x.startswith('#')], key=str.casefold)
if actual != expected:
    print('ERROR: Built image dependency versions differ from committed lockfile.')
    print('Actual:  ', actual)
    print('Expected:', expected)
    sys.exit(1)
print(f'PASS: Built image matches all {len(expected)} pinned packages.')
PY

trivy image --image-src docker --scanners vuln \
  --severity HIGH,CRITICAL --exit-code 1 --format json \
  --output docs/security/vote-trivy-pinned.json vote-secure:local

echo '== 5/5: Local HTTP smoke test =='
REDIS_ID="$(docker compose ps -q redis)"
[ -n "$REDIS_ID" ] || { echo 'ERROR: Docker Compose Redis not running.' >&2; exit 1; }
NET="$(docker inspect -f '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}}{{end}}' "$REDIS_ID")"
[ -n "$NET" ] || { echo 'ERROR: Cannot identify Redis network.' >&2; exit 1; }
docker rm -f "$SMOKE_NAME" >/dev/null 2>&1 || true
docker run -d --name "$SMOKE_NAME" --network "$NET" \
  -p 127.0.0.1:18088:8080 vote-secure:local >/dev/null
curl --fail --silent --show-error --retry 8 --retry-all-errors \
  --retry-delay 2 --retry-max-time 60 --max-time 10 \
  -o /dev/null -w 'Production Vote HTTP: %{http_code}\n' \
  http://127.0.0.1:18088/

echo 'PASS: Version-lock build, vulnerability gate and HTTP smoke test completed.'
echo 'NEXT: Inspect git diff and commit vote/requirements-prod.lock and vote/Dockerfile.'
