#!/usr/bin/env bash
# Read-only AWS checks for default VPC EKS lab architecture.
# Does NOT run Terraform apply, create AWS resources, or change your account.
set -Eeuo pipefail
PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-eu-north-1}"
EKS_VERSION="${EKS_VERSION:-1.36}"
AWS=(aws --no-cli-pager --profile "$PROFILE" --region "$REGION")
command -v aws >/dev/null || { echo 'AWS CLI not installed.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 not installed.' >&2; exit 1; }

ACCOUNT_ID="$("${AWS[@]}" sts get-caller-identity --query Account --output text)"
[[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo 'AWS identity check failed.' >&2; exit 1; }
printf 'Profile: %s | Region: %s | Account identity: verified\n' "$PROFILE" "$REGION"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"${AWS[@]}" ec2 describe-vpcs --filters Name=is-default,Values=true \
  --output json > "$TMP/vpcs.json"
VPC_ID="$(python3 - "$TMP/vpcs.json" <<'PY'
import json, sys
vpcs = json.load(open(sys.argv[1])).get('Vpcs', [])
if len(vpcs) != 1:
    raise SystemExit(f'ERROR: Expected one default VPC, found {len(vpcs)}')
print(vpcs[0]['VpcId'])
PY
)"
echo "Default VPC: $VPC_ID"

"${AWS[@]}" ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --output json > "$TMP/subnets.json"
"${AWS[@]}" ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
  --output json > "$TMP/routes.json"
"${AWS[@]}" ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --output json > "$TMP/igws.json"

"${AWS[@]}" ec2 describe-vpc-attribute --vpc-id "$VPC_ID" \
  --attribute enableDnsSupport --output json > "$TMP/dns_support.json"
"${AWS[@]}" ec2 describe-vpc-attribute --vpc-id "$VPC_ID" \
  --attribute enableDnsHostnames --output json > "$TMP/dns_hostnames.json"

python3 - "$TMP" "$VPC_ID" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1]); vpc_id = sys.argv[2]
def data(filename):
    return json.loads((root / filename).read_text())

subnets = data('subnets.json').get('Subnets', [])
rts = data('routes.json').get('RouteTables', [])
igws = data('igws.json').get('InternetGateways', [])
if not igws:
    raise SystemExit('FAIL: No Internet Gateway attached to default VPC.')
main = next((r for r in rts if any(a.get('Main') for a in r.get('Associations', []))), None)

eligible = []
print('\nSubnet readiness (public routes required for this no-NAT lab design):')
for s in subnets:
    explicit = next((r for r in rts if any(a.get('SubnetId') == s['SubnetId'] for a in r.get('Associations', []))), None)
    rt = explicit or main
    public_route = bool(rt and any(r.get('DestinationCidrBlock') == '0.0.0.0/0' and str(r.get('GatewayId', '')).startswith('igw-') and r.get('State', 'active') == 'active' for r in rt.get('Routes', [])))
    auto_ip = s.get('MapPublicIpOnLaunch', False)
    free = s.get('AvailableIpAddressCount', 0)
    ok = public_route and auto_ip and free >= 16
    print(f"  {s['SubnetId']} | {s['AvailabilityZone']} | auto-public-IP={auto_ip} | IGW-route={public_route} | available IPs={free} | {'PASS' if ok else 'NOT ELIGIBLE'}")
    if ok:
        eligible.append(s)

if len({s['AvailabilityZone'] for s in eligible}) < 2:
    raise SystemExit('FAIL: Fewer than 2 suitable public subnets in distinct AZs.')

support = data('dns_support.json').get('EnableDnsSupport', {}).get('Value')
hostnames = data('dns_hostnames.json').get('EnableDnsHostnames', {}).get('Value')
print(f'DNS support: {support} | DNS hostnames: {hostnames}')
if not (support and hostnames):
    raise SystemExit('FAIL: Default VPC DNS prerequisites not enabled.')

print('\nPASS: Default VPC prerequisites validated for a temporary public-subnet EKS lab.')
print('Suggested Terraform input VPC ID:', vpc_id)
print('Suggested eligible subnets:', ', '.join(s['SubnetId'] for s in eligible))
PY

"${AWS[@]}" eks describe-cluster-versions --cluster-versions "$EKS_VERSION" \
  --output json > "$TMP/versions.json"
python3 - "$TMP/versions.json" "$EKS_VERSION" <<'PY'
import json, sys
versions = json.load(open(sys.argv[1])).get('clusterVersions', [])
match = next((v for v in versions if v.get('clusterVersion') == sys.argv[2]), None)
if not match or match.get('versionStatus') != 'STANDARD_SUPPORT':
    raise SystemExit(f'FAIL: EKS {sys.argv[2]} not verified in STANDARD_SUPPORT in chosen region.')
print(f"PASS: EKS Kubernetes {sys.argv[2]} in STANDARD_SUPPORT; standard support until {match.get('endOfStandardSupportDate')}")
PY

echo 'Existing EKS clusters in region:'
"${AWS[@]}" eks list-clusters --query 'clusters' --output json

echo 'Checking account-wide budgets (read-only)...'
aws --no-cli-pager --profile "$PROFILE" --region us-east-1 budgets describe-budgets \
  --account-id "$ACCOUNT_ID" \
  --query 'Budgets[*].[BudgetName,BudgetLimit.Amount,TimeUnit]' --output table

echo 'PASS: AWS read-only preflight finished; NO infrastructure was created.'
echo 'STOP: Terraform apply still requires a reviewed plan, cost estimate, and explicit approval.'
