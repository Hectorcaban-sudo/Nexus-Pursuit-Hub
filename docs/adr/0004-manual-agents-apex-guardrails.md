# ADR 0004: Agents built manually; guardrails in Apex

- Status: Accepted
- Date: 2026-10-28

## Context

Agent Script is not available in our Government Cloud org, so deterministic rules cannot live in the agent definition.

## Decision

Build the Nexus Pursuit Assistant manually from the reference Agent Script. Enforce preview-before-act with HMAC preview tokens and permission checks inside the Apex actions. Run background summaries as prompt templates from batch Apex instead of autonomous agents.

## Consequences

Guardrails hold even if the model ignores an instruction. The manual build must be repeated per org unless the agent metadata is retrieved and deployed. The Agent Script stays as the spec and for commercial orgs.
