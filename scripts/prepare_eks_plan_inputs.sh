#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/infra/eks/terraform.tfvars"
TEMPLATE="$ROOT/infra/eks/terraform.tfvars.example"
if [[ -e "$TARGET" ]]; then
  echo "Configuration already exists. Refusing to overwrite: $TARGET"
  exit 1
fi
command -v curl >/dev/null || { echo 'ERROR: curl not found'; exit 1; }
PUBLIC_IP="$(curl -4 --fail --silent --show-error --max-time 15 https://checkip.amazonaws.com | tr -d '[:space:]')"
python3 - "$TEMPLATE" "$TARGET" "$PUBLIC_IP" <<'PYTHON'
import ipaddress
import pathlib
import sys
src, dest, address = sys.argv[1:]
ip = ipaddress.ip_address(address)
if not isinstance(ip, ipaddress.IPv4Address) or not ip.is_global:
    raise SystemExit("ERROR: Expected a globally routable public IPv4 address")
text = pathlib.Path(src).read_text()
marker = "REPLACE_WITH_YOUR_PUBLIC_IPV4/32"
if text.count(marker) != 1:
    raise SystemExit("ERROR: Missing expected public-IP placeholder")
pathlib.Path(dest).write_text(text.replace(marker, f"{ip}/32"))
print(f"Created local Terraform inputs with API CIDR {ip}/32.")
print("If your public IP changes, update public_api_cidr before planning/deploying.")
PYTHON
chmod 600 "$TARGET"
