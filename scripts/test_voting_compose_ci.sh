#!/usr/bin/env bash
# Verify production containers, Redis queue, Worker and PostgreSQL end-to-end.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
COMPOSE=(docker compose -f ci/docker-compose.ci.yml)

wait_http() {
  local label="$1" url="$2" i
  for ((i=1;i<=40;i++)); do
    if curl -fsS --connect-timeout 2 --max-time 5 -o /dev/null "$url"; then
      printf 'PASS: %s HTTP ready\n' "$label"
      return 0
    fi
    sleep 2
  done
  printf 'FAIL: %s did not become HTTP ready\n' "$label" >&2
  return 1
}

vote_count() {
  "${COMPOSE[@]}" exec -T db psql -X -q -U postgres -d postgres \
    -tAc "SELECT COUNT(*) FROM votes WHERE vote='a';" 2>/dev/null | tr -d '[:space:]'
}

wait_http Vote http://127.0.0.1:18080/
wait_http Results http://127.0.0.1:18081/

# The Worker creates the table on startup. Wait for real DB initialization.
before=''
for ((i=1;i<=30;i++)); do
  before="$(vote_count || true)"
  if [[ "$before" =~ ^[0-9]+$ ]]; then break; fi
  sleep 2
done
if [[ ! "$before" =~ ^[0-9]+$ ]]; then
  echo 'FAIL: Worker did not initialize PostgreSQL votes table.' >&2
  exit 1
fi
printf 'Votes for a before: %s\n' "$before"

# New curl client, no existing voting cookie, one vote for option a.
curl -fsS --connect-timeout 3 --max-time 15 \
  -X POST -d 'vote=a' \
  -o /dev/null http://127.0.0.1:18080/
echo 'PASS: Vote POST accepted'

for ((i=1;i<=40;i++)); do
  after="$(vote_count || true)"
  if [[ "$after" =~ ^[0-9]+$ ]] && (( after > before )); then
    printf 'PASS: Worker persisted vote in PostgreSQL (%s -> %s)\n' "$before" "$after"
    curl -fsS --max-time 10 -o /dev/null http://127.0.0.1:18081/
    echo 'PASS: Results HTTP endpoint available after vote'
    echo 'PASS: End-to-end voting integration test'
    exit 0
  fi
  sleep 2
done
printf 'FAIL: vote was not persisted within polling window (before=%s last=%s)\n' \
  "$before" "${after:-unknown}" >&2
exit 1
