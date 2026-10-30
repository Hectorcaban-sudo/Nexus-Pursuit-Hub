#!/usr/bin/env bash
# Load a GovWin IQ alert export for the parallel run and compare it with Nexus.
#
#   scripts/load-govwin-export.sh --org nxp-uat --file govwin-week1.csv
#
# The CSV needs the columns in data/govwin/govwin-export-template.csv (see data/govwin/README.md).
# Rows are upserted on GovWin_Id__c, so loading the same export again updates it. Then
# NXP_GovWinCompareBatch sets each alert's result; the Adoption dashboard shows the catch rate.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/common.sh

ORG=""
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org|-o) ORG="$2"; shift 2 ;;
    --file|-f) FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "Unknown option $1" ;;
  esac
done
[[ -n "$ORG" ]] || die "Give the org alias: --org <alias>"
[[ -n "$FILE" && -f "$FILE" ]] || die "Give the CSV export: --file <path>"
head -n 1 "$FILE" | grep -q 'GovWin_Id__c' || die "$FILE has no GovWin_Id__c column; rename the columns as in data/govwin/govwin-export-template.csv"
require_sf

step "Upserting $(basename "$FILE") into NXP_GovWin_Alert__c (by GovWin_Id__c)"
sf data upsert bulk --sobject NXP_GovWin_Alert__c --file "$FILE" --external-id GovWin_Id__c \
  --line-ending LF --wait 10 --target-org "$ORG"

step "Comparing with Nexus"
run_apex scripts/apex/compare-govwin.apex "$ORG"
echo "Done. The results appear on the Adoption dashboard in a minute (GovWin parallel run)."
