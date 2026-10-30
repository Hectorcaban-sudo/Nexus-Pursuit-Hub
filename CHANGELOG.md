# Changelog

## Unreleased

- **Reports and dashboards:** new seventh package `nxp-analytics` with 10 report types, 27 reports and 3 dynamic dashboards (_Nexus: Market and activity_; _Nexus: Operations_ and _Nexus: Adoption and GovWin cut-over_ in the admin folder). See [reports and dashboards](docs/design/reports-and-dashboards.md).
- **Data for them:** `NXP_Push_Log__c.Source__c` (Match Inbox, Notice Page, Bulk, Auto-Push, Assistant; `NXP_PushController.pushNoticeFrom`); `NXP_Usage__c` weekly usage log written when a Nexus screen opens (`nxpUtils.logUsage`); `NXP_GovWin_Alert__c` with `scripts/load-govwin-export` and `NXP_GovWinCompareBatch` for the GovWin parallel run; formulas `Fit_Band__c` and `Owner_Name__c`. Sample data adds 5 GovWin alerts; the smoke test checks the comparison, the usage log and that the reports and dashboards exist.
- **Document Reader:** PDFs attached to a notice (eBuy attachments, uploads) are read by AI with the `NXP_Document_Analysis` prompt template (File input) in `NXP_DocumentAnalysisJob`, one per job. `NXP_DocumentAnalysisParser` keeps only known fields (requirements, deliverables, evaluation factors, submission, key dates, terms, clearance, risks) and adds checks where the document disagrees with the notice (due date, NAICS, set-aside). Results are stored per file in `NXP_Document_Analysis__c` (controlled by the notice) and shown on the new **Documents** card (`nxpNoticeDocuments`) with Add documents and Analyze; the assistant gets **NXP Notice Documents**. Off until `Document_Analysis_Enabled` and `AI_Enabled`. The sample eBuy RFQ now carries a PDF statement of work; the smoke test checks the document row.
- **eBuy to TechnoMile:** the shipped Description push mapping now uses `Push_Details__c`, a notice formula with the source (_GSA eBuy RFQ_ for eBuy), Nexus ID, solicitation or RFQ number, vehicle, due date and link; `Contract_Vehicle_Code__c` (formula) lets you map the vehicle to a TechnoMile field. Sample data adds the auto-push search _SAMPLE - eBuy RFQs on our vehicles_ (Task Orders on held vehicles, fit 60), so the sample eBuy RFQ is pushed when it arrives; the smoke test checks it.
- **GSA eBuy e-mail intake:** eBuy has no API, so RFQ notification e-mails go to the `NXP_Ebuy_Inbox` e-mail service (`NXP_EbuyEmailHandler`). Each message is kept as an `NXP_Inbound_Email__c` (private, admins only) with its attachments as Files; `NXP_EbuyExtractJob` reads it with rules (`NXP_EbuyEmailParser`), optionally fills gaps with AI (`NXP_EbuyAiExtract`, prompt template `NXP_Ebuy_RFQ_Extract`, values checked by code), and ingests a _Task Order_ notice `EBUY:<RFQ number>` on the vehicle with the attachments linked. Unknown senders are rejected; executable and HTML attachments are dropped.
- **Inbound Emails** admin tab (`nxpEmailLog`, `NXP_EmailLogController`): every e-mail with status, what was read and the notice it became; Reprocess (with a typed RFQ number) and Ignore. Feed runs get an _Email_ channel.
- New settings `Ebuy_Allowed_Senders`, `Ebuy_Default_Vehicle`, `Ebuy_AI_Template`, `Ebuy_AI_Read_Attachments`, `Ebuy_Share_Files_With_Notice`. Sample data adds a made-up eBuy e-mail (`scripts/apex/seed-ebuy-email.apex`); the smoke test checks it.
- **Vehicle Portfolio:** new tab (`nxpVehiclePortfolio`, `NXP_VehicleController`) replacing the Contract Vehicles object tab in the app nav: vehicles we hold with their open notices, expiry and task-order inbox status, and open notices that need a vehicle we don't hold (with Follow). Admins can mark a vehicle held or not held, which re-scores its open notices.
- **Fix:** the Vehicle fit rule gave points whenever a notice had any vehicle and the profile listed any vehicle code; it now checks that we hold that vehicle (`NXP_FitScoreService.isHeld`). It still ships off.
- **Sample data:** a third vehicle (CIO-SP4, not held), expiry dates and an inbox address; `SAMPLE-0005`…`0007` are linked to vehicles. The smoke test checks the vehicle portfolio.
- **Agency profile:** Gov Agency record page with `nxpAgencyProfile` (`NXP_MarketController.getAgencyProfile`): what's coming, incumbents, NAICS mix, saved-search coverage, sub-agencies, offices, contacts. **Watch** an agency (`NXP_Follow__c.Agency__c`) for an alert on every new notice it or its sub-agencies post. Sample data adds contacts and offices.
- **Fix:** date-only values (due dates, period ends, forecast dates) showed one day early in US time zones; `nxpUtils.toDate` now reads `YYYY-MM-DD` as a local date.
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
