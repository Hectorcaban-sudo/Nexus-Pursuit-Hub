#!/usr/bin/env bash
# Remove Nexus Pursuit Hub from an org. Everything NXP_ goes, including all Nexus records.
#
#   scripts/uninstall.sh --org nxp-qa                  # deployed with sf commands (source mode)
#   scripts/uninstall.sh --org nxp-qa --mode package   # installed as unlocked packages
#   scripts/uninstall.sh --org nxp-qa --purge          # source mode: hard-delete the objects (not production)
#   scripts/uninstall.sh --org nxp-qa --yes            # no confirmation prompt
#
# Scratch org? Delete the whole org instead: sf org delete scratch --target-org <alias>
# Before you run it, delete what was built by hand (see docs/deployment/deployment-guide.md#uninstall):
# the Nexus Pursuit Assistant agent and its agent actions, the NXP prompt templates, and any reports,
# flows or list views people built on NXP objects. Opportunity records created by pushes are kept.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/common.sh

ORG=""
MODE="source"
PURGE=false
YES=false
TEST_LEVEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org|-o) ORG="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --purge) PURGE=true; shift ;;
    --yes|-y) YES=true; shift ;;
    --test-level) TEST_LEVEL="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) die "Unknown option $1" ;;
  esac
done
[[ -n "$ORG" ]] || die "Give the org alias: --org <alias>"
[[ "$MODE" == "source" || "$MODE" == "package" ]] || die "--mode must be source or package"
require_sf

PROD=false
is_production "$ORG" && PROD=true
[[ "$PROD" == true && "$PURGE" == true ]] && die "--purge is not allowed in production orgs."

cat <<MSG

This removes Nexus Pursuit Hub from $ORG ($MODE mode$([[ "$PROD" == true ]] && echo ", PRODUCTION")):
  - stops the NXP scheduled jobs and removes the NXP permission set assignments
  - deletes every NXP_ component, and with the NXP objects all their records
    (notices, searches, matches, push logs, feed runs). Without --purge, deleted objects stay
    under Setup > Object Manager > Deleted Objects for 15 days.
First delete by hand: the Nexus Pursuit Assistant agent and its NXP agent actions, the NXP prompt
templates, and reports, flows or list views built on NXP objects. They block the delete otherwise.
MSG
if [[ "$YES" != true ]]; then
  read -r -p "Type the org alias ($ORG) to continue: " answer
  [[ "$answer" == "$ORG" ]] || die "Stopped. Nothing was changed."
fi

step "Stopping jobs and removing permission set assignments"
run_apex scripts/uninstall/pre-uninstall.apex "$ORG"

REVERSED=()
for ((i=${#PACKAGE_DIRS[@]}-1; i>=0; i--)); do REVERSED+=("${PACKAGE_DIRS[$i]}"); done

if [[ "$MODE" == "package" ]]; then
  INSTALLED=$(sf package installed list --target-org "$ORG" --json)
  for dir in "${REVERSED[@]}"; do
    name=$(basename "$dir")
    # The 04t id that follows this package's SubscriberPackageName in the JSON.
    id=$(printf '%s\n' "$INSTALLED" | awk -v n="\"$name\"" '
      /"SubscriberPackageName"/ { hit = index($0, n) > 0 }
      hit && /"SubscriberPackageVersionId"/ { gsub(/[",]/, "", $2); print $2; exit }')
    if [[ -z "$id" ]]; then
      warn "$name is not installed; skipping"
      continue
    fi
    step "Uninstalling $name ($id)"
    sf package uninstall --package "$id" --target-org "$ORG" --wait 30
  done
else
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/package.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <version>$API_VERSION</version>
</Package>
XML
  EXTRA=(--ignore-warnings)
  [[ "$PURGE" == true ]] && EXTRA+=(--purge-on-delete)
  [[ -n "$TEST_LEVEL" ]] && EXTRA+=(--test-level "$TEST_LEVEL")
  # One deployment per package, dependents first, so nothing still in the org refers to what is deleted.
  for dir in "${REVERSED[@]}"; do
    step "Deleting the components in $dir"
    rm -rf "$WORK/gen" && mkdir -p "$WORK/gen"
    sf project generate manifest --source-dir "$dir" --api-version "$API_VERSION" --output-dir "$WORK/gen" >/dev/null
    mv "$WORK/gen/package.xml" "$WORK/destructiveChangesPost.xml"
    sf project deploy start --manifest "$WORK/package.xml" \
      --post-destructive-changes "$WORK/destructiveChangesPost.xml" \
      --target-org "$ORG" --api-version "$API_VERSION" --wait 60 "${EXTRA[@]}"
  done
fi

cat <<MSG

Nexus Pursuit Hub was removed from $ORG.
Left in place on purpose: Opportunity records created by pushes and any Data Cloud data
streams for NXP_Awards. The SAM.gov API key was removed with the NXP External Credential.
If a step failed, fix what it names (usually something built by hand) and run the script again;
components that are already gone are skipped.
MSG
