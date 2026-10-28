# Testing guide

| Test type     | Tool                                                               | Where                                                                                                               | Covers                                                                                                            | Gate                                                   |
| ------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| Apex unit     | Apex tests, `HttpCalloutMock`                                      | `NXP_CoreTest`, `NXP_IngestionTest`, `NXP_SearchTest`, `NXP_PushTest`, `NXP_AgentsTest`, `NXP_NoticeControllerTest` | Connectors, mapping, dedupe, versioning, fit score, matcher, alerts, digests, push, sync, REST API, agent actions | ≥ 85% per package; all pass                            |
| LWC unit      | Jest (`npm run test:unit`)                                         | `lwc/*/__tests__`                                                                                                   | Rendering, sorting, criteria JSON, push dialog, console tiles                                                     | All pass                                               |
| Static        | Prettier, ESLint, Code Analyzer                                    | `scripts/validate.sh`                                                                                               | Format, LWC rules, security, SOQL/DML in loops                                                                    | No severity 1–2                                        |
| Feed contract | Apex tests over recorded responses (`data/fixtures`)               | `NXP_IngestionTest.Router`                                                                                          | SAM.gov/USAspending shape changes                                                                                 | Refresh fixtures monthly                               |
| Agent         | Builder preview (Government Cloud) or `sf agent test` (commercial) | `tests/agents/assistant.yaml`                                                                                       | Routing, preview-before-act, citations                                                                            | ≥ 90%                                                  |
| Performance   | Load script in UAT                                                 | —                                                                                                                   | 10,000 saved searches × 1,000 notices                                                                             | Matching within one event batch; alerts within minutes |
| Parallel run  | GovWin vs Nexus alerts                                             | UAT/production, 4 weeks                                                                                             | Coverage before cancelling GovWin                                                                                 | Agreed coverage %                                      |

## Running tests

```bash
npm run test:unit                                    # Jest
scripts/validate.sh --org nxp-dev                    # everything + check-only deploy with RunLocalTests
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --target-org nxp-dev --wait 30
sf apex run test --class-names NXP_PushTest --target-org nxp-dev --result-format human
```

## Notes for org-specific failures

- **`NXP_PushTest` / `NXP_AgentsTest`** push to Opportunity with the org's first open stage. If the org has validation rules or required fields on Opportunity, adjust `useOpportunityMapping()` or add the fields to the test mapping.
- **E-mail** sends are caught when deliverability is off (_System only_), so tests still pass. Turn deliverability on to see real alerts.
- Tests force AI off (`NXP_Settings.setForTest('AI_Enabled', 'false')`) or use `NXP_AiService.responsesForTest`, so they never call real prompt templates.

## Agent

Run each case in `tests/agents/assistant.yaml`. Record pass or fail per case and keep the result with the release ticket. A case fails if:

- the wrong subagent is chosen;
- a `mustNot` action is called; or
- the answer has no notice ID where one applies.
