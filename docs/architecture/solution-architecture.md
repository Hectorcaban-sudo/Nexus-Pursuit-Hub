# Solution architecture

Nexus Pursuit Hub is a Salesforce-native market-intelligence app that replaces GovWin IQ. It runs in the same org as TechnoMile:

- Nexus Pursuit Hub finds and tracks government opportunities.
- TechnoMile manages the pursuits that users push into it.

![Solution architecture](../diagrams/01-solution-architecture.jpg)

## Scope

| Nexus Pursuit Hub owns                                                 | TechnoMile keeps                           |
| ---------------------------------------------------------------------- | ------------------------------------------ |
| Government feed ingestion, de-duplication, amendments, documents       | Opportunity / pursuit records and pipeline |
| Searchable library of notices, forecasts, awards, vendors and agencies | Capture stages, gates, bid/no-bid, pWin    |
| User-defined saved searches and alerts                                 | Capture plans, teaming, proposals          |
| Fit scoring, AI summaries                                              | Pipeline reporting                         |
| Push rules, push log, post-push sync                                   | Everything after the record lands          |

## Building blocks

| Layer        | Components                                                                                                                              |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Sources      | SAM.gov Opportunities and Entity APIs, USAspending (and FPDS), agency forecasts, other systems that push data in                        |
| Import       | Standard pipeline (Queueable chain), scheduled Apex batch, Apex callouts on demand, Apex REST ingestion API, Data Cloud Ingestion API   |
| Processing   | `NXP_IngestionService`: one path for every channel (normalize, resolve agency, dedupe, version, publish `NXP_Gov_Notice_Changed__e`)    |
| Intelligence | Fit score (`NXP_FitScoreService`), saved-search matching, alerts, AI summaries (prompt templates)                                       |
| Experience   | Lightning app _Nexus Pursuit Hub_: Match Inbox, My Searches, Gov Notice record page, Forecasts, Awards, Agencies, Vendors, Feed Console |
| Agent        | Nexus Pursuit Assistant (Agentforce employee agent) with four subagents                                                                 |
| Hand-off     | Push to TechnoMile through a configurable mapping; amendments keep pushed records current                                               |

## Main flows

1. **Ingest.** A scheduled job, a batch, or a REST call delivers records. `NXP_IngestionService` upserts notices, writes a Notice Version for every change of tracked fields, and publishes a change event ([02](../diagrams/02-ingestion-pipeline.jpg), [03](../diagrams/03-import-channels.jpg)).
2. **Match and alert.** A platform-event trigger runs each new or changed notice against every active saved search. It records Search Matches, sends real-time alerts, queues digests, alerts followers, requests AI summaries and calls the auto-push listener ([04](../diagrams/04-search-alert-workflow.jpg)).
3. **Push.** A user (or an auto-push rule, or the assistant) pushes a notice. The push service checks for an existing record, then creates or links the TechnoMile record, logs the push, and keeps it in sync on later amendments ([05](../diagrams/05-push-workflow.jpg)).
4. **Assist.** The Nexus Pursuit Assistant drafts searches, explains notices and fit scores, answers market questions and pushes notices. Every push and save needs a preview and an explicit yes ([10](../diagrams/10-agent-architecture.jpg)).

## Key decisions

| Decision                                                                     | ADR                                                   |
| ---------------------------------------------------------------------------- | ----------------------------------------------------- |
| Six unlocked packages without namespace; direct source deploy also supported | [0001](../adr/0001-unlocked-packages-no-namespace.md) |
| One ingestion service for all channels, events decouple consumers            | [0002](../adr/0002-single-ingestion-path.md)          |
| Push target configured by metadata, no code dependency on TechnoMile         | [0003](../adr/0003-configurable-push-target.md)       |
| Agents built manually in Government Cloud; guardrails enforced in Apex       | [0004](../adr/0004-manual-agents-apex-guardrails.md)  |
| API 68.0 everywhere                                                          | [0005](../adr/0005-api-68.md)                         |
| Releases by scripted `sf` commands, no CI/CD for now                         | [0006](../adr/0006-scripted-releases.md)              |

## Non-functional targets

| Area       | Target                                                                                                                 |
| ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| Freshness  | SAM.gov notices searchable within about an hour of posting (hourly feed); real-time alerts within minutes of ingestion |
| Search     | Previews read at most 2,000 rows with indexed filters, then apply text filters in Apex                                 |
| Volume     | Hundreds of thousands of notices a year; bulk award history in Data Cloud, not core storage                            |
| Resilience | Checkpointed runs resume after failures; retries on 429/5xx; partial failures never roll back loaded records           |
| Audit      | Feed Runs, Push Logs and NXP Logs; field history on key notice fields                                                  |
| AI         | Einstein Trust Layer; AI text labelled; actions cite notice IDs                                                        |
