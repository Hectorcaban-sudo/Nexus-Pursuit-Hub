# Reports and dashboards

Nexus ships standard Salesforce reports and dashboards in the `nxp-analytics` package, so admins can filter, schedule,
subscribe to and change them without code. Pipeline and win-rate reporting stays in TechnoMile.

## Dashboards

| Dashboard                               | Folder            | For                       | Shows                                                                                                                                                                                                         |
| --------------------------------------- | ----------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Nexus: Market and activity**          | Nexus Pursuit Hub | BD users, leads, managers | New notices (30 days), matches, pushes, high-fit notices about to be missed; new notices per week by source; match outcomes; pushes per month by source; fit bands; eBuy RFQs per vehicle; matches per search |
| **Nexus: Operations**                   | Nexus Admin       | Nexus admins              | Failed feed runs, push failures, eBuy e-mails needing review, errors; runs per feed and status; records read per day; push results; eBuy inbox and Document Reader by status; log entries per day             |
| **Nexus: Adoption and GovWin cut-over** | Nexus Admin       | Project lead, admins      | Active users this week, saved searches, GovWin alerts caught; weekly active users; GovWin catch rate; searches per user; where pushes come from; screen views per user                                        |

All three are **dynamic dashboards** (they run as the person viewing them), so each viewer sees only the records they
can see. Saved searches are private, so on the market dashboard a BD user sees their own searches and matches, and an
admin sees everyone's. Dynamic dashboards count against an org limit (5 in Enterprise Edition, 10 in Unlimited).

## Reports

27 reports, all named `NXP - …` (folder _Nexus Pursuit Hub_) or `NXP Admin - …` (folder _Nexus Admin_). Every
dashboard component links to its report. The main ones:

| Report                                           | Use it to                                                               |
| ------------------------------------------------ | ----------------------------------------------------------------------- |
| NXP - High-fit notices due soon, not pushed      | Daily check for notices worth a look before they close                  |
| NXP - Matches by saved search                    | See which searches produce matches that get pushed, and which are noise |
| NXP - Pushes by month and source                 | Track how much work flows to TechnoMile, and from where                 |
| NXP Admin - Feed runs by feed / Failed feed runs | Feed health                                                             |
| NXP Admin - Inbound emails needing review        | eBuy e-mails to fix and reprocess                                       |
| NXP Admin - GovWin parallel run                  | GovWin alerts Nexus missed (In Nexus, no search matched; Not in Nexus)  |

Report types (`NXP Notices`, `NXP Saved Searches with Matches`, `NXP Saved Searches`, `NXP Push Logs`, `NXP Feed Runs`,
`NXP Inbound Emails`, `NXP Document Analyses`, `NXP Logs`, `NXP Usage`, `NXP GovWin Alerts`) are available for people to
build their own reports.

## Data behind the adoption dashboard

| Data                   | Where it comes from                                                                                                                                                                           |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Weekly active users    | `NXP_Usage__c`: one row per user per week, written when the user opens a Nexus screen (`NXP_UsageService`). Only the screen name and a count are kept. Private; only `NXP_Admin` can read it. |
| Where pushes come from | `NXP_Push_Log__c.Source__c`: Match Inbox, Notice Page, Bulk, Auto-Push, Assistant, Sync                                                                                                       |
| GovWin catch rate      | `NXP_GovWin_Alert__c`, loaded weekly from a GovWin export with `scripts/load-govwin-export` and compared by `NXP_GovWinCompareBatch` (see [data/govwin](../../data/govwin/README.md))         |
| Searches per user      | `NXP_Saved_Search__c.Owner_Name__c` (formula)                                                                                                                                                 |
| Fit bands              | `NXP_Gov_Notice__c.Fit_Band__c` (formula)                                                                                                                                                     |

## After deployment

Folders are deployed without sharing, because sharing depends on your groups:

1. **Reports → Folders → Nexus Pursuit Hub** and **Dashboards → Folders → Nexus Pursuit Hub**: Share → _All Internal Users_ (or your BD group), **View**.
2. **Nexus Admin** (reports and dashboards): share with your Nexus admins and the project lead, **View**; keep it away from general users (it shows e-mail senders, errors and per-user activity).
3. Optional: subscribe the leads to _Nexus: Market and activity_ (weekly) and the admins to _Nexus: Operations_ (daily).

## Changing them

Edit reports and dashboards in the org, then retrieve them into `packages/nxp-analytics` so the next release keeps the
change. The shipped set was generated by `scripts/lib/generate-analytics.py`; regenerate with
`python3 scripts/lib/generate-analytics.py .` only if you want to start again from that set.
