# Changelog

## Unreleased

- **PowerShell scripts:** a `.ps1` version of every script (`dev-setup`, `validate`, `release`, `create-package-versions`, `datacloud/upload-awards`), sharing `scripts/lib/common.ps1`. Windows PowerShell 5.1 and PowerShell 7.
- **Uninstall:** `scripts/uninstall.sh` and `.ps1`, for source-deployed orgs (destructive deploys, dependents first) and for package installs.
- **Sample data:** CSV seed files upserted by external ID (re-runnable), dates set relative to today, three saved searches with matches, and `--reset` / `--delete`. `load-sample-data.sh` and `.ps1`.
- **Functional test:** `test-functional.sh` and `.ps1`. Checks the REST ingestion API and idempotency, then runs `scripts/apex/smoke-test.apex` end to end.
- **Docs:** the testing guide has a sample-data section and a screen-by-screen walkthrough; the deployment guide has an uninstall section; new `scripts/README.md`.
- `.gitattributes` keeps `.sh` and `.csv` files on LF line endings on Windows checkouts.

## 1.0.0 (2026-10-28)

First build of Nexus Pursuit Hub.

- **Feeds:** SAM.gov opportunities, entity, agency forecasts, USAspending awards, through a Queueable pipeline or a scheduled batch.
- **Additional import channels:** Apex REST ingestion API (`/nxp/v1/notices`, `/task-orders`, `/runs`), batch, on-demand callouts, Data Cloud Ingestion API (schema and upload script).
- **Processing:** cross-source dedupe, amendment versioning with field-level diffs, change events, agency hierarchy, contacts, forecast linking, description enrichment.
- **Scoring:** rules-based fit score with a per-rule breakdown.
- **Search:** saved searches with boolean keywords, plain-English drafting, live preview and 13-week back-test.
- **Alerts:** real-time, daily and weekly alerts; follow alerts; team and org sharing.
- **Experience:** Match Inbox, My Searches, Gov Notice page, push dialog and Feed Console (LWC).
- **Push to TechnoMile:** manual, bulk, auto-push and agent pushes; duplicate check; document links; push log, retry and post-push sync.
- **Agents:** Nexus Pursuit Assistant actions (11), AI summaries and amendment summaries via prompt templates, and Agent Script reference.
- **Security:** permission sets NXP_User, NXP_Power_User, NXP_Admin, NXP_Integration.
- **Tooling:** scripts (dev setup, validate, release, package versions, post-deploy), seed data, documentation and diagrams.
