#!/usr/bin/env bash
# Functional test of Nexus Pursuit Hub in a dev or QA org that has the sample data loaded.
#
#   scripts/test-functional.sh --org nxp-dev                 # REST API + end-to-end smoke test
#   scripts/test-functional.sh --org nxp-dev --apex-tests    # also run every Apex unit test
#   scripts/test-functional.sh --org nxp-dev --skip-rest     # skip the REST ingestion API check
#
# Load the sample data first: scripts/load-sample-data.sh --org nxp-dev
# Exit code 0 when nothing failed, 1 otherwise. Checks are listed in docs/guides/testing-guide.md.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/common.sh

ORG=""
APEX_TESTS=false
SKIP_REST=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org|-o) ORG="$2"; shift 2 ;;
    --apex-tests) APEX_TESTS=true; shift ;;
    --skip-rest) SKIP_REST=true; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "Unknown option $1" ;;
  esac
done
[[ -n "$ORG" ]] || die "Give the org alias: --org <alias>"
require_sf

RESULTS=()
add() { RESULTS+=("$1|$2|$3"); }

# 1. Apex REST ingestion API -------------------------------------------------------------------
if [[ "$SKIP_REST" != true ]]; then
  step "Apex REST ingestion API (POST /services/apexrest/nxp/v1/notices)"
  INFO=$(sf org display --target-org "$ORG" --json)
  TOKEN=$(printf '%s\n' "$INFO" | json_value accessToken)
  URL=$(printf '%s\n' "$INFO" | json_value instanceUrl)
  TODAY=$(date -u +%F)
  DUE=$(date -u -d '+30 days' +%F 2>/dev/null || date -u -v+30d +%F)
  BODY=$(sed -e "s/{{TODAY}}/$TODAY/" -e "s/{{DUE_30}}/$DUE/" data/fixtures/rest-sample-notice.json)
  KEY="nxp-functional-test-$(date +%s)"
  ENDPOINT="$URL/services/apexrest/nxp/v1/notices"
  if [[ -z "$TOKEN" || -z "$URL" ]]; then
    add WARN "REST ingestion" "could not read the access token from 'sf org display'; skipped"
  else
    RESP=$(curl -sS -w $'\n%{http_code}' -X POST "$ENDPOINT" -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" -H "Idempotency-Key: $KEY" --data "$BODY" || true)
    CODE=${RESP##*$'\n'}
    JSON=${RESP%$'\n'*}
    if [[ "$CODE" == "200" ]] && grep -q '"rejected":0' <<<"$JSON" && grep -qE '"(created|updated|unchanged)":1' <<<"$JSON"; then
      add PASS "REST ingestion" "HTTP 200, SAMPLE-REST-0001 accepted: $(grep -oE '"(created|updated|unchanged)":[0-9]+' <<<"$JSON" | tr '\n' ' ')"
    else
      add FAIL "REST ingestion" "HTTP $CODE $JSON (the user needs the NXP_Integration or NXP_Admin permission set)"
    fi
    HEADERS=$(curl -sS -D - -o /dev/null -X POST "$ENDPOINT" -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" -H "Idempotency-Key: $KEY" --data "$BODY" || true)
    if grep -qi '^Idempotent-Replay: *true' <<<"$HEADERS"; then
      add PASS "REST idempotency" "same Idempotency-Key replayed the first response"
    else
      add FAIL "REST idempotency" "second call with the same Idempotency-Key was not a replay"
    fi
  fi
fi

# 2. End-to-end smoke test (scripts/apex/smoke-test.apex) ---------------------------------------
step "End-to-end smoke test (fit scoring, searches, matches, push, feeds, digest)"
if OUT=$(sf apex run --file scripts/apex/smoke-test.apex --target-org "$ORG" 2>&1); then
  grep -q 'USER_DEBUG.*NXP-SMOKE|SUMMARY' <<<"$OUT" || add FAIL "Smoke test" "no results in the debug log (check the org's debug log levels)"
  while IFS= read -r line; do
    IFS='|' read -r _ status check detail <<<"$line"
    [[ "$status" == "SUMMARY" ]] && continue
    add "$status" "$check" "$detail"
  done < <(printf '%s\n' "$OUT" | grep '|USER_DEBUG|' | grep -o 'NXP-SMOKE|.*')
else
  printf '%s\n' "$OUT"
  add FAIL "Smoke test" "anonymous Apex did not run (compile or runtime error above)"
fi

# 3. Apex unit tests (optional) -----------------------------------------------------------------
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
