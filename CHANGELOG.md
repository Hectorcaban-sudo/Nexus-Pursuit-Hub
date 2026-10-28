# Changelog

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
