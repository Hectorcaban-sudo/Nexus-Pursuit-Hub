# Changelog

## Unreleased

- **Market screens:** Forecasts tab (`nxpForecastBoard`), Recompetes tab (`nxpRecompeteTimeline`) and a Gov Vendor record page with `nxpVendorProfile`, backed by `NXP_MarketController`.
- **Watch** forecasts, awards and vendors (`NXP_Follow__c` gets `Forecast__c`, `Award__c`, `Vendor__c`); `NXP_WatchService` alerts when a forecast is released, a likely follow-on to an award is posted, or a vendor wins an award (`NXP_AwardSummaryTrigger`).
- **Refresh from SAM.gov** on the vendor profile (admins).
- **Fix:** `NXP_User` could not follow a notice (no edit access on `NXP_Follow__c.Gov_Notice__c` and `Follow_Key__c`).
- **Sample market data:** 4 vendors, 6 award summaries and 3 forecasts (`data/seed/4-…6-…csv`; notices are now `7-…csv`), linked to the sample notices, with dates set relative to today. The smoke test checks Find Incumbent, Recompete Query and the forecast link.
- **Functional test:** the REST check now calls the REST ingestion resource inside the smoke test (an access token from `sf org display` was rejected with `INVALID_AUTH_HEADER`), and the smoke test saves its results in an `NXP_Log__c` row (Source `NXP-SMOKE`) that the runners read, instead of relying on the end of a possibly truncated debug log.
- **Notice Analyst schedule:** two jobs (`:15`, `:45`); Apex cron takes one minute value per job.
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
