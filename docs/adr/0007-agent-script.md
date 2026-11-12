# ADR 0007: The assistant is deployed with Agent Script where the org supports it

- Status: Accepted
- Date: 2026-11-12
- Amends: [ADR 0004](0004-manual-agents-apex-guardrails.md)

## Context

The new Agentforce Builder and Agent Script are now available in our sandbox. ADR 0004 had the assistant built by hand from a reference script, because Agent Script was not available in Government Cloud.

## Decision

The Nexus Pursuit Assistant is defined in `packages/nxp-agent-script` (`NXP_Pursuit_Assistant.agent`) and deployed, validated, published and activated with the Salesforce CLI ([agent script build](../guides/agent-script-build.md)). The file is generated from the Apex actions' annotations and the subagent design by `scripts/agent-script/gen_agent.py`, so the descriptions agents see match the code.

The script adds deterministic rules (preview before save or push, bound preview tokens, confirmation), and the Apex actions keep their own token and permission checks. The bundle has its own package directory, outside the release scripts, so orgs without Agent Script are not affected; they keep the manual build.

## Consequences

The assistant is reproducible across orgs and reviewed like code. Changes made in Agentforce Builder must be copied back into the generator. Agent Script is still evolving: run `sf agent validate authoring-bundle` before every publish.
