# Shared helpers for the bash scripts in scripts/. Sourced, not run:  . "$(dirname "$0")/lib/common.sh"
# The PowerShell scripts use scripts/lib/common.ps1, which has the same helpers.

API_VERSION="68.0"
# Install order. Uninstall uses the reverse.
PACKAGE_DIRS=(packages/nxp-core packages/nxp-ingestion packages/nxp-search packages/nxp-push packages/nxp-experience packages/nxp-agents)

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

require_sf() {
  command -v sf >/dev/null || die "Salesforce CLI (sf) not found. Install it: npm install --global @salesforce/cli"
}

# Value of a top-level "key": "value" or "key": true/false/number in pretty-printed sf --json output.
json_value() { sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\} *$/\1/p" | head -n 1; }

# run_apex <file> <org>: runs anonymous Apex, prints only its System.debug lines, stops on failure.
run_apex() {
  local file="$1" org="$2" out
  if ! out=$(sf apex run --file "$file" --target-org "$org" 2>&1); then
    printf '%s\n' "$out"
    die "Anonymous Apex failed: $file"
  fi
  printf '%s\n' "$out" | sed -n 's/.*|USER_DEBUG|\[[0-9]*\]|[A-Z]*|/   /p'
}

# is_production <org>: true for a production org (not a sandbox, not a scratch or trial org).
is_production() {
  local out
  out=$(sf data query --query "SELECT IsSandbox, TrialExpirationDate FROM Organization" --target-org "$1" --json 2>/dev/null) || return 1
  printf '%s\n' "$out" | grep -q '"IsSandbox": false' && printf '%s\n' "$out" | grep -q '"TrialExpirationDate": null'
}
