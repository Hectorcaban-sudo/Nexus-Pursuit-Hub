# nxp-agents/reference

Prompt templates for the Nexus Pursuit Hub AI features. **Nothing in this folder is deployed**: `.forceignore`
excludes it. The assistant itself is in `packages/nxp-agent-script` ([agent script build](../../../docs/guides/agent-script-build.md)).

| Folder                  | What it is                                                                                         | How to use it                                                                                                                                                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `genAiPromptTemplates/` | Prompt Builder templates used by the assistant and by the background jobs (`NXP_NoticeAnalystJob`) | Create each in Prompt Builder with the same API name and text, or move the file into `main/default/genAiPromptTemplates/` to deploy it where the org accepts the metadata. Activate, then set `NXP_Setting.AI_Enabled = true`. |
