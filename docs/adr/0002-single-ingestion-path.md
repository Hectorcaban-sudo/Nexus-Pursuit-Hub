# ADR 0002: One ingestion service for every channel

- Status: Accepted
- Date: 2026-10-28

## Context

Data arrives from scheduled feeds, batches, on-demand callouts, a REST API and Data Cloud. Duplicated logic would make results depend on the channel.

## Decision

Every channel converts its data to `NXP_IngestRecord` and calls `NXP_IngestionService`. The service owns dedupe, versioning and the `NXP_Gov_Notice_Changed__e` event. Matching, alerts and post-push sync subscribe to the event.

## Consequences

Behaviour is identical whichever channel loaded the data, and new consumers attach to the event without touching ingestion. Platform event subscribers must be monitored after deployments.
