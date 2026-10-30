# GovWin parallel run

During the parallel run, export the opportunities GovWin IQ alerted on each week and load them into Nexus, so the
**Adoption** dashboard can show how many Nexus also caught.

1. Export your GovWin alerts or saved-search results to CSV.
2. Rename the columns to match `govwin-export-template.csv`:

    | Column                   | From GovWin                                       | Required |
    | ------------------------ | ------------------------------------------------- | -------- |
    | `GovWin_Id__c`           | GovWin opportunity ID (unique; reloading updates) | Yes      |
    | `Title__c`               | Opportunity title                                 |          |
    | `Solicitation_Number__c` | Solicitation number (this is what is matched)     | Yes      |
    | `Agency__c`              | Agency                                            |          |
    | `Alert_Date__c`          | Date of the alert, `YYYY-MM-DD`                   |          |

3. Save it with LF line endings and UTF-8, then load and compare:

    ```bash
    scripts/load-govwin-export.sh --org nxp-uat --file govwin-week1.csv
    ```

    ```powershell
    .\scripts\load-govwin-export.ps1 -Org nxp-uat -File govwin-week1.csv
    ```

Each alert gets a result: **Caught by a search** (a Nexus notice with that solicitation number matched someone's saved
search), **In Nexus, no search matched** (Nexus has it, but no search would have alerted), or **Not in Nexus**. Look at
the last two to tune searches or feeds. Run the load again to re-compare after changing searches.
