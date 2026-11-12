#!/usr/bin/env bash
# Safely inspect an existing budget or create a new account-wide monthly AWS COST budget.
# This script does not launch or change any infrastructure.
set -Eeuo pipefail

PROFILE="${AWS_PROFILE:-default}"
BUDGET_NAME="${BUDGET_NAME:-DevOps-Capstone-Monthly}"
BILLING_REGION="us-east-1"  # AWS Budgets billing endpoint
AWS=(aws --no-cli-pager --profile "$PROFILE" --region "$BILLING_REGION")
command -v aws >/dev/null || { echo 'AWS CLI not installed' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 not installed' >&2; exit 1; }

ACCOUNT_ID="$("${AWS[@]}" sts get-caller-identity --query Account --output text)"
[[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo 'ERROR: AWS account identity unavailable.' >&2; exit 1; }

echo "Authenticated to AWS profile '$PROFILE'."
echo "Checking account-wide AWS Budgets in $BILLING_REGION ..."
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
umask 077
if ! "${AWS[@]}" budgets describe-budgets --account-id "$ACCOUNT_ID" --output json > "$TEMP/budgets.json"; then
  echo 'ERROR: Unable to read AWS Budgets. Check credentials/billing IAM permission.' >&2
  exit 1
fi

# Fail closed if the AWS response is empty or malformed.
python3 - "$TEMP/budgets.json" <<'PYVALIDATE'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except (OSError, ValueError) as exc:
    raise SystemExit(
        f"ERROR: Invalid AWS Budgets response: {exc}"
    )

if not isinstance(data, dict) or not isinstance(
    data.get("Budgets"), list
):
    raise SystemExit(
        "ERROR: AWS Budgets response has no valid Budgets list."
    )

print("PASS: AWS Budgets response is valid JSON.")
PYVALIDATE

if python3 - "$TEMP/budgets.json" "$BUDGET_NAME" <<'PY'
import json, sys
budgets = json.load(open(sys.argv[1])).get('Budgets', [])
b = next((b for b in budgets if b.get('BudgetName') == sys.argv[2]), None)
if b:
    print(f"Budget already exists: {b['BudgetName']}")
    print('Limit:', b.get('BudgetLimit'))
    print('Period:', b.get('TimeUnit'))
    sys.exit(0)
sys.exit(1)
PY
then
  echo 'Inspecting existing budget notifications; no changes are being made.'
  "${AWS[@]}" budgets describe-notifications-for-budget \
    --account-id "$ACCOUNT_ID" --budget-name "$BUDGET_NAME" \
    --query 'Notifications[*].[NotificationType,Threshold,ThresholdType,ComparisonOperator]' \
    --output table
  echo 'Important: Check that the existing notifications have the intended email subscriber.'
  exit 0
fi

printf 'AWS has no budget named %s.\n' "$BUDGET_NAME"
read -r -p 'Enter monthly alert limit in USD [30]: ' LIMIT
LIMIT="${LIMIT:-30}"
read -r -p 'Enter alert email address: ' EMAIL
export LIMIT EMAIL
python3 - <<'PY'
import os, re
from decimal import Decimal, InvalidOperation
try:
    amount = Decimal(os.environ['LIMIT'])
except InvalidOperation:
    raise SystemExit('ERROR: Invalid dollar amount.')
if not amount.is_finite() or amount <= 0 or amount > 100000:
    raise SystemExit('ERROR: Amount must be between $0 and $100000.')
email = os.environ['EMAIL']
if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
    raise SystemExit('ERROR: Invalid email address.')
PY

printf '\nBudget: %s | Monthly USD %s | Email: %s\n' "$BUDGET_NAME" "$LIMIT" "$EMAIL"
echo 'Notifications: ACTUAL 25%, 50%, 80%, 100% of the MONTHLY amount.'
echo 'WARNING: AWS Budgets are alerts, NOT hard spending caps. Billing notifications can lag usage.'
read -r -p 'Create this AWS Budget now? Type yes to proceed: ' CONFIRM
if [[ "$CONFIRM" != 'yes' ]]; then
  echo 'No AWS budget was created.'
  exit 0
fi

python3 - "$TEMP/budget.json" "$TEMP/notifications.json" "$BUDGET_NAME" <<'PY'
import json, os, sys
from decimal import Decimal
budget_file, notifications_file, name = sys.argv[1:]
amount = format(Decimal(os.environ['LIMIT']), 'f')
email = os.environ['EMAIL']
budget = {
    'BudgetName': name,
    'BudgetType': 'COST',
    'TimeUnit': 'MONTHLY',
    'BudgetLimit': {'Amount': amount, 'Unit': 'USD'}
}
notifications = []
for pct in (25, 50, 80, 100):
    notifications.append({
        'Notification': {
            'NotificationType': 'ACTUAL',
            'ComparisonOperator': 'GREATER_THAN',
            'Threshold': pct,
            'ThresholdType': 'PERCENTAGE'
        },
        'Subscribers': [{'SubscriptionType': 'EMAIL', 'Address': email}]
    })
with open(budget_file, 'w') as f:
    json.dump(budget, f, indent=2)
with open(notifications_file, 'w') as f:
    json.dump(notifications, f, indent=2)
PY

"${AWS[@]}" budgets create-budget --account-id "$ACCOUNT_ID" \
  --budget "file://$TEMP/budget.json" \
  --notifications-with-subscribers "file://$TEMP/notifications.json"

echo 'Budget creation requested. Verifying settings:'
"${AWS[@]}" budgets describe-budget --account-id "$ACCOUNT_ID" \
  --budget-name "$BUDGET_NAME" \
  --query 'Budget.[BudgetName,BudgetLimit,TimeUnit]' --output json
"${AWS[@]}" budgets describe-notifications-for-budget --account-id "$ACCOUNT_ID" \
  --budget-name "$BUDGET_NAME" \
  --query 'Notifications[*].[NotificationType,Threshold,ThresholdType]' --output table
printf '\nIMPORTANT: Verify that budget notification emails are received.\n'
