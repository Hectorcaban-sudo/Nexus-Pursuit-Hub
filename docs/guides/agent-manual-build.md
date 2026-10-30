# Building the Nexus Pursuit Assistant manually (Government Cloud)

Agent Script is not available in Government Cloud, so the agent is configured by hand in Agentforce Builder. The reference blueprint is `packages/nxp-agents/reference/aiAuthoringBundles/NXP_Pursuit_Assistant/NXP_Pursuit_Assistant.agent`; use the same names and text.

## Before you start

1. Deploy all six packages: every action (invocable Apex) must exist before the agent can reference it.
2. In Setup, confirm Einstein and Agentforce are enabled in this org and covered by your ATO, and review Einstein Trust Layer settings.
3. Create or confirm the agent user. Users who chat need `NXP_User`, which grants the action classes, plus agent access.
4. Create the prompt templates in Prompt Builder, using the API names and text in `packages/nxp-agents/reference/genAiPromptTemplates/`:
    - `NXP_Solicitation_Summary`: input _Notice_, an `NXP_Gov_Notice__c` record.
    - `NXP_Amendment_Impact`: input _Version_, an `NXP_Notice_Version__c` record.
    - `NXP_Search_Criteria_Draft`: input _Request_, text.
    - `NXP_Ebuy_RFQ_Extract` (optional, eBuy e-mail): input _Email_, an `NXP_Inbound_Email__c` record; add a File input _Attachment_ only if you turn on `Ebuy_AI_Read_Attachments`.

    Activate them, then set `NXP_Setting.AI_Enabled = true`.

## Step by step

1. **Setup → Agentforce Agents → New Agent → Agentforce Employee Agent.**
    - Name: _Nexus Pursuit Assistant_.
    - API name: `NXP_Pursuit_Assistant`.
    - Description: _Helps BD users search government opportunities, understand notices and push them to TechnoMile._
2. **Agent instructions / role.** Paste:

    ```text
    You help business-development users at our company find and act on U.S. government contract opportunities in Nexus Pursuit Hub.
    Only answer from Nexus Pursuit Hub records and the documents attached to them; if the data is not there, say so.
    Always cite the notice ID (and document name and page when you quote a document).
    Never create, change or push records without showing a preview and getting an explicit "yes" from the user.
    When you give market numbers, state the data source and the date range used.
    You do not manage capture, pipeline or proposals; those live in TechnoMile.
    ```

3. **Remove default subagents** you don't need, then create these four. Write the classification description exactly as shown, because it drives routing:

| Subagent (API name)                     | Classification description                                                                 | Instructions (one per line)                                                                                                                                                                                                      |
| --------------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Search Builder (`NXP_Search_Builder`)   | Creating, changing, explaining or saving searches and alerts for government opportunities. | Turn the user's request into search criteria with NXP Draft Search Criteria. · Always run NXP Preview Search and show the count and top results before saving. · Save only after the user confirms, passing the preview token.   |
| Notice Briefing (`NXP_Notice_Briefing`) | Questions about a specific notice, solicitation, its documents, amendments or fit score.   | Identify the notice from the page context or ask for the notice ID. · For "what changed", use NXP Compare Versions. · For "why this score", use NXP Explain Fit Score. · Cite the notice ID.                                     |
| Market Intel (`NXP_Market_Intel`)       | Incumbents, recompetes, likely bidders, agency spending, vendors and forecasts.            | Use the most specific action. · Always state the data window the action returned. · Do not estimate numbers the actions did not return.                                                                                          |
| Push (`NXP_Push`)                       | Sending notices to TechnoMile, checking push status, or setting auto-push rules.           | Run NXP Preview Push first and show the mapped values and any duplicate. · Only call NXP Push To TechnoMile after the user says yes, passing the preview token. · Auto-push needs the Power User permission; explain if refused. |

4. **Add actions** to each subagent: New Action → Apex → select the class.

| Subagent        | Action (Apex class)                                         | Require user confirmation | Show output in conversation |
| --------------- | ----------------------------------------------------------- | ------------------------- | --------------------------- |
| Search Builder  | NXP Draft Search Criteria (`NXP_DraftSearchCriteriaAction`) | –                         | Summary                     |
| Search Builder  | NXP Preview Search (`NXP_PreviewSearchAction`)              | –                         | Match count, Top matches    |
| Search Builder  | NXP Save Search (`NXP_SaveSearchAction`)                    | **Yes**                   | Message                     |
| Notice Briefing | NXP Explain Fit Score (`NXP_ExplainFitScoreAction`)         | –                         | Explanation                 |
| Notice Briefing | NXP Compare Versions (`NXP_CompareVersionsAction`)          | –                         | Changes                     |
| Market Intel    | NXP Find Incumbent (`NXP_FindIncumbentAction`)              | –                         | Answer                      |
| Market Intel    | NXP Recompete Query (`NXP_RecompeteQueryAction`)            | –                         | Recompetes                  |
| Push            | NXP Preview Push (`NXP_PreviewPushAction`)                  | –                         | Preview                     |
| Push            | NXP Push To TechnoMile (`NXP_PushToTechnoMileAction`)       | **Yes**                   | Status, Message             |
| Push            | NXP Push Status (`NXP_PushStatusAction`)                    | –                         | Status                      |
| Push            | NXP Set Auto-Push Rule (`NXP_SetAutoPushRuleAction`)        | **Yes**                   | Message                     |

Mark _Preview token_ outputs as **not** shown to the user but available to the agent. They are passed to Save Search and Push To TechnoMile.

5. **Test** in the conversation preview with every case in `tests/agents/assistant.yaml`, and check the plan trace for the expected subagent and actions. When routing is wrong, fix classification descriptions first.
6. **Activate**, assign agent access to the NXP user permission set group or profile, and add the agent to the Nexus Pursuit Hub app's Agentforce panel.
7. **Retrieve to source** (API 68.0) so other environments are deployed, not rebuilt:

    ```bash
    sf project retrieve start --metadata "AiAgentDefinition:NXP_Pursuit_Assistant" \
      --output-dir packages/nxp-agents/main/default --target-org <org> --api-version 68.0
    ```

    Commit on a branch. For UAT and production, deploy that metadata, then activate the agent and assign access (activation is a release step).

## Why the guardrails hold without Agent Script

Save Search and Push To TechnoMile refuse to act without the **preview token** returned by their preview action for the same user, subject and day. Auto-push changes check the Power User permission in Apex. So even if the model skipped an instruction, the action would decline and tell the user to preview first.
