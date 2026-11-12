# Building the Nexus Pursuit Assistant with Agent Script

Use this guide when your org has the new Agentforce Builder with Agent Script. The whole assistant (subagents, actions, input and output descriptions and the guardrails) is one file that you deploy, validate, publish and activate from the command line, instead of rebuilding it by hand in each org.

If your org doesn't have Agent Script yet, use the [manual build guide](agent-manual-build.md). Both build the same assistant.

## What's in the repository

| Path                                                                               | What it is                                                                                                                                                        |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/nxp-agent-script/main/default/aiAuthoringBundles/NXP_Pursuit_Assistant/` | The agent: `NXP_Pursuit_Assistant.agent` and its `bundle-meta.xml`. Its own package directory, so it is deployed only when you ask for it (not by `release.ps1`). |
| `scripts/agent-script/gen_agent.py`                                                | Writes the `.agent` file from the Apex actions and the subagent text. Run it after changing an action's labels, descriptions, inputs or outputs.                  |
| `packages/nxp-agents/main/default/classes/NXP_*Action.cls`                         | The actions the agent calls. Their `@InvocableVariable` descriptions are copied into the `.agent` file.                                                           |
| `packages/nxp-agents/reference/genAiPromptTemplates/`                              | The prompt templates, created in Prompt Builder as before.                                                                                                        |

## What the script adds over the manual build

The subagents, scopes and action descriptions are the same as in the manual build. Agent Script adds rules the model can't skip:

| Rule                                                                                           | How                                                                                                         |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Save Search** is offered only after a preview, and uses the token from that preview          | `available when @variables.search_preview_token != ""`, `with previewToken=@variables.search_preview_token` |
| **Push To Opportunity** is offered only after Preview Push, and uses that preview's token      | `available when @variables.push_preview_token != ""`, `with previewToken=@variables.push_preview_token`     |
| A save or push clears its token, so the next one needs a new preview                           | `set @variables.…_preview_token = ""`                                                                       |
| Save Search, Push To Opportunity and Set Auto-Push Rule ask the user to confirm                | `require_user_confirmation: True`                                                                           |
| While a preview waits for an answer, "yes" goes back to the subagent that showed it            | Conditional instructions in the router                                                                      |
| Preview tokens, criteria JSON and record Ids are passed between actions but not shown to users | `is_displayable: False` on those outputs                                                                    |

The Apex actions still check the preview tokens and permissions themselves ([ADR 0007](../adr/0007-agent-script.md)), so the guardrails hold even in orgs that use the manual build.

## Before you start

1. **Deploy the packages** as usual, at least `nxp-core` through `nxp-agents`: the agent refers to the Apex actions, which must exist first.
2. **Agentforce on:** Setup → Agentforce Agents shows the new builder, and Einstein and Agentforce are covered by your ATO.
3. **Prompt templates** created and active, and `AI_Enabled` on, as in the [manual build guide](agent-manual-build.md#before-you-start) (steps 2 to 4).
4. **Salesforce CLI** up to date, with the agent commands: `sf update`, then `sf agent --help` lists `validate`, `publish` and `activate`.
5. **An agent you built by hand earlier:** it has the same API name, `NXP_Pursuit_Assistant`. In Agentforce Builder, deactivate it before publishing. If publishing then fails because the name is taken, either delete the manual agent, or rename this one: change `developer_name` in the `.agent` file and rename the folder and both files to the new name (they must match).

## Deploy, check and publish

Run these from the repository folder in PowerShell (replace `staging` with your org alias):

```powershell
git pull

# 1. Check the script against the org (actions exist, types match, syntax).
sf agent validate authoring-bundle --api-name NXP_Pursuit_Assistant --target-org staging

# 2. Deploy the bundle (creates or updates the agent's draft in the org).
sf project deploy start --source-dir packages/nxp-agent-script --target-org staging --wait 30

# 3. Publish a version of the agent from the bundle, then turn it on.
sf agent publish authoring-bundle --api-name NXP_Pursuit_Assistant --target-org staging
sf agent activate --api-name NXP_Pursuit_Assistant --target-org staging
```

Fix anything `validate` reports before going further. The CLI is changing quickly: if a command or flag isn't recognized, check `sf agent <command> --help` for the current name.

Then give users access: Setup → **Agentforce Agents** → _Nexus Pursuit Assistant_ → access, or add the agent to the `NXP_User` permission set (**Agent Access**). Users also need `NXP_User` for the action classes.

## Try it before users do

```powershell
sf agent preview start --authoring-bundle NXP_Pursuit_Assistant --use-live-actions --target-org staging
```

Then send messages with `sf agent preview send` and end with `sf agent preview end`. Or open the agent in Agentforce Builder and use its preview panel on a Gov Notice page. Check at least:

| Say                                                   | Expect                                                                                    |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| "Alert me daily about DHS zero trust work over $5M"   | Search Builder drafts, previews (count and top five) and asks before saving               |
| "Save it" before any preview                          | No save; it previews first                                                                |
| On a notice: "Why is the fit score 36?"               | Notice Briefing explains the fit rules                                                    |
| On a notice: "Who is the incumbent?"                  | Market Intel names the predecessor award, or says none was found                          |
| On a notice: "Push this to Opportunity", then "yes"   | Preview with mapped values, a confirmation, then the Opportunity                          |
| On a notice: "Should we bid on this?"                 | Opportunity Analysis returns a bid / no-bid brief with source tags and (assumption) marks |
| "Who wins most in NAICS 541512 at Homeland Security?" | Market Intel lists vendors with award counts and the data window                          |
| "What's our pWin on this?"                            | Declines: managed in Opportunity                                                          |

Validation passing doesn't prove behaviour: read the trace in the preview (which subagent, which action ran, which inputs) for each test.

## Changing the agent

- **Instruction or scope text:** edit `scripts/agent-script/gen_agent.py` (the subagent text) and run it, or edit the `.agent` file directly and accept that the next generator run overwrites it.
- **An action's label, description, inputs or outputs:** change the Apex `@InvocableVariable` / `@InvocableMethod` annotations, deploy `nxp-agents`, then run `python scripts/agent-script/gen_agent.py` so the `.agent` file matches.
- **A new action:** add the Apex class, then add it to the right subagent in `gen_agent.py` (definition and reasoning binding) and regenerate.
- After any change: `validate`, deploy the bundle, `publish`, `activate`, and run the checks above again.

Changes made in Agentforce Builder's script editor are not in the repository. Retrieve the bundle afterwards (`sf project retrieve start --metadata AiAuthoringBundle:NXP_Pursuit_Assistant --target-org staging`) and copy the change into `gen_agent.py`, or the next deploy undoes it.

## Moving to another org

The `.agent` file is the same for every org. For each one: deploy the packages, create the prompt templates, then run the four commands above against that org's alias. Orgs without Agent Script still use the [manual build guide](agent-manual-build.md); don't deploy `packages/nxp-agent-script` to them.
