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

PowerShell: `.\scripts\validate.ps1 -Org nxp-dev`.

## Test with sample data

Use a scratch org, a developer sandbox or QA. Never production: the loader refuses a production org unless you add `--allow-production`.

### 1. Load the sample data

`scripts/dev-setup` loads it for you. To load it into an org that already has Nexus deployed:

| Bash                                                 | PowerShell                                            |
| ---------------------------------------------------- | ----------------------------------------------------- |
| `scripts/load-sample-data.sh --org nxp-dev`          | `.\scripts\load-sample-data.ps1 -Org nxp-dev`         |
| `scripts/load-sample-data.sh --org nxp-dev --reset`  | `.\scripts\load-sample-data.ps1 -Org nxp-dev -Reset`  |
| `scripts/load-sample-data.sh --org nxp-dev --delete` | `.\scripts\load-sample-data.ps1 -Org nxp-dev -Delete` |

Run it as a user with the `NXP_Admin` permission set. `--reset` deletes the sample data and loads it fresh; `--delete` only deletes it. Running the plain load again is safe: records are upserted by their external IDs.

| Step | What is loaded                                                                          | From                                     |
| ---- | --------------------------------------------------------------------------------------- | ---------------------------------------- |
| 1    | Company Profile _Our company (sample)_ (skipped if an active profile exists)            | `scripts/apex/seed-profile.apex`         |
| 2    | 3 departments and 4 agencies (DHS, DoD/Army, VA)                                        | `data/seed/1-…csv`, `2-…csv`             |
| 3    | 2 contract vehicles                                                                     | `data/seed/3-…csv`                       |
| 4    | 10 notices `SAMPLE-0001`…`SAMPLE-0010`, fit-scored as they load                         | `data/seed/4-…csv`                       |
| 5    | Posted and due dates moved relative to today                                            | `scripts/apex/refresh-sample-dates.apex` |
| 6    | 3 saved searches for you, then a change event per notice so the real matching path runs | `scripts/apex/seed-searches.apex`        |

Expected after about a minute: 8 search matches, fit scores from about 36 (`SAMPLE-0009`, facilities work) to about 86 (`SAMPLE-0001` and `SAMPLE-0002`).

| Saved search                       | Criteria                                                    | Matches                              |
| ---------------------------------- | ----------------------------------------------------------- | ------------------------------------ |
| SAMPLE - DHS cyber, small business | Homeland Security, NAICS `5415*`, small business; Real Time | 0001, 0002, 0005, 0006 (+ REST-0001) |
| SAMPLE - Army 8(a)                 | Army, 8(a); Daily                                           | 0003, 0010                           |
| SAMPLE - Zero trust keywords       | `"zero trust" OR segmentation`; Weekly                      | 0001, 0005 (+ REST-0001)             |

### 2. Run the automated functional test

| Bash                                                    | PowerShell                                              |
| ------------------------------------------------------- | ------------------------------------------------------- |
| `scripts/test-functional.sh --org nxp-dev`              | `.\scripts\test-functional.ps1 -Org nxp-dev`            |
| `scripts/test-functional.sh --org nxp-dev --apex-tests` | `.\scripts\test-functional.ps1 -Org nxp-dev -ApexTests` |

It prints one line per check (PASS, FAIL, WARN or SKIP) and exits with 1 if anything failed.

