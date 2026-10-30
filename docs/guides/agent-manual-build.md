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
The [next section](#action-input-and-output-descriptions) gives the exact text and settings for every input and output.

### Action, input and output descriptions

When you add an action, Builder copies the descriptions written in the Apex code into the instructions fields. Several inputs and outputs have no description in the code, and the agent relies on these instructions to decide what to pass and what to show. Replace every instructions field with the text below. Since the October 30 update, the Apex code carries the same text, so Builder fills it in for you on actions added after you deploy that version. Each text is under 255 characters.

For each action, Builder has these fields:

- **Agent action instructions:** when to use the action.
- **For each input:**
    - _Instructions_: what to pass.
    - _Require input_: the agent must have a value before calling the action.
    - _Collect data from user_: the agent may ask the user for the value.
- **For each output:**
    - _Instructions_: what the value means.
    - _Show in conversation_: the value is shown to the user. When this is off, only the agent sees it and can pass it to the next action.

**Gov Notice record Id** appears on seven actions, with the same instructions each time (repeated in each table below so you can copy it from there):

```text
Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id.
```

Settings for it: Require input **Yes**. Collect data from user **No**.

#### NXP Draft Search Criteria (Search Builder)

Agent action instructions:

```text
Use first whenever the user describes a search or alert they want, or asks to change one. Turns their words into draft criteria. Saves nothing.
```

| Kind   | Field           | Instructions                                                                                                                                                                     | Settings                          |
| ------ | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Input  | Request text    | The user's own words describing what they want alerts about: agencies, NAICS codes, set-asides, keywords, value, due dates and how often. Pass them unchanged; do not summarize. | Require **Yes** · Collect **Yes** |
| Output | Criteria JSON   | Machine-readable draft criteria. Do not show it to the user. Pass it unchanged to NXP Preview Search and then to NXP Save Search.                                                | Show **No**                       |
| Output | Alert frequency | Real Time, Daily or Weekly when the user asked for one; empty otherwise. Pass it to NXP Save Search.                                                                             | Show **No**                       |
| Output | Summary         | Readable summary of the draft criteria. Show it so the user can correct anything before the preview.                                                                             | Show **Yes**                      |

#### NXP Preview Search (Search Builder)

Agent action instructions:

```text
Use after NXP Draft Search Criteria and before any save. Shows how many notices match now, how many matched over the last 13 weeks, and the top five.
```

| Kind   | Field                 | Instructions                                                                                                                                                        | Settings                         |
| ------ | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Criteria JSON         | The Criteria JSON output of NXP Draft Search Criteria, unchanged. If the user wants a change, run NXP Draft Search Criteria again with the corrected request first. | Require **Yes** · Collect **No** |
| Output | Match count           | Number of active notices that match now.                                                                                                                            | Show **Yes**                     |
| Output | Matches last 13 weeks | Number of notices that would have matched over the last 13 weeks. Tells the user how busy the alert will be.                                                        | Show **Yes**                     |
| Output | Top matches           | Up to five matching notices, one per line, each starting with its notice ID in brackets. Show them as a list and keep the IDs.                                      | Show **Yes**                     |
| Output | Criteria summary      | Readable summary of the criteria that were previewed.                                                                                                               | Show **Yes**                     |
| Output | Preview token         | Proof the user saw this preview. Do not show it. Pass it to NXP Save Search. It works only for these criteria and this user, and expires at the end of the day.     | Show **No**                      |

#### NXP Save Search (Search Builder)

Agent action instructions:

```text
Use only after NXP Preview Search has been shown and the user has said yes to saving. Saves the previewed search as the user's own.
```

| Kind   | Field           | Instructions                                                                                                                         | Settings                          |
| ------ | --------------- | ------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- |
| Input  | Search name     | Short name for the search. Use the name the user gave. If they gave none, suggest one based on the summary and confirm it with them. | Require **Yes** · Collect **Yes** |
| Input  | Criteria JSON   | The same Criteria JSON that was passed to NXP Preview Search, unchanged.                                                             | Require **Yes** · Collect **No**  |
| Input  | Alert frequency | Real Time, Daily, Weekly or None. Use the user's choice; if they did not choose, leave it empty for Daily.                           | Require **No** · Collect **Yes**  |
| Input  | Preview token   | The Preview token output of NXP Preview Search for these same criteria, from this conversation. Never make one up.                   | Require **Yes** · Collect **No**  |
| Output | Saved search Id | Id of the new saved search. Do not show it. Keep it in case the user then asks to turn on auto-push for this search.                 | Show **No**                       |
| Output | Message         | What happened, including the reason if the save was refused. Tell the user.                                                          | Show **Yes**                      |

#### NXP Explain Fit Score (Notice Briefing)

Agent action instructions:

```text
Use when the user asks why a notice has its fit score, or what is helping or hurting the score.
```

| Kind   | Field                | Instructions                                                                                                                                                                                                                  | Settings                         |
| ------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Gov Notice record Id | Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id. | Require **Yes** · Collect **No** |
| Output | Explanation          | The score and the points each rule added, starting with the notice ID. Show it as given; do not recalculate or round.                                                                                                         | Show **Yes**                     |

#### NXP Compare Versions (Notice Briefing)

Agent action instructions:

```text
Use when the user asks what changed in a notice, what an amendment did, or whether the due date moved.
```

| Kind   | Field                    | Instructions                                                                                                                                                                                                                  | Settings                         |
| ------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Gov Notice record Id     | Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id. | Require **Yes** · Collect **No** |
| Input  | How many recent versions | How many recent amendments to compare. Use the number the user asked for; otherwise leave empty for 3.                                                                                                                        | Require **No** · Collect **No**  |
| Output | Changes                  | Field-by-field changes for each amendment, newest first, with the notice ID.                                                                                                                                                  | Show **Yes**                     |

#### NXP Notice Documents (Notice Briefing)

Agent action instructions:

```text
Use when the user asks what the solicitation documents say or require: requirements, evaluation factors, page limits, key dates, clearances, risks, or where a document disagrees with the notice.
```

| Kind   | Field                | Instructions                                                                                                                                                                                                                     | Settings                         |
| ------ | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Gov Notice record Id | Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id.    | Require **Yes** · Collect **No** |
| Output | Documents            | What the Document Reader found in each file: requirements, evaluation factors, dates, risks, and where a file disagrees with the notice; also files not read yet. Say it was read by AI and should be checked against the files. | Show **Yes**                     |

#### NXP Find Incumbent (Market Intel)

Agent action instructions:

```text
Use when the user asks who holds the work now, who the incumbent is, or what the previous award was for a notice.
```

| Kind   | Field                | Instructions                                                                                                                                                                                                                  | Settings                         |
| ------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Gov Notice record Id | Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id. | Require **Yes** · Collect **No** |
| Output | Answer               | The incumbent vendor, the predecessor award and its end date, or a statement that none was found. Do not add vendors that are not in it.                                                                                      | Show **Yes**                     |

#### NXP Recompete Query (Market Intel)

Agent action instructions:

```text
Use when the user asks which contracts are ending soon or which recompetes are coming, optionally by agency, NAICS or size.
```

| Kind   | Field         | Instructions                                                                                                    | Settings                         |
| ------ | ------------- | --------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Agency        | Agency name or part of it, for example Veterans Affairs. Leave empty for all agencies.                          | Require **No** · Collect **Yes** |
| Input  | NAICS         | A NAICS code, or a prefix ending in \* such as 5415\*. Leave empty for all codes.                               | Require **No** · Collect **Yes** |
| Input  | Months ahead  | How many months ahead to look for awards ending. Use the user's number; otherwise leave empty for 18.           | Require **No** · Collect **Yes** |
| Input  | Minimum value | Lowest award value in dollars, as a plain number (10000000 for $10M). Leave empty for any value.                | Require **No** · Collect **Yes** |
| Output | Recompetes    | Awards ending in the window, one per line, and the data window used. Always repeat the data window to the user. | Show **Yes**                     |

#### NXP Preview Push (Push)

Agent action instructions:

```text
Use first whenever the user wants to send a notice to Opportunity. Shows the values that would be sent and whether a matching Opportunity already exists. Sends nothing.
```

| Kind   | Field                | Instructions                                                                                                                                                                                                                  | Settings                         |
| ------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Gov Notice record Id | Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id. | Require **Yes** · Collect **No** |
| Output | Preview              | The values that will be sent to Opportunity and whether a matching record already exists. Show it in full before asking for a yes.                                                                                            | Show **Yes**                     |
| Output | Preview token        | Proof the user saw this preview. Do not show it. Pass it to NXP Push To Opportunity for this same notice.                                                                                                                     | Show **No**                      |
| Output | Existing record Id   | Set when a matching Opportunity already exists. The push will link to it instead of creating a new one; tell the user that.                                                                                                   | Show **No**                      |

#### NXP Push To Opportunity (Push)

Agent action instructions:

```text
Use only after NXP Preview Push has been shown for this notice and the user has said yes. Creates the Opportunity, or links the existing one.
```

| Kind   | Field                 | Instructions                                                                                                                                                                                                                                            | Settings                         |
| ------ | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Gov Notice record Id  | Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no page is open, ask the user to open it. Must be the notice that was previewed. Never guess. | Require **Yes** · Collect **No** |
| Input  | Preview token         | The Preview token output of NXP Preview Push for this same notice, from this conversation. Never make one up.                                                                                                                                           | Require **Yes** · Collect **No** |
| Output | Status                | Success, Linked Existing or Failed.                                                                                                                                                                                                                     | Show **Yes**                     |
| Output | Opportunity record Id | Id of the Opportunity created or linked. Offer to open it.                                                                                                                                                                                              | Show **Yes**                     |
| Output | Message               | What happened, including the reason if it failed. Tell the user.                                                                                                                                                                                        | Show **Yes**                     |

#### NXP Push Status (Push)

Agent action instructions:

```text
Use when the user asks whether a notice was pushed, whether a push failed, or why.
```

| Kind   | Field                | Instructions                                                                                                                                                                                                                  | Settings                         |
| ------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Input  | Gov Notice record Id | Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id. | Require **Yes** · Collect **No** |
| Output | Status               | Up to the five most recent pushes of the notice, newest first: time, how it was pushed, result, record and any error. Or a note that it was never pushed.                                                                     | Show **Yes**                     |

#### NXP Set Auto-Push Rule (Push)

Agent action instructions:

```text
Use when the user asks to turn auto-push on, off or change its threshold on one of their saved searches. Power Users only. Confirm the search and the setting with the user first.
```

| Kind   | Field             | Instructions                                                                                                                                                                              | Settings                          |
| ------ | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Input  | Saved search Id   | Id of a saved search the user owns. Take it from the Saved search Id output of NXP Save Search in this conversation, or from the saved search record page the user has open. Never guess. | Require **Yes** · Collect **No**  |
| Input  | Mode              | Exactly one of: Off, Fit Threshold, All Matches.                                                                                                                                          | Require **Yes** · Collect **Yes** |
| Input  | Minimum fit score | Lowest fit score, 0 to 100, that is pushed automatically. Required when Mode is Fit Threshold; leave empty otherwise.                                                                     | Require **No** · Collect **Yes**  |
| Output | Message           | The result, or why it was refused (for example, the user is not a Power User or does not own the search).                                                                                 | Show **Yes**                      |

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
