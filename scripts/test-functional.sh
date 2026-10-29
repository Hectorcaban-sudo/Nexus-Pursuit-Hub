#!/usr/bin/env bash
# Functional test of Nexus Pursuit Hub in a dev or QA org that has the sample data loaded.
#
#   scripts/test-functional.sh --org nxp-dev                 # end-to-end smoke test (incl. REST API)
#   scripts/test-functional.sh --org nxp-dev --apex-tests    # also run every Apex unit test
#
# Runs scripts/apex/smoke-test.apex, which saves its results in an NXP_Log__c row (Source NXP-SMOKE);
# this script reads that row, so results don't depend on the size of the debug log.
# Load the sample data first: scripts/load-sample-data.sh --org nxp-dev
# Exit code 0 when nothing failed, 1 otherwise. Checks are listed in docs/guides/testing-guide.md.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/common.sh

ORG=""
APEX_TESTS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org|-o) ORG="$2"; shift 2 ;;
    --apex-tests) APEX_TESTS=true; shift ;;
    --skip-rest) shift ;; # kept for compatibility; the REST check now runs inside the smoke test
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "Unknown option $1" ;;
  esac
done
[[ -n "$ORG" ]] || die "Give the org alias: --org <alias>"
require_sf

RESULTS=()
add() { RESULTS+=("$1|$2|$3"); }

# 1. End-to-end smoke test ----------------------------------------------------------------------
step "End-to-end smoke test (REST API, fit scoring, searches, matches, push, feeds, digest)"
# Two minutes of slack for clock differences between this computer and the org.
SINCE=$(date -u -d '-2 minutes' +%FT%TZ 2>/dev/null || date -u -v-2M +%FT%TZ)
if OUT=$(sf apex run --file scripts/apex/smoke-test.apex --target-org "$ORG" 2>&1); then
  QUERY="SELECT Message__c FROM NXP_Log__c WHERE Source__c = 'NXP-SMOKE' AND CreatedDate >= $SINCE ORDER BY CreatedDate DESC LIMIT 1"
  SAVED=$(sf data query --query "$QUERY" --target-org "$ORG" --json 2>/dev/null || true)
  # Message__c is one JSON string; turn its \n escapes back into lines.
  LINES=$(printf '%s\n' "$SAVED" | sed -n 's/^ *"Message__c": "\(.*\)",\{0,1\} *$/\1/p' | head -n 1 \
    | sed -e 's/\\n/\n/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g')
  if [[ -z "$LINES" ]]; then
    # Older smoke-test versions only wrote to the debug log.
    LINES=$(printf '%s\n' "$OUT" | grep '|USER_DEBUG|' | grep -o 'NXP-SMOKE|.*' | sed 's/^NXP-SMOKE|//' || true)
  fi
  grep -q '^SUMMARY|' <<<"$LINES" || add FAIL "Smoke test" "ran, but no results were found in NXP Logs or the debug log"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS='|' read -r status check detail <<<"$line"
    [[ "$status" == "SUMMARY" ]] && continue
    add "$status" "$check" "$detail"
  done <<<"$LINES"
else
  printf '%s\n' "$OUT"
  add FAIL "Smoke test" "anonymous Apex did not run (compile or runtime error above)"
fi

# 2. Apex unit tests (optional) -----------------------------------------------------------------
if [[ "$APEX_TESTS" == true ]]; then
  step "Apex unit tests (RunLocalTests, with coverage)"
  if sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 30 --target-org "$ORG"; then
    add PASS "Apex unit tests" "all local tests passed"
  else
    add FAIL "Apex unit tests" "see the test output above"
  fi
fi

# Report ----------------------------------------------------------------------------------------
step "Results for $ORG"
FAILS=0
for r in "${RESULTS[@]}"; do
  IFS='|' read -r status check detail <<<"$r"
  case "$status" in
    PASS) color=32 ;; FAIL) color=31; FAILS=$((FAILS + 1)) ;; WARN) color=33 ;; *) color=90 ;;
  esac
  printf '\033[%sm%-5s\033[0m %-22s %s\n' "$color" "$status" "$check" "$detail"
done
echo
if [[ $FAILS -eq 0 ]]; then
  printf '\033[32mAll checks passed (%s).\033[0m Next: the manual walkthrough in docs/guides/testing-guide.md\n' "${#RESULTS[@]}"
else
  printf '\033[31m%s of %s checks failed.\033[0m\n' "$FAILS" "${#RESULTS[@]}"
  exit 1
fi
