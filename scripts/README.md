# scripts

Every script has a bash version (`.sh`: macOS, Linux, WSL, Git Bash) and a PowerShell version (`.ps1`: Windows PowerShell 5.1 or PowerShell 7 on any OS). Both run the same `sf` commands; pick the one for your shell. Run them from anywhere: they change to the repository root themselves.

| Purpose                                        | Bash                                                    | PowerShell                                                                            |
| ---------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Install into a scratch org or sandbox          | `dev-setup.sh [--org <alias>] [--no-sample-data]`       | `dev-setup.ps1 [-Org <alias>] [-NoSampleData]`                                        |
| Load, reset or delete the sample data          | `load-sample-data.sh --org <alias> [--reset\|--delete]` | `load-sample-data.ps1 -Org <alias> [-Reset\|-Delete]`                                 |
| Functional test (REST API + end-to-end checks) | `test-functional.sh --org <alias> [--apex-tests]`       | `test-functional.ps1 -Org <alias> [-ApexTests]`                                       |
| Pre-PR checks (+ check-only deploy)            | `validate.sh [--org <alias>]`                           | `validate.ps1 [-Org <alias>]`                                                         |
| Release to an environment                      | `release.sh <env> <alias> [source\|package]`            | `release.ps1 -Environment <env> -Org <alias> [-Mode package]`                         |
| Create unlocked package versions               | `create-package-versions.sh <devhub> [key]`             | `create-package-versions.ps1 -DevHub <devhub> [-InstallationKey k] [-CreatePackages]` |
| Uninstall                                      | `uninstall.sh --org <alias> [--mode package] [--purge]` | `uninstall.ps1 -Org <alias> [-Mode package] [-Purge]`                                 |
| Data Cloud bulk upload (in `datacloud/`)       | `upload-awards.sh <csv>`                                | `upload-awards.ps1 -CsvFile <csv>`                                                    |

Help: `scripts/<name>.sh --help`, or `Get-Help .\scripts\<name>.ps1 -Detailed`.

Windows: if PowerShell refuses to run scripts, run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once.

## Folders

| Folder         | Contents                                                                                                                                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/`         | Shared helpers: `common.sh` and `common.ps1` (package order, API version, running anonymous Apex, production check)                                                                                                |
| `apex/`        | Anonymous Apex: sample data (`seed-profile`, `seed-searches`, `seed-ebuy-email`, `refresh-sample-dates`, `delete-sample-data`), `smoke-test`, and admin helpers (`run-feed-now`, `feed-health`, `rescore-notices`) |
| `post-deploy/` | `schedule-jobs.apex` and `unschedule-jobs.apex`                                                                                                                                                                    |
| `uninstall/`   | `pre-uninstall.apex`: stops NXP jobs and removes NXP permission set assignments                                                                                                                                    |

Run any anonymous Apex file on its own with `sf apex run --file scripts/apex/<file>.apex --target-org <alias>`.
