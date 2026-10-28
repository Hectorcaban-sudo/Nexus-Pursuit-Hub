# Data Cloud ingestion (bulk awards)

Bulk award history (millions of USAspending/FPDS rows) belongs in Data Cloud, not core storage. It is loaded with the **Data Cloud Ingestion API** (bulk pattern) from an approved job host outside Salesforce.

## One-time setup (Data Cloud Setup)

1. **Ingestion API → New**, name `NXP_Awards`; upload `datacloud/NXP_Awards.schema.yaml`.
2. **Data Streams → New → Ingestion API → NXP_Awards → NXP_Award**:
    - Category _Other_.
    - Primary key `award_key`.
    - Record modified field `last_modified`.
3. Map the DLO to an **Award** DMO (custom or standard), mapping PIID, agency, recipient UEI, NAICS, amounts and dates.
4. Create a connected app or External Client App with the `cdp_ingest_api` scope for the job host.
5. Optional: create a calculated insight for agency spend by NAICS and fiscal year.

## Weekly load

```bash
export DC_TENANT=https://<tenant>.c360a.salesforce.com
export DC_TOKEN=<data cloud token>
datacloud/upload-awards.sh awards-2026-10-26.csv
```

The script creates an upsert job, uploads the CSV batch and marks the upload complete. Split files over 150 MB.

## How core uses award data

- `USAspending_Awards` (Apex callouts) keeps a targeted, recent slice in `NXP_Award_Summary__c` for incumbents and recompetes (_NXP Find Incumbent_, _NXP Recompete Query_).
- Analysts use the Data Cloud Award DMO for history and market sizing (Data Cloud reports, Tableau, segments).
- When Apex needs history for a specific award, copy it into `NXP_Award_Summary__c` (upsert on `PIID__c`) through the REST API or a Data Cloud-triggered flow.

Keep the Data Cloud objects and mapping steps in this runbook. Whatever Data Cloud metadata your org can retrieve, retrieve into `datacloud/` and commit.
