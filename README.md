# Nexus Pursuit Hub

Government opportunity intelligence on Salesforce. Nexus Pursuit Hub replaces the GovWin IQ subscription:

- **Feeds:** it ingests government feeds (SAM.gov, agency forecasts, USAspending awards, SAM.gov entities) and GSA eBuy RFQs received by e-mail.
- **Market intel:** forecasts, recompetes, vendor, agency and contract-vehicle views, with Watch alerts.
- **Searches:** each user builds their own saved searches and gets alerts on matches.
- **Push:** chosen notices become **Opportunity** records, where capture is managed.

![Solution architecture](docs/diagrams/01-solution-architecture.jpg)

|           |                                                                                                                               |
| --------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Platform  | Salesforce (Government Cloud supported), Salesforce DX source format, **API 68.0**                                            |
| Naming    | Every object and component starts with `NXP_` (LWCs: `nxp` + camelCase)                                                       |
| Packaging | Seven unlocked packages, no namespace. They can also be deployed straight from source with `sf project deploy`.               |
| AI        | Agentforce assistant built manually in Agentforce Builder; prompt templates run by batch Apex; Agent Script kept as reference |
| Release   | Scripted `sf` commands (`scripts/release.sh`), no CI/CD pipeline                                                              |

## What it does

| Capability                                                                                                                                                                                            | Where                                                                                    |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| **Standard feeds:** SAM.gov opportunities, entities, forecasts and USAspending awards                                                                                                                 | `nxp-ingestion` connectors on a Queueable pipeline or a scheduled batch                  |
| **Additional import channels:** Apex REST ingestion API, scheduled Apex batch, Apex callouts, Data Cloud Ingestion API                                                                                | `/services/apexrest/nxp/v1/notices`, `NXP_FeedFetchBatch`, `datacloud/`                  |
| **GSA eBuy RFQs by e-mail** (eBuy has no API): parsed by rules, optional AI fill-in, admin log with Reprocess                                                                                         | `NXP_Ebuy_Inbox` e-mail service, **Inbound Emails** tab (`nxpEmailLog`)                  |
| Dedupe across sources, amendment versioning, change events                                                                                                                                            | `NXP_IngestionService`                                                                   |
| Rules-based fit score against the company profile                                                                                                                                                     | `NXP_FitScoreService`, `NXP_Fit_Rule__mdt`                                               |
| User-built saved searches with boolean keywords, live preview and a 13-week back-test; org templates to copy; matching against open notices on save; **Find similar** from a notice, with AI keywords | **My Searches** tab (`nxpSearchBuilder`)                                                 |
| Real-time (e-mail, bell), daily and weekly (e-mail) alerts; follow and watch alerts (bell); daily problems e-mail for admins                                                                          | `NXP_SearchMatchService`, `NXP_AlertService`, `NXP_DigestBatch`, `NXP_AdminDigestJob`    |
| Match Inbox: fit reasons; push, watch or dismiss, one card or in bulk                                                                                                                                 | **Match Inbox** tab (`nxpMatchInbox`)                                                    |
| Push to Opportunity: manual, bulk, auto-push rules and post-push sync                                                                                                                                 | `nxp-push`, `NXP_Push_Mapping__mdt`                                                      |
| Forecasts board and recompete timeline, with Watch                                                                                                                                                    | **Forecasts** and **Recompetes** tabs                                                    |
| Vendor and agency profiles: awards, incumbents, what's coming, contacts                                                                                                                               | Gov Vendor and Gov Agency record pages                                                   |
| Vehicle portfolio: vehicles we hold, their notices and expiry; notices that need a vehicle we lack                                                                                                    | **Vehicle Portfolio** tab (`nxpVehiclePortfolio`)                                        |
| SAM.gov description text and attachments fetched for matched and high-fit notices, or on request                                                                                                      | `NXP_NoticeEnrichBatch`, `NXP_SamFileJob`                                                |
| Document Reader: AI reads notice PDFs (requirements, evaluation, dates, risks) and flags differences from the notice                                                                                  | Documents card and warning on the notice page (`nxpNoticeDocuments`, `nxpNoticeSummary`) |
| Daily AI-call limit                                                                                                                                                                                   | `AI_Max_Calls_Per_Day`, `NXP_AI_Usage__c`                                                |
| Nexus Pursuit Assistant (Agentforce) and AI summaries                                                                                                                                                 | `nxp-agents`                                                                             |
| Feed health and Run now for admins                                                                                                                                                                    | **Feed Console** tab (`nxpFeedConsole`)                                                  |
| Admin-only e-mail log; every setting in one screen with health checks and change history                                                                                                              | **Inbound Emails** and **Settings** tabs (`nxpAdminSettings`), `NXP_Setting__mdt`        |
| Reports and dashboards: market and activity, operations, adoption and the GovWin parallel run                                                                                                         | `nxp-analytics` ([reports and dashboards](docs/design/reports-and-dashboards.md))        |

