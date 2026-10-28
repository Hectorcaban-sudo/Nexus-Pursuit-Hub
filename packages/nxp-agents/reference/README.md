# nxp-agents/reference

Reference design for the Nexus Pursuit Hub agents. **Nothing in this folder is deployed by default**:
`.forceignore` excludes it, because Agent Script is not available in Government Cloud.

| Folder                                      | What it is                                                                                                        | How to use it                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aiAuthoringBundles/NXP_Pursuit_Assistant/` | Agent Script (`.agent`) blueprint of the Nexus Pursuit Assistant: four subagents, actions and deterministic rules | **Commercial orgs:** validate and publish with `sf agent validate authoring-bundle` and `sf agent publish authoring-bundle --api-name NXP_Pursuit_Assistant`. **Government Cloud:** build the agent by hand in Agentforce Builder from [docs/guides/agent-manual-build.md](../../../docs/guides/agent-manual-build.md); this file is the spec. |
| `genAiPromptTemplates/`                     | Prompt Builder templates used by the assistant and by the background jobs (`NXP_NoticeAnalystJob`)                | Create each in Prompt Builder with the same API name and text, or move the file into `main/default/genAiPromptTemplates/` to deploy it where the org accepts the metadata. Activate, then set `NXP_Setting.AI_Enabled = true`.                                                                                                                 |

Agent Script is a beta language and its syntax changes between releases. Run `sf agent validate authoring-bundle`
against your target org and fix anything it reports before publishing. After a manual build, retrieve the agent
at API 68.0 (`AiAgentDefinition`, `AiAgentDefinitionVersion`) into `main/default/` so later environments are
deployed rather than rebuilt.
