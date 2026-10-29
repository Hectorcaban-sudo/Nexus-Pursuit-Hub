# UI screens

The Lightning app **Nexus Pursuit Hub** (`NXP_Pursuit_Hub`) has these tabs: Match Inbox, Gov Notices, My Searches, Forecasts, Recompetes, Gov Agencies, Gov Vendors, Contract Vehicles and Feed Console (admins). The Gov Forecasts and Award Summaries object tabs stay available from the App Launcher. The Nexus Pursuit Assistant opens from the Agentforce panel on every page.

| Screen                 | Component                                            | Purpose                                                                                                                                             | Main actions                                                                                                                   |
| ---------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Match Inbox            | `nxpMatchInbox` (tab)                                | New matches from my searches; one card per notice, best fit first                                                                                   | Push to TechnoMile, Watch, Dismiss (with reason), bulk push, filter by search, sort                                            |
| My Searches            | `nxpSearchBuilder` (tab)                             | Build and edit searches with live preview and 13-week back-test; list of my and shared searches                                                     | Describe it → Draft criteria, Save, Delete, settings (visibility, alerts, channels, auto-push)                                 |
| Gov Notice record page | `NXP_Gov_Notice_Record_Page` with `nxpNoticeSummary` | Countdown, fit, facts, AI summary, full description, fit breakdown, versions, contacts, push history                                                | Push / open TechnoMile record, Follow, Open on SAM.gov                                                                         |
| Push dialog            | `nxpPushDialog` (modal)                              | Exactly what will be sent, duplicate warning, documents                                                                                             | Push / Link record, Cancel                                                                                                     |
| Forecasts              | `nxpForecastBoard` (tab `NXP_Forecasts`)             | Agency forecasts grouped by expected solicitation date (90 days, 3–6 months, 6–12 months, later, released); profile fit per card                    | Watch (alert when released), open forecast or the notice it became, filters (agency, NAICS, set-aside, FY, fits profile)       |
| Recompetes             | `nxpRecompeteTimeline` (tab `NXP_Recompetes`)        | Award summaries on a 4-year timeline with today marked; incumbent, value, months left, follow-on (confirmed predecessor, likely notice or forecast) | Select an award for details, Watch (alert on a likely follow-on), open incumbent, follow-on or award; window 6/12/18/24 months |
| Gov Vendor record page | `NXP_Gov_Vendor_Record_Page` with `nxpVendorProfile` | Competitor profile: identity, totals, awards, NAICS/agency/set-aside overlap with our profile, open notices where they're the likely incumbent      | Watch (alert on new awards), Refresh from SAM.gov (NXP Admin Access)                                                           |
| Feed Console           | `nxpFeedConsole` (tab)                               | One tile per feed and REST source: health, counts, last run; recent runs table; scheduler warning                                                   | Run now (NXP Admin Access), Errors, Refresh                                                                                    |

Shared pieces: `nxpFitBadge` (fit tier colours: 75+ blue, 60–74 amber, below 60 grey) and `nxpUtils` (errors, toasts, formatting, debounce).

Mockups of these screens were reviewed before the build (Match Inbox, Search Builder, Notice Detail, Push dialog, Feed Console; then Forecasts, Recompetes and Vendor profile). The components follow them, using Lightning base components and SLDS so they render natively in Lightning Experience and on mobile.

## Watching forecasts, awards and vendors

Watch uses the same `NXP_Follow__c` object as following a notice, with a `Forecast__c`, `Award__c` or `Vendor__c` lookup (one row per user and record, keyed by `Follow_Key__c`). `NXP_WatchService` sends an **NXP Match Alert** notification:

| Watched  | Alert when                                                                                                                           | Raised from                                                          |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| Forecast | A new notice is linked to it (released)                                                                                              | `NXP_SearchMatchService.handleEvents` (new-notice events)            |
| Award    | A new notice names it as predecessor, or has the same agency and NAICS while the award ends within 18 months or ended in the last 12 | `NXP_SearchMatchService.handleEvents`                                |
| Vendor   | A new award summary is created for the vendor                                                                                        | `NXP_AwardSummaryTrigger` (bypass: `Bypass_NXP_AwardSummaryTrigger`) |

Alerts never block ingestion: failures are logged to NXP Logs as warnings.
