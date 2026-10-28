# Apex REST ingestion API

Other systems push government notices into Nexus Pursuit Hub through these endpoints. Records go through the same processing as the standard feeds: dedupe, versioning, scoring, matching, alerts and push.

| Method | Path                                     | Purpose                                                                 |
| ------ | ---------------------------------------- | ----------------------------------------------------------------------- |
| POST   | `/services/apexrest/nxp/v1/notices`      | Create or update notices                                                |
| POST   | `/services/apexrest/nxp/v1/task-orders`  | Same, defaulting `noticeType` to _Task Order_ and linking `vehicleCode` |
| GET    | `/services/apexrest/nxp/v1/runs/{runId}` | Status of a call (feed run)                                             |

## Authentication

Set up OAuth 2.0 client credentials through an External Client App (or connected app) whose run-as user is a dedicated integration user. That user gets only the **NXP_Integration** permission set. Calls without the `NXP_Integration_Access` custom permission get **403**.

## Request

Headers:

- `Authorization: Bearer <token>`
- `Content-Type: application/json`
- `Idempotency-Key: <unique per logical request>` (recommended)

```json
{
    "source": "partner",
    "records": [
        {
            "sourceId": "9",
            "title": "Network Segmentation Pilot",
            "solicitationNumber": "SAMPLE-SOL-0005",
            "noticeType": "Sources Sought",
            "agencyPath": "Homeland Security > Customs and Border Protection",
            "agencyCodePath": "070.7014",
            "office": "Office of Information and Technology",
            "naics": "541512",
            "psc": "DA01",
            "setAside": "Total Small Business Set-Aside",
            "estimatedValue": 1500000,
            "postedDate": "2026-10-25",
            "responseDue": "2026-11-20T17:00:00Z",
            "archiveDate": "2026-12-31",
            "description": "Pilot of micro-segmentation for border systems.",
            "url": "https://example.gov/notices/9",
            "placeOfPerformance": "Washington, DC",
            "market": "Federal",
            "status": "Active",
            "vehicleCode": "OASIS+",
            "contacts": [
                { "name": "Sam Lee", "email": "sam.lee@example.gov", "phone": "555-0100", "role": "Program Manager" }
            ]
        }
    ]
}
```

| Field        | Rules                                                                                                     |
| ------------ | --------------------------------------------------------------------------------------------------------- |
| `source`     | Required. 1–40 letters, digits, `_` or `-`. Becomes feed name `REST_<source>` and the notice key prefix.  |
| `records`    | Required, 1–200 per call (`NXP_Setting.Rest_Max_Records`).                                                |
| `sourceId`   | Required unless `noticeId` is given. Notice ID becomes `<SOURCE>:<sourceId>`.                             |
| `noticeId`   | Optional. Use the SAM.gov notice ID when the source knows it, so the record merges with the SAM.gov feed. |
| `title`      | Required.                                                                                                 |
| `noticeType` | Normalized (for example "sources sought" → Sources Sought); unknown values become _Other_.                |
| `agencyPath` | Outermost first, separated by `>` or `›`.                                                                 |
| Dates        | `YYYY-MM-DD`, `MM/DD/YYYY` or ISO 8601 with `Z` or an offset.                                             |
| `role`       | Contracting Officer, Contract Specialist, Program Manager, Other.                                         |

A record with the same solicitation number as an existing notice updates that notice and adds the source to its lineage.

## Response

```json
{
    "runId": "a0X...",
    "received": 1,
    "created": 1,
    "updated": 0,
    "unchanged": 0,
    "rejected": 0,
    "results": [
        { "sourceId": "9", "noticeId": "PARTNER:9", "status": "Created", "recordId": "a0Y...", "message": null }
    ]
}
```

| HTTP | When                                                                                                                                                                                                      |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 200  | Processed. Check per-record `status`: Created, Updated, Unchanged, Rejected (with `message`). A replay with the same `Idempotency-Key` returns the stored response with header `Idempotent-Replay: true`. |
| 400  | Body is not JSON, `source` invalid, or `records` empty                                                                                                                                                    |
| 403  | Caller lacks NXP_Integration                                                                                                                                                                              |
| 413  | More records than allowed                                                                                                                                                                                 |
| 500  | Unexpected error (logged to NXP Logs)                                                                                                                                                                     |

## Example

```bash
curl -sS -X POST "$INSTANCE/services/apexrest/nxp/v1/notices" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -H "Idempotency-Key: partner-2026-10-28-0001" \
  --data @data/fixtures/rest-notices-request.json
```

Each call appears on the Feed Console as a tile named `<source> (Apex REST)`.
