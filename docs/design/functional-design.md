# Functional design

## Users

| Persona                  | Uses Nexus Pursuit Hub to                                                                                        |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| BD / opportunity analyst | Build searches, triage the Match Inbox, push good notices to TechnoMile                                          |
| Capture manager          | Follow notices, see amendments flow into pushed TechnoMile records                                               |
| BD lead (Power User)     | Share team searches, turn on auto-push, bulk push                                                                |
| Admin                    | Configure feeds, credentials, fit rules, push mapping, eBuy inbox, AI; watch the Feed Console and Inbound Emails |
| Integration (system)     | Push notices in through the REST API; owns eBuy e-mail records                                                   |

## User stories

| #   | As a…           | I can…                                                                                                                                          | Delivered by                         |
| --- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| 1   | BD user         | build a search with keywords (AND/OR/NOT, phrases, prefixes), buyer, NAICS, PSC, set-aside, notice type, value, due date, place and minimum fit | My Searches tab                      |
| 2   | BD user         | describe a search in plain English and get the criteria filled in                                                                               | _Describe it_ / Draft criteria       |
| 3   | BD user         | see how many notices match now and per week over 13 weeks before saving                                                                         | Live preview                         |
| 4   | BD user         | choose real-time, daily, weekly or no alerts, and the channels                                                                                  | Alert settings                       |
| 5   | BD user         | review new matches best-fit first and push, watch or dismiss each                                                                               | Match Inbox                          |
| 6   | BD user         | see the countdown, fit breakdown, AI summary, versions and contacts of a notice                                                                 | Gov Notice page                      |
| 7   | BD user         | push a notice to TechnoMile after seeing exactly what will be sent and whether it already exists                                                | Push dialog                          |
| 8   | BD user         | follow a notice and be alerted when it is amended                                                                                               | Follow / Watch                       |
| 9   | Power User      | share a search with a team or as an org template                                                                                                | Visibility                           |
| 10  | Power User      | auto-push matches above a fit threshold                                                                                                         | Auto-push                            |
| 11  | Capture manager | have a pushed record's due date updated and be alerted on other changes                                                                         | Post-push sync                       |
| 12  | Admin           | see each feed's health, run it now, and read its errors                                                                                         | Feed Console                         |
| 13  | Integration     | send notices from another system with retries made safe by an idempotency key                                                                   | REST API                             |
| 14  | BD user         | ask the assistant to search, explain, compare amendments, find incumbents, list recompetes and push                                             | Nexus Pursuit Assistant              |
| 15  | BD user         | see agency forecasts by expected solicitation date and watch one to hear when it is released                                                    | Forecasts tab                        |
| 16  | BD user         | see awards ending in the next 6–24 months with their likely follow-on, and watch a recompete                                                    | Recompetes tab                       |
| 17  | BD user         | open a vendor's or agency's profile (awards, incumbents, what's coming, contacts) and watch it                                                  | Vendor and Agency pages              |
| 18  | BD user         | see the notices on the vehicles we hold, when they expire, and which notices need a vehicle we lack                                             | Vehicle Portfolio tab                |
| 19  | Admin           | record that we hold or no longer hold a vehicle, and have its notices re-scored                                                                 | Vehicle Portfolio                    |
| 20  | BD user         | get GSA eBuy RFQs as notices on the right vehicle, with their attachments, without re-typing them                                               | eBuy e-mail intake                   |
| 21  | Admin           | see every e-mail the eBuy inbox received, why it was rejected or needs review, and reprocess it                                                 | Inbound Emails tab                   |
| 22  | BD user         | have eBuy RFQs that fit us pushed to TechnoMile automatically                                                                                   | Auto-push saved search               |
| 23  | BD user         | read what a solicitation document requires (requirements, evaluation, dates, clearance, risks) and where it disagrees with the notice           | Documents card, NXP Notice Documents |

## GovWin IQ coverage

| GovWin IQ capability                                              | Nexus Pursuit Hub                                                             |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Opportunity database, pre-RFP to award                            | SAM.gov notices (all types), forecasts, awards, recompete query               |
| Saved searches and alerts                                         | Saved searches with live preview; real-time, daily, weekly                    |
| Smart Fit, analyst summaries                                      | Rules-based fit score with breakdown; AI summaries                            |
| Agency and vendor profiles                                        | Agency and vendor profile pages from SAM.gov and USAspending data, with Watch |
| Contract vehicle intelligence                                     | Vehicle Portfolio; eBuy RFQs by e-mail                                        |
| Document analysis                                                 | Document Reader on notice PDFs (AI, checked by code)                          |
| Salesforce / TechnoMile connector                                 | Native push with dedupe and amendment sync                                    |
| GovWin analyst research (budget signals, contacts beyond notices) | **Not reproduced** from public data; decide whether the gap is acceptable     |

## Rules

- A notice is identified by its source notice ID. A notice arriving from another source with the same solicitation number updates the existing record and adds the source to its lineage.
- Any change to title, type, status, NAICS, PSC, set-aside, response due, value, archive date, place or description creates a new Notice Version and a change event.
- Dismissed matches are never alerted again for that search. Other matches are alerted again on change when _Alert on changes_ is on.
- Already-pushed notices drop out of the Match Inbox.
- An eBuy RFQ is identified by `EBUY:<RFQ number>`; a later e-mail about the same RFQ updates it. The RFQ number is read by rules, never by AI.
- AI output (summaries, document analysis, eBuy fill-in) is labelled and never decides anything: bid/no-bid stays in TechnoMile.
- A push never overwrites capture fields. After a push, only fields mapped with _Update_ change automatically; _Alert only_ fields notify the record owner.
