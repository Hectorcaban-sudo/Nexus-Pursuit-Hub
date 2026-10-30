#!/usr/bin/env bash
# Create unlocked package versions in dependency order (Dev Hub = production org).
#   scripts/create-package-versions.sh <devhub-alias> [installation-key]
# First time only, create the packages:
#   for p in nxp-core nxp-ingestion nxp-search nxp-push nxp-experience nxp-agents nxp-analytics; do
#     sf package create --name $p --package-type Unlocked --path packages/$p --no-namespace --target-dev-hub <devhub>; done
set -euo pipefail
cd "$(dirname "$0")/.."
HUB="${1:?dev hub alias}"
KEY="${2:-}"
for p in nxp-core nxp-ingestion nxp-search nxp-push nxp-experience nxp-agents nxp-analytics; do
  echo "==> $p"
  if [[ -n "$KEY" ]]; then
    sf package version create --package "$p" --installation-key "$KEY" --code-coverage --target-dev-hub "$HUB" --wait 60
  else
    sf package version create --package "$p" --installation-key-bypass --code-coverage --target-dev-hub "$HUB" --wait 60
  fi
done
echo "Promote each version after QA: sf package version promote --package <alias@x.y.z-n> --target-dev-hub $HUB"
