# Admin guide

## First-time configuration

1. **Assign permission sets:**
    - `NXP_User` to every BD user.
    - `NXP_Power_User` as well, for BD leads.
    - `NXP_Admin` to admins and to the user who schedules jobs.
    - `NXP_Integration` to the REST integration user only.
2. **SAM.gov API key:** go to Setup → Named Credentials → External Credentials → **NXP SAM.gov** → Principals → _Default_ → Authentication Parameters → add `ApiKey` with the key from your SAM.gov account (System Account key for higher limits). Users who run feeds need the principal, which `NXP_Admin` grants.
3. **Forecast endpoint:** edit Named Credential **NXP Agency Forecasts** to your forecast API URL and adjust the `FC_*` feed mappings to its field names.
4. **Company profile:** create one active **Company Profile**, with your NAICS (prefix `5415*` allowed), PSC, set-asides you qualify for, target agencies (names as they appear in agency paths), capability keywords and value range. Then run `scripts/apex/rescore-notices.apex`.
5. **Push mapping:** see [Push mapping](#push-mapping).
6. **Schedule jobs:** run `scripts/post-deploy/schedule-jobs.apex`, as an `NXP_Admin` user.
7. **Activate the Gov Notice record page** if your org overrides it: Lightning App Builder → _Gov Notice Record Page_ → Activation. The Nexus Pursuit Hub app already assigns it.
8. **Notifications:** Setup → Custom Notifications → _NXP Match Alert_ → enable desktop and mobile delivery. Users who want Slack or Teams alerts need the Salesforce for Slack or Teams integration to forward notifications.

## Feeds

Feeds are `NXP_Feed_Config__mdt` records. Change them through `env-config/<env>` and deploy, so environments stay reproducible. In an emergency, Setup → Custom Metadata Types also works; retrieve the change afterwards.

| Field                                              | Meaning                                                                  |
| -------------------------------------------------- | ------------------------------------------------------------------------ |
| Active                                             | Feed runs when due                                                       |
| Connector Class / Named Credential / Endpoint Path | Where and how it fetches                                                 |
| Page Size                                          | Records per callout (SAM.gov max 1000)                                   |
| Lookback Days                                      | Window for the first run; later runs start a day before the last success |
| Interval (minutes)                                 | How often it is due (scheduler checks hourly)                            |
| Channel                                            | Standard Pipeline (Queueable) or Scheduled Batch                         |
| Extra Query Parameters                             | `a=1&b=2` sent with each call; keys starting `_` are connector options   |

**Feed Console** shows health per feed: Healthy, Warning (some rejected), Failed, Running, Paused, Never run. _Run now_ needs NXP Admin Access, and _Errors_ shows the run's error log.

## Fit rules

`NXP_Fit_Rule__mdt`: active weights should sum to 100. Shipped weights are NAICS 30, Agency 20, Set-Aside 15, Keyword 20 (three keywords give full points) and Value Range 15. PSC and Vehicle ship off. After changes, run `rescore-notices.apex`.

## Push mapping

1. Find TechnoMile's opportunity object and required fields in Object Manager.
2. In `NXP_Push_Mapping__mdt` (mapping set `TechnoMile_Default`), set `Target_Object__c` on every row to that object. Point `Target_Field__c` at its fields, and set the default stage to a valid value.
3. Recommended: add a text field `NXP_Solicitation_Number__c` to the TechnoMile object, and a row from `Solicitation_Number__c` to that field with Sync Behavior _Never_, to turn on duplicate detection.
4. Decide sync behaviour per field: Update (due date), Alert Only (value, set-aside), Never (name, stage).
5. Test in a sandbox: push a sample notice, check the record, then amend the notice (or re-run a feed) and check the sync.

## Settings (`NXP_Setting__mdt`)

| Key                                               | Default              | Purpose                                                                         |
| ------------------------------------------------- | -------------------- | ------------------------------------------------------------------------------- |
| `AI_Enabled`                                      | false                | Turns on AI summaries and the AI criteria draft (needs active prompt templates) |
| `Max_Searches_Per_User` / `Max_RealTime_Searches` | 50 / 20              | Bound matching load                                                             |
| `Inbox_Days`                                      | 30                   | Match Inbox window                                                              |
| `Push_Mapping_Set`                                | TechnoMile_Default   | Active push mapping set                                                         |
| `Push_Max_Attempts`                               | 3                    | Auto-push retries                                                               |
| `Match_Listeners`                                 | NXP_AutoPushListener | Classes called on new matches                                                   |
| `Http_Max_Attempts`, `Http_Timeout_Ms`            | 3, 60000             | Callout retry and timeout                                                       |
| `Batch_Max_Pages`, `Queue_Max_Pages`              | 200, 50              | Pages per run                                                                   |
| `Rest_Max_Records`                                | 200                  | REST batch limit                                                                |
| `Alert_OrgWide_Email_Id`                          | (none)               | Org-wide address alerts come from                                               |
| `Bypass_NXP_GovNoticeTriggerHandler`              | (none)               | Emergency trigger switch (set Value to true)                                    |

## Monitoring

- Run `scripts/apex/feed-health.apex` or open the Feed Console daily during the first weeks.
- Check reports on `NXP_Log__c` (Level = ERROR) and on `NXP_Push_Log__c` (Status = Failed).
- Check platform event subscriber status after deployments.
- To pause everything: `scripts/post-deploy/unschedule-jobs.apex`. To resume: `schedule-jobs.apex`.
