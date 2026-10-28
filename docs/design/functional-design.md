# Functional design

## Users

| Persona                  | Uses Nexus Pursuit Hub to                                                     |
| ------------------------ | ----------------------------------------------------------------------------- |
| BD / opportunity analyst | Build searches, triage the Match Inbox, push good notices to TechnoMile       |
| Capture manager          | Follow notices, see amendments flow into pushed TechnoMile records            |
| BD lead (Power User)     | Share team searches, turn on auto-push, bulk push                             |
| Admin                    | Configure feeds, credentials, fit rules, push mapping; watch the Feed Console |
| Integration (system)     | Push notices in through the REST API                                          |

## User stories (version 1)

| #   | As a…           | I can…                                                                                                                                          | Delivered by                   |
| --- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| 1   | BD user         | build a search with keywords (AND/OR/NOT, phrases, prefixes), buyer, NAICS, PSC, set-aside, notice type, value, due date, place and minimum fit | My Searches tab                |
| 2   | BD user         | describe a search in plain English and get the criteria filled in                                                                               | _Describe it_ / Draft criteria |
| 3   | BD user         | see how many notices match now and per week over 13 weeks before saving                                                                         | Live preview                   |
| 4   | BD user         | choose real-time, daily, weekly or no alerts, and the channels                                                                                  | Alert settings                 |
| 5   | BD user         | review new matches best-fit first and push, watch or dismiss each                                                                               | Match Inbox                    |
| 6   | BD user         | see the countdown, fit breakdown, AI summary, versions and contacts of a notice                                                                 | Gov Notice page                |
| 7   | BD user         | push a notice to TechnoMile after seeing exactly what will be sent and whether it already exists                                                | Push dialog                    |
| 8   | BD user         | follow a notice and be alerted when it is amended                                                                                               | Follow / Watch                 |
| 9   | Power User      | share a search with a team or as an org template                                                                                                | Visibility                     |
| 10  | Power User      | auto-push matches above a fit threshold                                                                                                         | Auto-push                      |
| 11  | Capture manager | have a pushed record's due date updated and be alerted on other changes                                                                         | Post-push sync                 |
| 12  | Admin           | see each feed's health, run it now, and read its errors                                                                                         | Feed Console                   |
| 13  | Integration     | send notices from another system with retries made safe by an idempotency key                                                                   | REST API                       |
| 14  | BD user         | ask the assistant to search, explain, compare amendments, find incumbents, list recompetes and push                                             | Nexus Pursuit Assistant        |

## GovWin IQ coverage

| GovWin IQ capability                                              | Nexus Pursuit Hub                                                         |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Opportunity database, pre-RFP to award                            | SAM.gov notices (all types), forecasts, awards, recompete query           |
| Saved searches and alerts                                         | Saved searches with live preview; real-time, daily, weekly                |
| Smart Fit, analyst summaries                                      | Rules-based fit score with breakdown; AI summaries                        |
| Agency and vendor profiles                                        | Agency hierarchy and vendor records from SAM.gov and USAspending          |
| Salesforce / TechnoMile connector                                 | Native push with dedupe and amendment sync                                |
| GovWin analyst research (budget signals, contacts beyond notices) | **Not reproduced** from public data; decide whether the gap is acceptable |

## Rules

- A notice is identified by its source notice ID. A notice arriving from another source with the same solicitation number updates the existing record and adds the source to its lineage.
- Any change to title, type, status, NAICS, PSC, set-aside, response due, value, archive date, place or description creates a new Notice Version and a change event.
- Dismissed matches are never alerted again for that search. Other matches are alerted again on change when _Alert on changes_ is on.
- Already-pushed notices drop out of the Match Inbox.
- A push never overwrites capture fields. After a push, only fields mapped with _Update_ change automatically; _Alert only_ fields notify the record owner.
