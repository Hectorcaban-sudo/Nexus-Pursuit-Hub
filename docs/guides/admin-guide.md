# Admin guide

## First-time configuration

1. **Assign permission sets:**
    - `NXP_User` to every BD user.
    - `NXP_Power_User` as well, for BD leads.
    - `NXP_Admin` to admins and to the user who schedules jobs.
    - `NXP_Integration` to the REST integration user only (also the context user of the eBuy e-mail service).
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

`NXP_Fit_Rule__mdt`: active weights should sum to 100. Shipped weights are NAICS 30, Agency 20, Set-Aside 15, Keyword 20 (three keywords give full points) and Value Range 15. PSC and Vehicle ship off. The Vehicle rule gives full points when the notice is on a contract vehicle we hold (**We Hold** ticked on the vehicle, or its code in the profile's _Vehicles We Hold_); to use it, give it a weight and lower another rule so the total stays 100. After changes, run `rescore-notices.apex`.

## Push mapping

1. Find the Opportunity object and required fields in Object Manager.
2. In `NXP_Push_Mapping__mdt` (mapping set `Opportunity_Default`), set `Target_Object__c` on every row to that object. Point `Target_Field__c` at its fields, and set the default stage to a valid value.
3. Recommended: add a text field `NXP_Solicitation_Number__c` to the Opportunity object, and a row from `Solicitation_Number__c` to that field with Sync Behavior _Never_, to turn on duplicate detection.
4. Optional: map `Contract_Vehicle_Code__c` to the Opportunity's contract vehicle field, and `Notice_URL__c` to a link field if it has one. The shipped Description row uses `Push_Details__c` (source, IDs, vehicle, due date and link in one line).
5. Decide sync behaviour per field: Update (due date), Alert Only (value, set-aside), Never (name, stage).
6. Test in a sandbox: push a sample notice, check the record, then amend the notice (or re-run a feed) and check the sync.

## GSA eBuy e-mail

eBuy has no API, so RFQs come in through the e-mail eBuy sends your company. The `NXP_Ebuy_Inbox` e-mail service records each message as an **Inbound Email** (admins only), saves its attachments as Files, reads the RFQ fields and creates or updates a _Task Order_ notice keyed `EBUY:<RFQ number>` on the vehicle. The **Inbound Emails** tab lists every message with its status; fix and **Reprocess** the ones marked _Needs Review_.

1. **Check the org allows inbound e-mail services** (Setup → Email Services). Confirm with your ATO owner that eBuy RFQ text may be stored in this org.
2. **Create the address:** Setup → Email Services → `NXP_Ebuy_Inbox` → **New Email Address**. Context user: the integration user (it owns the records). _Accept Email From_: `gsa.gov` plus your own domain if colleagues forward mail. Copy the generated address.
3. **Route eBuy mail to it:** either set that address as a notification e-mail in your eBuy contractor profile, or add a mail rule that **redirects** (not forwards) eBuy messages to it. A redirect keeps GSA as the sender; a forward makes your colleague the sender, so their domain must then be added to `Ebuy_Allowed_Senders`.
4. **Pick the vehicle:** put the address eBuy sends to (your alias, or the service address) in the contract vehicle's **Inbox Address**. E-mail to any other address goes to the `Ebuy_Default_Vehicle` (GSA-MAS-IT).
5. **Optional AI:** create the `NXP_Ebuy_RFQ_Extract` prompt template from `packages/nxp-agents/reference/genAiPromptTemplates/` and set `AI_Enabled = true`. AI only fills fields the rules miss, and code checks every value. To let it read the first PDF attachment, add a File input named _Attachment_ to the template, choose a model that reads files, and set `Ebuy_AI_Read_Attachments = true`.
6. **Send eBuy RFQs to Opportunity automatically** (bid/no-bid stays in Opportunity): create a saved search with notice type _Task Order_, your vehicles, Real Time alerts and Auto-Push _Fit Threshold_ (for example 60). eBuy RFQs often close in one to two weeks, so this saves the wait for someone to push them. Auto-push needs `NXP_Power_User`. The sample data has one: _SAMPLE - eBuy RFQs on our vehicles_.
7. **Tune the rules** to your real e-mails: the accepted labels for each field are in `NXP_EbuyEmailParser.LABELS`.

What is kept and who sees it:

- Mail from senders not in `Ebuy_Allowed_Senders` is recorded as _Rejected_, with no notice and no attachments. Executable and HTML attachments are never kept.
- The raw e-mail, sender addresses and the extraction log are on the Inbound Email record, which only `NXP_Admin` can open.
- The notice is readable by every Nexus user, like all notices. Attachments are linked to it unless `Ebuy_Share_Files_With_Notice = false`, in which case only admins (on the Inbound Email) can open them.

## Document Reader

Reads PDF files attached to notices (eBuy attachments and uploads on the notice page's **Documents** card) with the `NXP_Document_Analysis` prompt template, and stores the result on an `NXP_Document_Analysis__c` row per file, readable by everyone who can read the notice.

1. In Prompt Builder, create `NXP_Document_Analysis` (Flex) from `packages/nxp-agents/reference/genAiPromptTemplates/`. Add a second input: **File**, API name `Document`, and insert it in the template where it says "the attached document". Choose a model that reads PDF files (Prompt Builder shows each model's file limits). Activate it.
2. Set `AI_Enabled = true` and `Document_Analysis_Enabled = true`.
3. Open a notice with a PDF and click **Analyze**. In a sandbox, check a few results against the documents before you rely on them.

Files are read when attached (at most `Document_Max_Per_Notice` per notice automatically; the rest with Analyze), one per background job; files waiting when analysis couldn't start are picked up by the next Notice Analyst run. PDFs over `Document_Max_MB` and non-PDF files are listed but not read. Each read is one AI call through the Einstein Trust Layer; confirm your ATO allows sending solicitation documents to the model. The model only returns field values, which code checks; it can't change records. Turn the trigger off in an emergency with `Bypass_NXP_DocumentService = true`.

SAM.gov attachments are not downloaded automatically yet: add them to the notice from SAM.gov (download, then **Add documents**).

## Settings (`NXP_Setting__mdt`)

| Key                                                        | Default                       | Purpose                                                                         |
| ---------------------------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------- |
| `AI_Enabled`                                               | false                         | Turns on AI summaries and the AI criteria draft (needs active prompt templates) |
| `Max_Searches_Per_User` / `Max_RealTime_Searches`          | 50 / 20                       | Bound matching load                                                             |
| `Inbox_Days`                                               | 30                            | Match Inbox window                                                              |
| `Push_Mapping_Set`                                         | Opportunity_Default           | Active push mapping set                                                         |
| `Push_Max_Attempts`                                        | 3                             | Auto-push retries                                                               |
| `Match_Listeners`                                          | NXP_AutoPushListener          | Classes called on new matches                                                   |
| `Http_Max_Attempts`, `Http_Timeout_Ms`                     | 3, 60000                      | Callout retry and timeout                                                       |
| `Batch_Max_Pages`, `Queue_Max_Pages`                       | 200, 50                       | Pages per run                                                                   |
| `Rest_Max_Records`                                         | 200                           | REST batch limit                                                                |
| `Ebuy_Allowed_Senders`                                     | gsa.gov                       | Addresses or domains the eBuy inbox accepts                                     |
| `Ebuy_Default_Vehicle`                                     | GSA-MAS-IT                    | Vehicle for eBuy e-mail that isn't sent to a vehicle's Inbox Address            |
| `Ebuy_AI_Template` / `Ebuy_AI_Read_Attachments`            | NXP_Ebuy_RFQ_Extract / false  | AI extraction template; whether it also reads the first PDF                     |
| `Document_Analysis_Enabled` / `Document_Analysis_Template` | false / NXP_Document_Analysis | Document Reader on notice PDFs (needs `AI_Enabled`)                             |
| `Document_Max_MB` / `Document_Max_Per_Notice`              | 10 / 5                        | Largest PDF sent to the model; files read automatically per notice              |
| `Ebuy_Share_Files_With_Notice`                             | true                          | Link eBuy attachments to the notice (false: admins only)                        |
| `Alert_OrgWide_Email_Id`                                   | (none)                        | Org-wide address alerts come from                                               |
| `Bypass_NXP_GovNoticeTriggerHandler`                       | (none)                        | Emergency trigger switch (set Value to true)                                    |

## Monitoring

- Run `scripts/apex/feed-health.apex` or open the Feed Console daily during the first weeks.
- Open **Inbound Emails** for eBuy messages marked _Needs Review_, _Rejected_ or _Failed_.
- The **Nexus: Operations** dashboard shows feed, push, eBuy inbox, Document Reader and error health together; subscribe to it daily ([reports and dashboards](../design/reports-and-dashboards.md)).
- During the GovWin parallel run, load each week's GovWin export with `scripts/load-govwin-export` and check **Nexus: Adoption and GovWin cut-over** ([data/govwin](../../data/govwin/README.md)).
- Check reports on `NXP_Log__c` (Level = ERROR) and on `NXP_Push_Log__c` (Status = Failed).
- Check platform event subscriber status after deployments.
- To pause everything: `scripts/post-deploy/unschedule-jobs.apex`. To resume: `schedule-jobs.apex`.
