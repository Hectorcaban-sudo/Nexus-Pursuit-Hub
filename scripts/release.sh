#!/usr/bin/env bash
# Release Nexus Pursuit Hub to an environment with sf commands (no CI/CD pipeline).
#
#   scripts/release.sh <env> <org-alias> [source|package]
#     env       dev | qa | uat | prod   (selects env-config/<env>)
#     source    (default) validate, then quick-deploy the package folders as metadata
#     package   install the package versions listed in release/versions.json, in order
#
# Example: scripts/release.sh uat nxp-uat
set -euo pipefail
cd "$(dirname "$0")/.."

ENV="${1:?env (dev|qa|uat|prod)}"
ORG="${2:?org alias}"
MODE="${3:-source}"
VERSION="$(git describe --tags --always 2>/dev/null || echo untagged)"
DIRS=(packages/nxp-core packages/nxp-ingestion packages/nxp-search packages/nxp-push packages/nxp-experience packages/nxp-agents packages/nxp-analytics)

[[ -d "env-config/$ENV" ]] || { echo "No env-config/$ENV"; exit 1; }

echo "==> Releasing $VERSION to $ORG ($ENV, $MODE)"
echo "Reminder: $ORG must already be on the Salesforce release that supports API 68.0."

if [[ "$MODE" == "source" ]]; then
  mkdir -p manifest
  sf project generate manifest --source-dir "${DIRS[@]}" --api-version 68.0 --name "release-$VERSION" --output-dir manifest
  echo "==> Validating (RunLocalTests)"
  JOB=$(sf project deploy validate --source-dir "${DIRS[@]}" --target-org "$ORG" --api-version 68.0 \
        --test-level RunLocalTests --wait 90 --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["id"])')
  echo "Validation job: $JOB"
  read -r -p "Quick-deploy $JOB to $ORG now? (yes/no) " ok
  [[ "$ok" == "yes" ]] || { echo "Stopped. Quick-deploy later: sf project deploy quick --job-id $JOB --target-org $ORG"; exit 0; }
  sf project deploy quick --job-id "$JOB" --target-org "$ORG" --wait 60
  echo "$VERSION $ENV $ORG $JOB $(date -u +%FT%TZ)" >> manifest/deployments.log
else
  [[ -f release/versions.json ]] || { echo "Create release/versions.json (see docs/deployment/deployment-guide.md)"; exit 1; }
  for pkg in $(python3 -c 'import json; [print(v) for v in json.load(open("release/versions.json"))["install"]]'); do
    echo "==> Installing $pkg"
    sf package install --package "$pkg" --target-org "$ORG" --wait 30 --no-prompt --security-type AdminsOnly
  done
fi

echo "==> env-config/$ENV"
(cd "env-config/$ENV" && sf project deploy start --source-dir force-app --target-org "$ORG" --api-version 68.0 --wait 15)

echo "==> Post-deploy"
sf apex run --file scripts/post-deploy/schedule-jobs.apex --target-org "$ORG"

cat <<MSG
Release finished. Complete docs/deployment/post-deployment-checklist.md:
  credentials, permission sets, agent activation, smoke test.
  First release in this org? Add the SAM.gov API key: Setup > Named Credentials > External Credentials >
  NXP SAM.gov > Principals > Default > parameter ApiKey. Steps: docs/deployment/deployment-guide.md#samgov-api-key
MSG