## Repository layout

```text
packages/
  nxp-core/        objects, metadata types, platform event, shared Apex, fit score
  nxp-ingestion/   connectors, pipeline, batches, Apex REST API, eBuy e-mail intake, credentials, feed config
  nxp-search/      saved searches, matcher, alerts, digests, market and vehicle screens' data, watches
  nxp-push/        push target, push service, post-push sync, push mappings
  nxp-experience/  Lightning app, tabs, record page, LWCs
  nxp-agents/      agent actions, AI jobs (Notice Analyst, Document Reader, eBuy AI), permission sets
  nxp-analytics/   report types, reports and dashboards (installs last)
    reference/     Agent Script + prompt templates (not deployed in Government Cloud)
env-config/<env>/  per-environment settings (each a small DX project)
datacloud/         Ingestion API schema and bulk upload script
data/              seed data and API fixtures
scripts/           install, sample data, functional test, validate, release, uninstall (.sh and .ps1)
docs/              architecture, design, guides, deployment, ADRs, diagrams (JPG)
```

## Quick start (development)

Prerequisites: VS Code with the Salesforce Extension Pack, Salesforce CLI (`sf`), Node 20+, and a Dev Hub or developer sandbox.

```bash
git clone https://github.com/Hectorcaban-sudo/Nexus-Pursuit-Hub.git
cd Nexus-Pursuit-Hub
npm install
sf org login web --alias nxp-devhub --set-default-dev-hub
scripts/dev-setup.sh                 # scratch org "nxp-dev" with sample data
# or: scripts/dev-setup.sh --org my-sandbox
```

Windows PowerShell:

```powershell
.\scripts\dev-setup.ps1                    # or: .\scripts\dev-setup.ps1 -Org my-sandbox
```

Then add your SAM.gov API key. In **Setup → Named Credentials → External Credentials → NXP SAM.gov → Principals → Default**, add an authentication parameter named `ApiKey` (how to get one: [SAM.gov API key](docs/deployment/deployment-guide.md#samgov-api-key)).

Test it with the sample data, then run the pre-PR checks:

```bash
scripts/test-functional.sh --org nxp-dev   # REST API + end-to-end checks   (.\scripts\test-functional.ps1 -Org nxp-dev)
scripts/validate.sh --org nxp-dev          # Prettier, ESLint, Jest, check-only deploy with Apex tests
```

Every script has a PowerShell twin; see [scripts/README.md](scripts/README.md). The [testing guide](docs/guides/testing-guide.md#test-with-sample-data) explains the sample data and has a walkthrough of every screen. To remove Nexus from an org: `scripts/uninstall.sh --org <alias>` ([uninstall](docs/deployment/deployment-guide.md#uninstall)).

## Documentation

Start at **[docs/README.md](docs/README.md)**. The most-used pages:

| Audience      | Read                                                                                                                                                                                                   |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Everyone      | [Solution architecture](docs/architecture/solution-architecture.md) · [Functional design](docs/design/functional-design.md)                                                                            |
| Developers    | [Developer guide](docs/guides/developer-guide.md) · [Technical architecture](docs/architecture/technical-architecture.md) · [Testing guide](docs/guides/testing-guide.md)                              |
| Admins        | [How Nexus works](docs/guides/how-it-works.md) · [Admin guide](docs/guides/admin-guide.md) · [Training guide](docs/guides/training-guide.md) · [Agent manual build](docs/guides/agent-manual-build.md) |
| Release leads | [Deployment guide](docs/deployment/deployment-guide.md) · [Post-deployment checklist](docs/deployment/post-deployment-checklist.md)                                                                    |
| Integrators   | [REST ingestion API](docs/integration/rest-ingestion-api.md) · [Data Cloud ingestion](docs/integration/data-cloud-ingestion.md)                                                                        |
| BD users      | [How Nexus works](docs/guides/how-it-works.md) · [User guide](docs/guides/user-guide.md)                                                                                                               |

## Status

Version 1.0.x, October 2026:

- **Checked here:**
    - All Apex parses (prettier-plugin-apex) and passes a language-server check.
    - All XML is well-formed.
    - 51 Jest tests pass and ESLint is clean.
    - Every bash and PowerShell script parses.
- **Deployed to a sandbox** (staging) and the SAM.gov feed run there. Apex tests run in the org with `scripts/validate.sh --org <org>`.
- **Org-specific settings:** the push target and the Opportunity field mapping must be set per org ([admin guide](docs/guides/admin-guide.md#push-mapping)). The eBuy e-mail address, prompt templates, AI switches, e-mail deliverability and Remote Site Settings for SAM.gov files are also set up per org after deployment.