| Check                                 | What it proves                                                                                                                                         |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| REST ingestion                        | `POST /services/apexrest/nxp/v1/notices` accepts `data/fixtures/rest-sample-notice.json` (creates `SAMPLE-REST-0001`)                                  |
| REST idempotency                      | A second call with the same `Idempotency-Key` replays the first response                                                                               |
| Configuration                         | One active Company Profile, active Fit Rules and Feed Configs                                                                                          |
| Sample notices                        | The sample data is there                                                                                                                               |
| Fit scoring                           | Every sample notice has a score and a rule-by-rule breakdown                                                                                           |
| Explain fit score                     | The assistant's explanation text can be built                                                                                                          |
| Draft criteria                        | Plain English → criteria JSON (Search Builder's **Draft criteria**)                                                                                    |
| Search preview                        | Live preview finds the DHS notices                                                                                                                     |
| Saved searches                        | The three sample searches exist for you                                                                                                                |
| Search matches                        | The event-driven matcher produced matches. WARN means the event subscriber had not run yet, so the test ran matching directly                          |
| Match Inbox data                      | The inbox gets your searches                                                                                                                           |
| Notice summary                        | The notice record page data loads                                                                                                                      |
| Push preview / guardrail / push / log | Preview shows the mapped fields; a push without a valid preview token is refused; the top notice is pushed once (an Opportunity by default) and logged |
| Feed console                          | Feed tiles and run history load; WARN if the feed scheduler is not scheduled                                                                           |
| Daily digest                          | The digest batch can be queued                                                                                                                         |
| AI setting                            | SKIP when `AI_Enabled` is off in the org                                                                                                               |
| Error log                             | No `ERROR` rows in **NXP Logs** today (WARN otherwise)                                                                                                 |

The test leaves its results in the org so you can look at them: one pushed Opportunity, one REST notice and a queued digest. `--reset` on the loader removes them, apart from the digest e-mail.

### 3. Walk through the app

The automated test covers the services. This walkthrough covers the screens. About 30 minutes; do it in QA before each release.

| #   | Area                   | Do                                                                                                                                                                                       | Expect                                                                                                                                                                   |
| --- | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Match Inbox            | Open **Nexus Pursuit Hub → Match Inbox**. Pick _SAMPLE - DHS cyber, small business_                                                                                                      | 4 cards (5 after the REST check), best fit first, each with the fit badge, buyer, days left and why it matched                                                           |
| 2   | Watch and dismiss      | **Watch** one card; **Dismiss** another with a reason                                                                                                                                    | The watched notice shows under **Include watching**; the dismissed card disappears                                                                                       |
| 3   | Notice page            | Open `SAMPLE-0001`                                                                                                                                                                       | Fit score about 86 with the rule-by-rule breakdown; description; **Follow** button                                                                                       |
| 4   | Versions               | Open `SAMPLE-REST-0001` (created through the REST API)                                                                                                                                   | Version 1 in the version history and one contact. CSV-loaded notices have no versions                                                                                    |
| 5   | Search Builder         | **My Searches → New search**. In **Describe it** type `Army 8(a) cyber, weekly` and click **Draft criteria**                                                                             | Army, 8(a), keyword _cyber_ and Weekly filled in; live preview shows `SAMPLE-0010`                                                                                       |
| 6   | Save and match         | Save the search. Then run `scripts/apex/seed-searches.apex` again (`sf apex run --file … --target-org nxp-dev`)                                                                          | The new search shows its matches in the inbox; existing searches don't get duplicates                                                                                    |
| 7   | Push                   | On `SAMPLE-0002` click **Push to TechnoMile**                                                                                                                                            | The dialog lists each mapped field. Confirm: an Opportunity is created and a **Push Log** row is added                                                                   |
| 8   | Push twice             | Push `SAMPLE-0002` again                                                                                                                                                                 | The dialog says it was already pushed and links to the existing record; no second record                                                                                 |
| 9   | Bulk push (Power User) | Select two cards and click **Push selected**                                                                                                                                             | Both pushed, one log row each                                                                                                                                            |
| 10  | Real-time alert        | Check the bell icon. The alerts were sent when the sample data loaded (re-sent only after `--reset`)                                                                                     | **NXP Match Alert** notifications for _SAMPLE - DHS cyber, small business_, the Real Time search                                                                         |
| 11  | Feed Console           | Open **Feed Console**                                                                                                                                                                    | One tile per feed with health and last run. **Run now** on _USAspending Awards_ starts a run (needs the endpoint reachable from the org; SAM.gov feeds need the API key) |
| 12  | Permissions            | Log in as a user with only `NXP_User`                                                                                                                                                    | Can search, watch and push one notice at a time. Bulk push, auto-push, team sharing and Feed Console **Run now** are refused or hidden                                   |
| 13  | Assistant              | After the [manual agent build](agent-manual-build.md), run the cases in `tests/agents/assistant.yaml` against the sample notices (for example "Why is the fit score on SAMPLE-0001 86?") | See [Agent](#agent) below                                                                                                                                                |

Clean up with `scripts/load-sample-data.sh --org nxp-dev --delete` (or `-Delete`). It removes everything marked `SAMPLE`, including the REST notice and the Opportunities the tests pushed. It doesn't touch real feed data.

## Notes for org-specific failures

- **`NXP_PushTest` / `NXP_AgentsTest`** push to Opportunity with the org's first open stage. If the org has validation rules or required fields on Opportunity, adjust `useOpportunityMapping()` or add the fields to the test mapping.
- **E-mail** sends are caught when deliverability is off (_System only_), so tests still pass. Turn deliverability on to see real alerts.
- Tests force AI off (`NXP_Settings.setForTest('AI_Enabled', 'false')`) or use `NXP_AiService.responsesForTest`, so they never call real prompt templates.

## Agent

Run each case in `tests/agents/assistant.yaml`. Record pass or fail per case and keep the result with the release ticket. A case fails if:

- the wrong subagent is chosen;
- a `mustNot` action is called; or
- the answer has no notice ID where one applies.
