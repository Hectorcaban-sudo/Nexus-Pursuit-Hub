#!/usr/bin/env bash
# Nexus Pursuit Hub: install into a development org from this repo.
#
#   scripts/dev-setup.sh                         # new scratch org "nxp-dev" (7 days)
#   scripts/dev-setup.sh --alias my-dev --days 14
#   scripts/dev-setup.sh --org my-sandbox        # use an existing sandbox instead of a scratch org
#   scripts/dev-setup.sh --org my-sandbox --no-sample-data
#
# Steps: org -> deploy all packages (API 68.0) -> env-config/dev -> permission sets -> sample data -> jobs.
# PowerShell version: scripts/dev-setup.ps1. Remove again: scripts/uninstall.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/common.sh

ALIAS="nxp-dev"
DAYS=7
EXISTING=""
SAMPLE=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --alias) ALIAS="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --org) EXISTING="$2"; shift 2 ;;
    --no-sample-data) SAMPLE=false; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) die "Unknown option $1" ;;
  esac
done
require_sf

if [[ -n "$EXISTING" ]]; then
  ALIAS="$EXISTING"
  step "Using existing org $ALIAS"
else
  step "Creating scratch org $ALIAS ($DAYS days)"
  sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" --duration-days "$DAYS" --set-default --wait 20
fi

step "Deploying packages in dependency order (one deployment)"
sf project deploy start --source-dir "${PACKAGE_DIRS[@]}" --target-org "$ALIAS" --api-version "$API_VERSION" --wait 30

step "Deploying env-config/dev"
(cd env-config/dev && sf project deploy start --source-dir force-app --target-org "$ALIAS" --api-version "$API_VERSION" --wait 10)

step "Assigning permission sets"
sf org assign permset --name NXP_User --name NXP_Power_User --name NXP_Admin --target-org "$ALIAS"

if [[ "$SAMPLE" == true ]]; then
  scripts/load-sample-data.sh --org "$ALIAS"
fi

step "Scheduling background jobs"
run_apex scripts/post-deploy/schedule-jobs.apex "$ALIAS"

cat <<MSG

Done. Next:
  1. Setup > Named Credentials > External Credentials > NXP SAM.gov > Principals > Default:
     add an Authentication Parameter named ApiKey with your SAM.gov API key.
  2. Test it:  scripts/test-functional.sh --org $ALIAS
  3. Open it:  sf org open --target-org $ALIAS --path /lightning/n/NXP_Match_Inbox
MSG
