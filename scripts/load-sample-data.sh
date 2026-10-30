#!/usr/bin/env bash
# Load the Nexus Pursuit Hub sample data into a dev, QA or scratch org. Safe to run again.
#
#   scripts/load-sample-data.sh --org nxp-dev            # load (or refresh) the sample data
#   scripts/load-sample-data.sh --org nxp-dev --reset    # delete the sample data first, then load it
#   scripts/load-sample-data.sh --org nxp-dev --delete   # only delete the sample data
#
# Loads: a sample Company Profile, 7 agencies, 3 contract vehicles, 4 vendors, 6 award summaries,
# 3 forecasts, 10 SAMPLE notices (scored on insert), 4 saved searches for you, the search matches
# and alerts they produce, and one made-up eBuy RFQ e-mail (notice EBUY:RFQ9990001).
# Refuses to run against a production org unless --allow-production is given.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/common.sh

ORG=""
RESET=false
DELETE_ONLY=false
ALLOW_PROD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org|-o) ORG="$2"; shift 2 ;;
    --reset) RESET=true; shift ;;
    --delete) DELETE_ONLY=true; shift ;;
    --allow-production) ALLOW_PROD=true; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) die "Unknown option $1" ;;
  esac
done
[[ -n "$ORG" ]] || die "Give the org alias: --org <alias>"
require_sf

if is_production "$ORG" && [[ "$ALLOW_PROD" != true ]]; then
  die "$ORG is a production org. Sample data is for dev, QA and scratch orgs only (override: --allow-production)."
fi

if [[ "$RESET" == true || "$DELETE_ONLY" == true ]]; then
  step "Deleting existing sample data"
  run_apex scripts/apex/delete-sample-data.apex "$ORG"
  [[ "$DELETE_ONLY" == true ]] && { echo "Sample data deleted."; exit 0; }
fi

step "Company Profile (before the notices, so they are scored as they load)"
run_apex scripts/apex/seed-profile.apex "$ORG"

# file | object | external ID field. Order matters: agencies, vendors, awards and forecasts before the notices that point to them.
LOADS=(
  "data/seed/1-NXP_Gov_Agency__c-departments.csv|NXP_Gov_Agency__c|Agency_Code__c"
  "data/seed/2-NXP_Gov_Agency__c-agencies.csv|NXP_Gov_Agency__c|Agency_Code__c"
  "data/seed/3-NXP_Contract_Vehicle__c.csv|NXP_Contract_Vehicle__c|Vehicle_Code__c"
  "data/seed/4-NXP_Gov_Vendor__c.csv|NXP_Gov_Vendor__c|UEI__c"
  "data/seed/5-NXP_Award_Summary__c.csv|NXP_Award_Summary__c|PIID__c"
  "data/seed/6-NXP_Gov_Forecast__c.csv|NXP_Gov_Forecast__c|Forecast_Id__c"
  "data/seed/7-NXP_Gov_Notice__c.csv|NXP_Gov_Notice__c|Notice_Id__c"
  "data/seed/8-NXP_Gov_Contact__c.csv|NXP_Gov_Contact__c|Contact_Key__c"
)
for load in "${LOADS[@]}"; do
  IFS='|' read -r file object extid <<<"$load"
  step "Upserting $(basename "$file") into $object (by $extid)"
  sf data upsert bulk --sobject "$object" --file "$file" --external-id "$extid" \
    --line-ending LF --wait 10 --target-org "$ORG"
done

step "Setting sample dates relative to today and linking forecasts"
run_apex scripts/apex/refresh-sample-dates.apex "$ORG"

step "Saved searches and matching"
run_apex scripts/apex/seed-searches.apex "$ORG"

step "Sample eBuy RFQ e-mail (Inbound Emails)"
run_apex scripts/apex/seed-ebuy-email.apex "$ORG"

cat <<MSG

Sample data loaded into $ORG. Matching runs in the background and takes about a minute.
  Test everything:  scripts/test-functional.sh --org $ORG
  Look around:      sf org open --target-org $ORG --path /lightning/n/NXP_Match_Inbox
MSG
