#!/usr/bin/env bash
# Run before every pull request (and by release.sh before every deployment).
#
#   scripts/validate.sh                 # local checks only: format, lint, Jest
#   scripts/validate.sh --org nxp-dev   # plus a check-only deployment with local Apex tests
set -euo pipefail
cd "$(dirname "$0")/.."

ORG=""
[[ "${1:-}" == "--org" ]] && ORG="${2:-}"

echo "==> Prettier (Apex, LWC)"
npx prettier --check "packages/**/*.{cls,trigger}" "packages/**/lwc/**/*.{js,html,css}"

echo "==> ESLint (LWC)"
npx eslint "packages/**/lwc/**/*.js"

echo "==> Jest (LWC)"
npm run --silent test:unit

if command -v sf >/dev/null && sf plugins inspect @salesforce/plugin-code-analyzer >/dev/null 2>&1; then
  echo "==> Code Analyzer"
  sf code-analyzer run --workspace packages --severity-threshold 2 --view table
else
  echo "==> Code Analyzer not installed; skipping (sf plugins install code-analyzer)"
fi

if [[ -n "$ORG" ]]; then
  echo "==> Check-only deployment to $ORG with RunLocalTests"
  sf project deploy validate \
    --source-dir packages/nxp-core packages/nxp-ingestion packages/nxp-search \
    packages/nxp-push packages/nxp-experience packages/nxp-agents \
    --target-org "$ORG" --api-version 68.0 --test-level RunLocalTests --coverage-formatters text --wait 60
fi
echo "==> All checks passed"
