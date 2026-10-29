# data

| Folder      | Contents                                                                                                                                                                                                                 | Used by                                                                     |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `seed/`     | Sample agencies, contract vehicles and 10 **sample** notices (`SAMPLE-0001`…`SAMPLE-0010`) as CSV files, loaded in file-name order with Bulk API upserts on external IDs                                                 | `scripts/load-sample-data.sh` / `.ps1` (called by `dev-setup`)              |
| `fixtures/` | Recorded API response shapes (SAM.gov opportunities, USAspending awards), an example REST request, and `rest-sample-notice.json` for testing the HTTP endpoint by hand (replace `{{TODAY}}` and `{{DUE_30}}` with dates) | Apex tests (inline copies), API docs, `scripts/test-functional.sh` / `.ps1` |

The sample Company Profile and saved searches are created by Apex (`scripts/apex/seed-profile.apex`, `seed-searches.apex`) because they depend on the running user.

Load, reset or delete the sample data:

```bash
scripts/load-sample-data.sh --org nxp-dev            # PowerShell: .\scripts\load-sample-data.ps1 -Org nxp-dev
scripts/load-sample-data.sh --org nxp-dev --reset    # -Reset
scripts/load-sample-data.sh --org nxp-dev --delete   # -Delete
```

What gets loaded, the expected results and how to test with it: [testing guide](../docs/guides/testing-guide.md#test-with-sample-data).

Sample data is for development, scratch and QA orgs only. Never load it into UAT or production (the loader refuses a production org).

Keep the CSV files with LF line endings (`.gitattributes` does this); the loaders upload them with `--line-ending LF`.
