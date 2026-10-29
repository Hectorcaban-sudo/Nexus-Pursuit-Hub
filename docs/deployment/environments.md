# Environments

| Environment   | Org type                         | Purpose                                                  | Gets changes by                                                         | env-config | Feeds on                             |
| ------------- | -------------------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------- | ---------- | ------------------------------------ |
| Dev (feature) | Scratch org or Developer sandbox | One story                                                | `scripts/dev-setup.sh`, then source tracking                            | `dev`      | SAM_Opportunities (page size 100)    |
| Agent dev     | Developer sandbox                | Agentforce, Prompt Builder, Data Cloud work              | Deploy from branch                                                      | `dev`      | as dev                               |
| INT           | Developer Pro sandbox            | Every merge to `main`                                    | `scripts/release.sh dev nxp-int`                                        | `dev`      | as dev                               |
| QA            | Partial Copy sandbox             | Functional and regression testing                        | `scripts/release.sh qa nxp-qa` on a tag                                 | `qa`       | SAM opportunities, entity, forecasts |
| UAT           | Full sandbox                     | Business acceptance, performance, parallel run vs GovWin | `scripts/release.sh uat nxp-uat` after approval                         | `uat`      | All, AI on                           |
| Production    | Production                       | Users                                                    | `scripts/release.sh prod nxp-prod` after approval, in the change window | `prod`     | All, AI on                           |

## Rules

- **API version:** all orgs must be on API 68.0 before a release.
- **No manual changes:** don't change metadata by hand in INT, QA, UAT or production. Retrieve any Setup change into a branch and release it.
- **Credentials:** SAM.gov API keys are set per org on the `NXP_SAM_Gov` principal. Sandboxes refreshed from production keep the production key; replace it with a test key after each refresh.
- **Sample data:** dev, INT and QA only (`load-sample-data`); never UAT or production. The loader refuses production orgs.
- **Post-refresh steps for sandboxes:** see [Sandbox refresh](deployment-guide.md#sandbox-refresh).
- **Scripts:** the commands above are the bash versions; on Windows use the `.ps1` scripts with the same names (`.\scripts\release.ps1 -Environment qa -Org nxp-qa`).

## env-config

Each `env-config/<env>` is a small DX project, so it deploys on its own. It holds:

- `NXP_Feed_Config__mdt` (which feeds are active, page sizes);
- `NXP_Setting.Org_Environment`;
- `NXP_Setting.AI_Enabled`.

Add environment-specific values here (for example a different push mapping set), never in the packages.
