# Deployment guide

Nexus Pursuit Hub is released with scripted `sf` commands (no CI/CD pipeline). The same six package folders can be released two ways. Pick one per org and stay with it.

|          | Direct source deploy (default)                                                   | Unlocked packages                                                        |
| -------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Command  | `scripts/release.sh <env> <alias>`                                               | `scripts/release.sh <env> <alias> package`                               |
| Unit     | One metadata deployment of all folders                                           | Six package versions in dependency order                                 |
| Rollback | Redeploy the previous Git tag; remove new components with a destructive manifest | Reinstall the previous promoted versions                                 |
| Tests    | `RunLocalTests` during validation                                                | Coverage checked at version creation; `RunLocalTests` recommended in UAT |
| Best for | Change boards that approve metadata deployments; hotfixes                        | Long-term upgrades, clean uninstall                                      |

![Release workflow](../diagrams/09-deployment-workflow.jpg)

## Prerequisites

- **API version:** every target org is on the Salesforce release that supports **API 68.0**. Check sandboxes too; an org on an older release rejects 68.0 metadata.
- **CLI login:** `sf org login web --alias nxp-<env> --instance-url https://<my-domain>.my.salesforce.com`. For Government Cloud, use your org's My Domain URL.
- **Deploying user:** a System Administrator.
- **Org features:** Platform Events and Custom Notifications on (both standard). Einstein/Agentforce are needed only for AI and the assistant.

## Release with source deploy

```bash
git switch main && git pull
git tag v1.0.0 && git push --tags
scripts/release.sh uat nxp-uat
```

`release.sh` does the following:

1. **Generate the manifest:** `sf project generate manifest` → `manifest/release-<tag>.xml`, to attach to the change record.
2. **Validate:** `sf project deploy validate` with `RunLocalTests`. Prints the job ID.
3. **Confirm and quick-deploy:** `sf project deploy quick --job-id <id>`, without re-running tests. You can quick-deploy later, inside the change window, while the validation is still valid.
4. **Deploy `env-config/<env>`:** feed switches, `Org_Environment`, `AI_Enabled`.
5. **Schedule jobs:** runs `scripts/post-deploy/schedule-jobs.apex`.
6. **Finish the checklist:** [post-deployment checklist](post-deployment-checklist.md).

Manual equivalent:

```bash
sf project deploy validate --source-dir packages/nxp-core packages/nxp-ingestion packages/nxp-search \
  packages/nxp-push packages/nxp-experience packages/nxp-agents \
  --target-org nxp-prod --api-version 68.0 --test-level RunLocalTests --wait 90
sf project deploy quick --job-id 0Af... --target-org nxp-prod
(cd env-config/prod && sf project deploy start --source-dir force-app --target-org nxp-prod)
sf apex run --file scripts/post-deploy/schedule-jobs.apex --target-org nxp-prod
```

## Release with unlocked packages

One-time setup:

```bash
for p in nxp-core nxp-ingestion nxp-search nxp-push nxp-experience nxp-agents; do
  sf package create --name $p --package-type Unlocked --path packages/$p --no-namespace --target-dev-hub nxp-devhub
done
```

Each release:

```bash
scripts/create-package-versions.sh nxp-devhub          # versions in dependency order, with code coverage
cp release/versions.example.json release/versions.json # fill in the new version aliases
scripts/release.sh qa nxp-qa package
sf package version promote --package nxp-core@1.0.0-1 --target-dev-hub nxp-devhub   # each, after QA
scripts/release.sh prod nxp-prod package
```

Don't mix the two paths in one org: components installed by a package can't later be replaced by plain source deploys.

## Rollback

| Path    | Steps                                                                                                                                                                                                    |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Source  | `git checkout v<previous>`, then `scripts/release.sh <env> <alias>`. For components added in the bad release, add `--post-destructive-changes manifest/destructiveChangesPost.xml` to the validate step. |
| Package | Reinstall the previous promoted version of each package that changed, in dependency order                                                                                                                |
| Data    | Releases never delete data. Two-step any change that makes a field required (release 1 adds it; release 2 makes it required) so rollback stays possible.                                                 |

Before a risky release, run `scripts/post-deploy/unschedule-jobs.apex` to pause feeds. After it, run `schedule-jobs.apex` again.

## Agent release

Retrieve the manually built agent into `packages/nxp-agents/main/default/` (see [agent manual build](../guides/agent-manual-build.md#step-by-step)) so it ships with the release. After deployment, activate it in the target org and assign access. Activation is never automatic.
