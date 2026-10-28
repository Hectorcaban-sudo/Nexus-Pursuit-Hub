# UI screens

The Lightning app **Nexus Pursuit Hub** (`NXP_Pursuit_Hub`) has these tabs: Match Inbox, Gov Notices, My Searches, Gov Forecasts, Award Summaries, Gov Agencies, Gov Vendors, Contract Vehicles and Feed Console (admins). The Nexus Pursuit Assistant opens from the Agentforce panel on every page.

| Screen                 | Component                                            | Purpose                                                                                              | Main actions                                                                                   |
| ---------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Match Inbox            | `nxpMatchInbox` (tab)                                | New matches from my searches; one card per notice, best fit first                                    | Push to TechnoMile, Watch, Dismiss (with reason), bulk push, filter by search, sort            |
| My Searches            | `nxpSearchBuilder` (tab)                             | Build and edit searches with live preview and 13-week back-test; list of my and shared searches      | Describe it → Draft criteria, Save, Delete, settings (visibility, alerts, channels, auto-push) |
| Gov Notice record page | `NXP_Gov_Notice_Record_Page` with `nxpNoticeSummary` | Countdown, fit, facts, AI summary, full description, fit breakdown, versions, contacts, push history | Push / open TechnoMile record, Follow, Open on SAM.gov                                         |
| Push dialog            | `nxpPushDialog` (modal)                              | Exactly what will be sent, duplicate warning, documents                                              | Push / Link record, Cancel                                                                     |
| Feed Console           | `nxpFeedConsole` (tab)                               | One tile per feed and REST source: health, counts, last run; recent runs table; scheduler warning    | Run now (NXP Admin Access), Errors, Refresh                                                    |

Shared pieces: `nxpFitBadge` (fit tier colours: 75+ blue, 60–74 amber, below 60 grey) and `nxpUtils` (errors, toasts, formatting, debounce).

Mockups of these screens were reviewed before the build (Match Inbox, Search Builder, Notice Detail, Push dialog, Feed Console). The components follow them, using Lightning base components and SLDS so they render natively in Lightning Experience and on mobile.
