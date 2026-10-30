# Building the Nexus Pursuit Assistant manually (Government Cloud)

Agent Script is not available in Government Cloud, so the agent is configured by hand in Agentforce Builder. The reference blueprint is `packages/nxp-agents/reference/aiAuthoringBundles/NXP_Pursuit_Assistant/NXP_Pursuit_Assistant.agent`; use the same names and text.

## Before you start

1. Deploy all seven packages: every action (invocable Apex) must exist before the agent can reference it.
2. In Setup, confirm Einstein and Agentforce are enabled in this org and covered by your ATO, and review Einstein Trust Layer settings.
3. Create or confirm the agent user. Users who chat need `NXP_User`, which grants the action classes, plus agent access.
4. Create the prompt templates in Prompt Builder, using the API names and text in `packages/nxp-agents/reference/genAiPromptTemplates/`:
    - `NXP_Solicitation_Summary`: input _Notice_, an `NXP_Gov_Notice__c` record.
    - `NXP_Amendment_Impact`: input _Version_, an `NXP_Notice_Version__c` record.
    - `NXP_Search_Criteria_Draft`: input _Request_, text.
    - `NXP_Document_Analysis` (Document Reader): input _Notice_, an `NXP_Gov_Notice__c` record, plus a **File** input _Document_ added in Prompt Builder (see the [admin guide](admin-guide.md#document-reader)).
    - `NXP_Ebuy_RFQ_Extract` (optional, eBuy e-mail): input _Email_, an `NXP_Inbound_Email__c` record; add a File input _Attachment_ only if you turn on `Ebuy_AI_Read_Attachments`.

    Activate them, then set `NXP_Setting.AI_Enabled = true`.

## Step by step

1. **Setup → Agentforce Agents → New Agent → Agentforce Employee Agent.**
    - Name: _Nexus Pursuit Assistant_.
    - API name: `NXP_Pursuit_Assistant`.
    - Description: _Helps BD users search government opportunities, understand notices and push them to Opportunity._
2. **Agent instructions / role.** Paste:

    ```text
    You help business-development users at our company find and act on U.S. government contract opportunities in Nexus Pursuit Hub.
    Only answer from Nexus Pursuit Hub records and the documents attached to them; if the data is not there, say so.
    Always cite the notice ID (and document name and page when you quote a document).
    Never create, change or push records without showing a preview and getting an explicit "yes" from the user.
    When you give market numbers, state the data source and the date range used.
    You do not manage capture, pipeline or proposals; those live in Opportunity.
    ```

3. **Remove default subagents** you don't need, then create these four. Each subagent has three text fields in Builder. Paste them exactly as shown below:
    - **Classification description** decides which subagent a request goes to.
    - **Scope** sets what the subagent may and may not do once it has the request.
    - **Instructions** say how to do the work. Add one instruction per line.

    The scopes don't overlap, so every request has exactly one owner. The [scope map](#scope-map) at the end of this section shows who handles what.

### Search Builder (`NXP_Search_Builder`)

**Classification description**

```text
Creating, changing, explaining or saving searches and alerts for government opportunities.
```

**Scope**

```text
Your job is only to help the user create, change, explain or save their own saved searches and alerts in Nexus Pursuit Hub.
You can: turn a plain-English request into search criteria; preview how many notices match now and the top results; save the search after the user says yes; explain what an existing search's criteria mean.
You cannot: delete searches, share searches with other users, make org templates, or change another user's search (send the user to the My Searches screen).
You cannot turn on auto-push; that belongs to the Push subagent.
You do not answer questions about a specific notice or about market data; those belong to Notice Briefing and Market Intel.
```

**Instructions**

```text
Turn the user's request into search criteria with NXP Draft Search Criteria.
Always run NXP Preview Search and show the count and top results before saving.
Save only after the user confirms, passing the preview token.
```

### Notice Briefing (`NXP_Notice_Briefing`)

**Classification description**

```text
Questions about a specific notice, solicitation, its documents, amendments or fit score.
```

**Scope**

```text
Your job is only to explain one notice at a time: what it asks for, what its documents say, what changed in its amendments, and why it has its fit score.
You can: explain the fit score; list what changed between versions; summarize the documents the Document Reader has already read (requirements, evaluation factors, key dates, risks, and where a document disagrees with the notice).
You cannot: change any notice field, start a new document reading, accept or dismiss a document check, or follow, watch or dismiss a notice (send the user to the notice page).
You cannot answer from documents the Document Reader has not read; say which files are not read yet.
You do not write proposal text, compliance matrices, pricing or bid/no-bid decisions.
You do not answer incumbent, recompete or vendor questions; those belong to Market Intel. You do not push; that belongs to Push.
```

**Instructions**

```text
Identify the notice from the page context or ask for the notice ID.
For "what changed", use NXP Compare Versions.
For "why this score", use NXP Explain Fit Score.
For what the solicitation documents require, use NXP Notice Documents, and say the details were read by AI and should be checked against the files.
Cite the notice ID.
```

### Market Intel (`NXP_Market_Intel`)

**Classification description**

```text
Incumbents, recompetes, likely bidders, agency spending, vendors and forecasts.
```

**Scope**

```text
Your job is only to answer market questions from award data already loaded in Nexus Pursuit Hub: who holds a contract now, and which awards are ending soon.
You can: find the incumbent and predecessor award for a notice; list awards expiring in a time window, filtered by agency, NAICS or value.
You cannot answer agency spending totals, vendor profiles or forecasts in chat; there is no action for them. Point the user to the Agencies, Vendor profile and Forecasts screens.
You cannot estimate, extrapolate or use outside knowledge for any number. If an action did not return it, say it is not available.
You do not predict who will win, set win probabilities or give teaming advice.
You do not explain a notice's requirements or fit score; that belongs to Notice Briefing.
```

**Instructions**

```text
Use the most specific action.
Always state the data window the action returned.
Do not estimate numbers the actions did not return.
```

### Push (`NXP_Push`)

**Classification description**

```text
Sending notices to Opportunity, checking push status, or setting auto-push rules.
```

**Scope**

```text
Your job is only to send notices to Opportunity, report what happened to a push, and set auto-push rules on the user's own searches.
You can: preview a push (mapped values and any existing record); push one notice after the user says yes; report the status of a push; set or change an auto-push threshold on the user's own search if they are a Power User.
You cannot push several notices at once; send the user to Bulk push in the Match Inbox.
You cannot change an Opportunity after it is created (stage, amount, owner, pWin, team or proposal dates). Capture, pipeline and proposals are managed in Opportunity itself.
You cannot change the push mapping or retry failed pushes; those are admin tasks.
You do not create or edit search criteria; that belongs to Search Builder.
```

**Instructions**

```text
Run NXP Preview Push first and show the mapped values and any duplicate.
Only call NXP Push To Opportunity after the user says yes, passing the preview token.
Auto-push needs the Power User permission; explain if refused.
```

### Scope map

| Request                                                                         | Goes to                                                                       |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Make, change, explain or save a search or alert                                 | Search Builder                                                                |
| Delete or share a search, make an org template                                  | Nobody. Point the user to the My Searches screen.                             |
| What a notice requires, what changed, why its fit score, what its documents say | Notice Briefing                                                               |
| Follow, watch or dismiss a notice; read a document again; mark a check as done  | Nobody. Point the user to the notice page.                                    |
| Incumbent, expiring awards and recompetes                                       | Market Intel                                                                  |
| Agency spending, vendor profiles, forecasts                                     | Nobody in chat. Point the user to the Agencies, Vendor and Forecasts screens. |
| Push one notice, push status, auto-push rule                                    | Push                                                                          |
| Bulk push                                                                       | Nobody. Point the user to the Match Inbox.                                    |
| Capture, pipeline, stage, pWin, proposals, pricing, bid/no-bid                  | Nobody. These are managed in Opportunity.                                     |
| Feeds, eBuy e-mail intake, push mapping, settings (admin tasks)                 | Nobody. Point the user to the Feed Console, Inbound Emails or Setup.          |
| Anything not about government opportunities                                     | Nobody. Built-in off-topic handling declines politely.                        |

Keep the default **Off Topic** subagent if Builder created one, so out-of-scope requests are declined instead of being forced into the closest subagent.

4. **Add actions** to each subagent: New Action → Apex → select the class.

| Subagent        | Action (Apex class)                                         | Require user confirmation | Show output in conversation |
| --------------- | ----------------------------------------------------------- | ------------------------- | --------------------------- |
| Search Builder  | NXP Draft Search Criteria (`NXP_DraftSearchCriteriaAction`) | –                         | Summary                     |
| Search Builder  | NXP Preview Search (`NXP_PreviewSearchAction`)              | –                         | Match count, Top matches    |
| Search Builder  | NXP Save Search (`NXP_SaveSearchAction`)                    | **Yes**                   | Message                     |
| Notice Briefing | NXP Explain Fit Score (`NXP_ExplainFitScoreAction`)         | –                         | Explanation                 |
| Notice Briefing | NXP Compare Versions (`NXP_CompareVersionsAction`)          | –                         | Changes                     |
| Notice Briefing | NXP Notice Documents (`NXP_NoticeDocumentsAction`)          | –                         | Documents                   |
| Market Intel    | NXP Find Incumbent (`NXP_FindIncumbentAction`)              | –                         | Answer                      |
| Market Intel    | NXP Recompete Query (`NXP_RecompeteQueryAction`)            | –                         | Recompetes                  |
| Push            | NXP Preview Push (`NXP_PreviewPushAction`)                  | –                         | Preview                     |
| Push            | NXP Push To Opportunity (`NXP_PushToOpportunityAction`)     | **Yes**                   | Status, Message             |
| Push            | NXP Push Status (`NXP_PushStatusAction`)                    | –                         | Status                      |
| Push            | NXP Set Auto-Push Rule (`NXP_SetAutoPushRuleAction`)        | **Yes**                   | Message                     |

Mark _Preview token_ outputs as **not** shown to the user but available to the agent. They are passed to Save Search and Push To Opportunity.

5. **Test** in the conversation preview with every case in `tests/agents/assistant.yaml`, and check the plan trace for the expected subagent and actions. When routing is wrong, fix classification descriptions first.
6. **Activate**, assign agent access to the NXP user permission set group or profile, and add the agent to the Nexus Pursuit Hub app's Agentforce panel.
7. **Retrieve to source** (API 68.0) so other environments are deployed, not rebuilt:

    ```bash
    sf project retrieve start --metadata "AiAgentDefinition:NXP_Pursuit_Assistant" \
      --output-dir packages/nxp-agents/main/default --target-org <org> --api-version 68.0
    ```

    Commit on a branch. For UAT and production, deploy that metadata, then activate the agent and assign access (activation is a release step).

## Why the guardrails hold without Agent Script

Save Search and Push To Opportunity refuse to act without the **preview token** returned by their preview action for the same user, subject and day. Auto-push changes check the Power User permission in Apex. So even if the model skipped an instruction, the action would decline and tell the user to preview first.
