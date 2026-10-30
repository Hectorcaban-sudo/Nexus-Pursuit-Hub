# ADR 0001: Six unlocked packages, no namespace

- Status: Accepted
- Date: 2026-10-28

## Context

The solution has clear seams (data, ingestion, search, push, UI, agents). Some change boards require plain metadata deployments, and the capture app that owns the Opportunity records is a managed package in the same org.

## Decision

Split the code into six unlocked packages along those seams, with no namespace, so the same folders can also be deployed as source with `sf project deploy`. The `NXP_` prefix does the job a namespace would.

## Consequences

Each package can be versioned and tested on its own, and install order is explicit. Without a namespace, names must stay prefixed. Choose one release path per org; package-installed components cannot later be replaced by source deploys.

## Update

A seventh package, `nxp-analytics`, was added for report types, reports and dashboards. It depends on all the others and installs last, so report metadata never blocks the code packages and can be released on its own.
