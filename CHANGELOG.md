# Changelog

## Unreleased

- **Fixes from the first org deployment:**
    - `NXP_HttpClient.CalloutFailure` renamed `CalloutFailureException` (Apex exception classes must end in "Exception").
    - Reserved words no longer used as variable names: `number` (`NXP_CriteriaDraftService`); `any`, `inner`, `end` (`NXP_KeywordExpression`).
    - `NXP_NoticeAnalystJob` no longer filters on the long text field `AI_Change_Summary__c`; already-summarized versions are skipped in Apex.
    - `NXP_Public_API` External Credential uses the Custom protocol with a `Default` principal (no parameters), because orgs reject `NoAuthentication`; `NXP_Admin` gets access to that principal.
    - Gov Notice record page: removed `Replace` region modes.
    - `NXP_User`: Edit on `NXP_Follow__c`, which Delete requires.
    - `NXP_PushService.target()`: if/else instead of a ternary between an interface and a class.
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
