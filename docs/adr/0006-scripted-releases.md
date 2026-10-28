# ADR 0006: Scripted sf releases, no CI/CD for now

- Status: Accepted
- Date: 2026-10-28

## Context

The team does not need a pipeline yet, and Government Cloud CI hosting needs separate approval.

## Decision

Use `scripts/validate.sh` before pull requests, and `scripts/release.sh` (validate, then quick deploy, env-config, post-deploy) for every environment, with manual approvals.

## Consequences

Simple to run and audit. Quality depends on people running `validate.sh`, and a pipeline can wrap the same scripts later.
