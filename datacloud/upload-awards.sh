#!/usr/bin/env bash
# Bulk-load a USAspending award extract into Data Cloud through the Ingestion API (bulk pattern).
# Runs on an approved job host outside Salesforce. Requires:
#   DC_TENANT   Data Cloud tenant endpoint (e.g. https://<tenant>.c360a.salesforce.com)
#   DC_TOKEN    Data Cloud access token (exchange a Salesforce OAuth token at /services/a360/token)
#   $1          CSV file with the NXP_Award columns (header row required, max 150 MB per batch)
set -euo pipefail
CSV="${1:?csv file}"
: "${DC_TENANT:?set DC_TENANT}" "${DC_TOKEN:?set DC_TOKEN}"
AUTH=(-H "Authorization: Bearer $DC_TOKEN")

JOB=$(curl -sS "${AUTH[@]}" -H "Content-Type: application/json" -X POST "$DC_TENANT/api/v1/ingest/jobs" \
  -d '{"object":"NXP_Award","sourceName":"NXP_Awards","operation":"upsert"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
echo "Job $JOB"
curl -sS "${AUTH[@]}" -H "Content-Type: text/csv" -X PUT "$DC_TENANT/api/v1/ingest/jobs/$JOB/batches" --data-binary @"$CSV" >/dev/null
curl -sS "${AUTH[@]}" -H "Content-Type: application/json" -X PATCH "$DC_TENANT/api/v1/ingest/jobs/$JOB" -d '{"state":"UploadComplete"}' >/dev/null
echo "Uploaded. Check status: curl -H 'Authorization: Bearer \$DC_TOKEN' $DC_TENANT/api/v1/ingest/jobs/$JOB"
