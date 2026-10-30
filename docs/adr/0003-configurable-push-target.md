# ADR 0003: Push target configured by metadata

- Status: Accepted
- Date: 2026-10-28

## Context

the Opportunity object and field names vary by org and version, and a code dependency on its managed package would block testing and packaging.

## Decision

Push reads its target object, fields, defaults, required flags and sync rules from `NXP_Push_Mapping__mdt`. Only `NXP_OpportunityPushTarget`, behind the `NXP_PushTarget` interface, knows about the target.

## Consequences

Admins can retarget the push without code, and tests run against Opportunity. Duplicate detection needs a mapped solicitation-number field on the target object.
