#!/usr/bin/env bash
# Nexus Pursuit Hub: create a development org from this repo.
#
#   scripts/dev-setup.sh                      # new scratch org "nxp-dev" (7 days)
#   scripts/dev-setup.sh --alias my-dev --days 14
#   scripts/dev-setup.sh --org my-sandbox     # use an existing sandbox instead of a scratch org
#
# Steps: org -> deploy all packages (API 68.0) -> env-config/dev -> permission sets -> seed data -> jobs.
set -euo pipefail
cd "$(dirname "$0")/.."

ALIAS="nxp-dev"
DAYS=7
EXISTING=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --alias) ALIAS="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --org) EXISTING="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
done

if [[ -n "$EXISTING" ]]; then
  ALIAS="$EXISTING"
  echo "==> Using existing org $ALIAS"
else
  echo "==> Creating scratch org $ALIAS ($DAYS days)"
  sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" --duration-days "$DAYS" --set-default --wait 20
fi

echo "==> Deploying packages in dependency order (one deployment)"
sf project deploy start \
  --source-dir packages/nxp-core packages/nxp-ingestion packages/nxp-search \
  packages/nxp-push packages/nxp-experience packages/nxp-agents \
  --target-org "$ALIAS" --api-version 68.0 --wait 30

echo "==> Deploying env-config/dev"
(cd env-config/dev && sf project deploy start --source-dir force-app --target-org "$ALIAS" --api-version 68.0 --wait 10)

echo "==> Assigning permission sets"
sf org assign permset --name NXP_User --name NXP_Power_User --name NXP_Admin --target-org "$ALIAS"

echo "==> Loading sample data"
sf data import tree --plan data/seed/plan.json --target-org "$ALIAS"

echo "==> Scheduling background jobs"
sf apex run --file scripts/post-deploy/schedule-jobs.apex --target-org "$ALIAS"

cat <<MSG

Done. Next:
  1. Setup > Named Credentials > External Credentials > NXP SAM.gov > Principals > Default:
     add an Authentication Parameter named ApiKey with your SAM.gov API key.
  2. sf org open --target-org $ALIAS --path /lightning/n/NXP_Match_Inbox
MSG
