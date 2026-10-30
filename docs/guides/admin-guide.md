# Admin guide

For admins who set up and run Nexus Pursuit Hub. Read [How Nexus works](how-it-works.md) first: it explains what each part does. Installing and releasing are in the [deployment guide](../deployment/deployment-guide.md).

**Contents:** [First-time configuration](#first-time-configuration) · [Adding users](#adding-users) · [E-mail and notifications](#e-mail-and-notifications) · [Scheduled jobs](#scheduled-jobs) · [The Settings tab](#the-settings-tab) · [Your routine](#your-routine) · [Feeds](#feeds) · [Fit rules](#fit-rules) · [Push mapping](#push-mapping) · [Search templates](#search-templates) · [GSA eBuy e-mail](#gsa-ebuy-e-mail) · [Document Reader](#document-reader) · [AI](#ai) · [Settings](#settings-nxp_setting__mdt) · [Monitoring](#monitoring) · [Troubleshooting](#troubleshooting)

## First-time configuration

1. **Assign permission sets:**
    - `NXP_User` to every BD user.
    - `NXP_Power_User` as well, for BD leads.
    - `NXP_Admin` to admins and to the user who schedules jobs.
    - `NXP_Integration` to the REST integration user only (also the context user of the eBuy e-mail service).
2. **SAM.gov API key:** go to Setup → Named Credentials → External Credentials → **NXP SAM.gov** → Principals → _Default_ → Authentication Parameters → add `ApiKey` with the key from your SAM.gov account (System Account key for higher limits). Users who run feeds need the principal, which `NXP_Admin` grants. How to get the key, which kind to use and how to replace an expired one: [SAM.gov API key](../deployment/deployment-guide.md#samgov-api-key).
3. **Forecast endpoint:** edit Named Credential **NXP Agency Forecasts** to your forecast API URL and adjust the `FC_*` feed mappings to its field names.
4. **Company profile:** create one active **Company Profile**, with your NAICS (prefix `5415*` allowed), PSC, set-asides you qualify for, target agencies (names as they appear in agency paths), capability keywords and value range. Then run `scripts/apex/rescore-notices.apex`.
5. **Push mapping:** see [Push mapping](#push-mapping).
6. **Schedule jobs:** run `scripts/post-deploy/schedule-jobs.apex`, as an `NXP_Admin` user.
7. **Activate the Gov Notice record page** if your org overrides it: Lightning App Builder → _Gov Notice Record Page_ → Activation. The Nexus Pursuit Hub app already assigns it.
8. **Notifications and e-mail:** see [E-mail and notifications](#e-mail-and-notifications): turn on _NXP Match Alert_ delivery, check **Deliverability** and, optionally, set an org-wide From address.
9. **Search templates:** run `scripts/apex/seed-search-templates.apex` as an `NXP_Admin` user to create the four starter templates, then adjust them ([Search templates](#search-templates)).
10. **AI (optional):** prompt templates, `AI_Enabled`, the Document Reader and the daily limit ([AI](#ai)).
11. **Contract vehicles:** create the vehicles you hold (tick **We Hold**, set expiry, ceiling and **Inbox Address**).
12. **Check everything on the Settings tab:** its _Health checks_ panel should be all green ✓ ([The Settings tab](#the-settings-tab)).

## Adding users

1. Create the Salesforce user (or use an existing one) and assign the **Nexus Pursuit Hub** app.
2. Assign permission sets: `NXP_User` for everyone in BD; add `NXP_Power_User` for BD leads (sharing searches, templates, auto-push, bulk push); `NXP_Admin` for Nexus admins.
3. Give them access to the assistant (agent access on their profile or permission set group), if you use it.
4. Share the _Nexus Pursuit Hub_ report and dashboard folders with them.
5. Point them to the [user guide](user-guide.md): their first step is a saved search, usually from a template.

When someone leaves, deactivate the user and deal with their saved searches (App Launcher → **Saved Searches**): they keep matching, but alerts to an inactive user go nowhere. Change the owner if a team relied on one, or delete them. Templates they created stay available.

## E-mail and notifications

Nexus sends two kinds of message; who gets what is in [How Nexus works](how-it-works.md#4-alerts-and-notifications).

**E-mail** (Real Time alerts with the Email channel, daily and weekly digests, the admin problems e-mail):

1. **Setup → Deliverability → Access level = All email.** Sandboxes are created with _System email only_, which silently drops every Nexus e-mail. This is the usual reason "no alerts arrive" in a sandbox.
2. Optional: create an **Organization-Wide Email Address** (for example `nexus-alerts@yourcompany.gov`), verify it, and put its Id in the `Alert_OrgWide_Email_Id` setting so alerts come from it instead of the admin who scheduled the jobs.
3. Make sure users' e-mail addresses in Salesforce are correct; alerts go to the user's Salesforce e-mail.
4. Daily and weekly digests are sent at 06:30 in the time zone of the user who ran `schedule-jobs.apex`.

**Salesforce notifications** (bell and mobile; Real Time alerts with the Salesforce channel, followed and watched items, amended pushed notices):

1. **Setup → Custom Notifications → NXP Match Alert → Edit**: tick **Desktop** and **Mobile**.
2. Users need the Salesforce mobile app for phone notifications.
3. Slack or Teams: only through the Salesforce for Slack or Teams integration forwarding Salesforce notifications; Nexus doesn't post to Slack or Teams directly.

**Admin problems e-mail**: every active `NXP_Admin` user gets it at 07:00 when something failed. Change who with `Admin_Digest_Recipients` and when with `Admin_Digest_Mode` ([Monitoring](#monitoring)).

## The Settings tab

**Settings** (in the Nexus Pursuit Hub app, admins only) puts the Nexus settings in one screen, so you rarely need Setup → Custom Metadata Types.

- **Sections** on the left: Alerts and e-mail, SAM.gov and feeds, Searches and inbox, AI, Descriptions and files, GSA eBuy, Fit score rules, Push to Opportunity, and Other settings. Each setting has a plain description and its current value; **Find a setting** searches all sections.
- **Change and save:** changed settings are marked _Changed_ and a bar at the bottom counts them. **Save changes** saves them together (about 30 seconds) and the toast says when they are in effect; **Discard** throws them away. Values are checked first: numbers can't be negative, and active fit rule weights must still add up to 100.
- **After a release:** deploying the packages puts the shipped values back for every setting and fit rule. The release scripts then run `scripts/post-deploy/reapply-settings.apex`, which saves again the last value you gave each setting here, so your changes survive. If you deploy packages by hand, click **Reapply my settings** in the health checks (the _Settings saved here_ check lists what a release put back).
- **Reset by each release:** settings with this badge (`AI_Enabled`, `Org_Environment` and the feed switches, intervals, lookback and page size) are set by `env-config/<env>` on purpose and are not reapplied. Change them here for today, but make the lasting change in `env-config` too.
- **Health checks** (right): e-mail delivery (Deliverability), bell notifications (NXP Match Alert), the SAM.gov key and feed (**Test the key** makes one SAM.gov call), scheduled jobs (**Reschedule all** reschedules the seven Nexus jobs as you), settings saved here (**Reapply my settings** after a release put shipped values back), SAM.gov file downloads (Remote Site Settings), the Company Profile (**Rescore notices** re-scores open notices, for example after you change fit weights) and AI (today's calls against the daily limit). Links open the right Setup page where Setup is needed.
- **Recent changes:** who changed what, from what to what, and whether the save worked. A _Failed_ save shows the reason and nothing is changed. The history is kept in the **Setting Changes** object (`NXP_Setting_Change__c`).

What you need: `NXP_Admin` and the **Customize Application** permission (saving deploys custom metadata, like editing it in Setup). Without Customize Application the save fails with a message saying so.

Still in Setup: the SAM.gov API key (Named Credentials), permission sets and users, push mapping rows (`NXP_Push_Mapping__mdt`), prompt templates (Prompt Builder), Remote Site Settings, Deliverability and Custom Notifications. The health checks link to the last three.

## Scheduled jobs

`scripts/post-deploy/schedule-jobs.apex` (run by `release` and `dev-setup`, or by hand as an `NXP_Admin` user) stops and reschedules all of them; so does **Settings → Health checks → Reschedule all**. They run as the user who scheduled them, so that user must keep `NXP_Admin` and stay active.

| Job (Setup → Scheduled Jobs) | When           | Does                                                                                      |
| ---------------------------- | -------------- | ----------------------------------------------------------------------------------------- |
| NXP Feed Scheduler           | :05 every hour | Runs due feeds; after SAM.gov runs, fetches description text and attachments where needed |
| NXP Notice Analyst :15 / :45 | twice an hour  | AI summaries, amendment summaries, documents waiting to be read (only when AI is on)      |
| NXP Push Retry               | :20 every hour | Retries failed auto-pushes                                                                |
| NXP Daily Digest             | 06:30          | Daily alert e-mails                                                                       |
| NXP Weekly Digest            | 06:30 Monday   | Weekly alert e-mails                                                                      |
| NXP Admin Digest             | 07:00          | Problems e-mail to admins                                                                 |

Matching and Real Time alerts don't need a schedule: they run as notices arrive. To pause everything: `scripts/post-deploy/unschedule-jobs.apex`; to resume, `schedule-jobs.apex`.

## Your routine

**Daily** (a few minutes):

1. Read the **problems e-mail** (07:00). No e-mail means nothing failed.
2. Open **Inbound Emails**: fix and **Reprocess** eBuy messages marked _Needs Review_.
3. Glance at the **Feed Console**: every active feed should be _Healthy_.

**Weekly:**

1. Open **Dashboards → Nexus: Operations** (feeds, pushes, eBuy inbox, Document Reader, errors) and **Nexus: Adoption** (who uses Nexus, pushes by source, GovWin catch rate).
2. Check `NXP AI Usage` (Setup → Custom Settings) against `AI_Max_Calls_Per_Day` and your Einstein credits.
3. Review dismissed matches' reasons (Match Outcomes report) with BD leads to tune templates and the Company Profile.

**Every 90 days** (personal SAM.gov key only): replace the key before it expires ([SAM.gov API key](../deployment/deployment-guide.md#samgov-api-key)).

**After each release:** run the [post-deployment checklist](../deployment/post-deployment-checklist.md).

## Feeds

Feeds are `NXP_Feed_Config__mdt` records. Change them through `env-config/<env>` and deploy, so environments stay reproducible. For a quick change, **Settings → SAM.gov and feeds** turns a feed on or off and changes its interval, lookback and page size (the next release resets them to `env-config`); Setup → Custom Metadata Types has the other fields.

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

`NXP_Fit_Rule__mdt`: active weights should sum to 100. Shipped weights are NAICS 30, Agency 20, Set-Aside 15, Keyword 20 (three keywords give full points) and Value Range 15. PSC and Vehicle ship off. The Vehicle rule gives full points when the notice is on a contract vehicle we hold (**We Hold** ticked on the vehicle, or its code in the profile's _Vehicles We Hold_); to use it, give it a weight and lower another rule so the total stays 100. Change the weights on **Settings → Fit score rules** (the save refuses weights that don't add up to 100), then click **Rescore notices** in the health checks (or run `rescore-notices.apex`).

## Push mapping

1. Find the Opportunity object and required fields in Object Manager.
2. In `NXP_Push_Mapping__mdt` (mapping set `Opportunity_Default`), set `Target_Object__c` on every row to that object. Point `Target_Field__c` at its fields, and set the default stage to a valid value.
3. Recommended: add a text field `NXP_Solicitation_Number__c` to the Opportunity object, and a row from `Solicitation_Number__c` to that field with Sync Behavior _Never_, to turn on duplicate detection.
4. Optional: map `Contract_Vehicle_Code__c` to the Opportunity's contract vehicle field, and `Notice_URL__c` to a link field if it has one. The shipped Description row uses `Push_Details__c` (source, IDs, vehicle, due date and link in one line).
5. Decide sync behaviour per field: Update (due date), Alert Only (value, set-aside), Never (name, stage).
6. Test in a sandbox: push a sample notice, check the record, then amend the notice (or re-run a feed) and check the sync.

## Search templates

Templates are saved searches with **Visibility = Org Template**. Everyone sees them under _Start from a template_ on My Searches with today's match count and how many people use them; **Use template** gives the user a private copy. Templates themselves never alert, match or auto-push (saving one as a template turns those off).

- **Create**: as a Power User or admin, build the search on My Searches, set Visibility to _Org Template_, save. `scripts/apex/seed-search-templates.apex` creates four starters: _High fit, due in 30 days_; _eBuy RFQs (task orders by e-mail)_; _Early market research: sources sought and RFIs_; _Small-business set-asides over $1M_.
- **Edit**: open it on My Searches (it's listed with your searches) and save. Copies already made don't change.
- **Remove**: delete it; copies keep working.

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

When a read document disagrees with the notice (due date, NAICS, set-aside), the notice page shows a warning, the Match Inbox card gets a _document checks_ chip and the push dialog warns. **Mark as checked** records who checked it (`Checks_Reviewed__c`, `Checks_Reviewed_By__c`) and hides it for everyone until the file is read again.

### SAM.gov attachments

The SAM.gov feed stores each notice's file links (`Resource_Links__c`). `NXP_SamFileJob` downloads them into Files on the notice, where the Document Reader reads the PDFs:

- **Which notices:** those that match a saved search or score at least `Files_Min_Fit` (70), while `Files_Auto_Download` is true; and any notice where someone clicks **Get SAM.gov files** on the Documents card.
- **When:** after each SAM.gov feed run and when a search is saved, one file per background job.
- **Limits:** at most `Files_Max_Per_Notice` (10) files per notice; files over `Files_Max_MB` (6) are skipped and stay on SAM.gov. Each file is one SAM.gov call and uses file storage. Amendments download only new files.
- **Status:** the Documents card shows what happened (`Files_Status__c`). An HTTP 429 stops downloading until the next feed run.

Downloads go to `sam.gov` through the **NXP SAM.gov Files** Named Credential (same API key), which redirects to file storage. The **NXP_SAM_File_Storage** Remote Site Setting allows `https://s3.amazonaws.com`. If a notice's status says a file couldn't be downloaded and names another host (an "Unauthorized endpoint" error), add a Remote Site Setting for that host in Setup.

## AI

AI is optional; everything works without it. With it: AI summaries of matched notices, amendment summaries, the Document Reader, eBuy field extraction, better _Draft criteria_ and the assistant. Every call goes through the Einstein Trust Layer; confirm your ATO covers sending notice text and solicitation documents to the model.

1. Create the prompt templates in Prompt Builder from `packages/nxp-agents/reference/genAiPromptTemplates/` ([agent manual build](agent-manual-build.md) lists them) and activate them.
2. Set `AI_Enabled = true`. For the Document Reader also set `Document_Analysis_Enabled = true`.
3. Set `AI_Max_Calls_Per_Day` to fit your Einstein credits (default 500); the **Settings → AI** section shows today's count. When it's used up, summaries and document reading wait for the next day and the problems e-mail says so. Today's count: Setup → Custom Settings → **NXP AI Usage** → Manage.
4. The assistant is built by hand in Agentforce Builder: [agent manual build](agent-manual-build.md).
5. **Find similar** (notice page) drafts its keywords with `NXP_Similar_Keywords` (setting `Similar_Keywords_Template`). Without it, or with AI off, Find similar uses words from the notice title instead.

## Settings (`NXP_Setting__mdt`)

Change settings on the **Settings** tab ([The Settings tab](#the-settings-tab)), or in Setup → Custom Metadata Types → **NXP Setting** → Manage Records → Edit. Every package deployment puts the shipped values back; values saved on the Settings tab are reapplied by the release scripts, but edits made in Setup are not, so prefer the Settings tab. `AI_Enabled` and `Org_Environment` come from `env-config/<env>`: record lasting changes to those there.

| Key                                                        | Default                       | Purpose                                                                                                                                                                                                            |
| ---------------------------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AI_Enabled`                                               | false                         | Turns on AI summaries and the AI criteria draft (needs active prompt templates)                                                                                                                                    |
| `Max_Searches_Per_User` / `Max_RealTime_Searches`          | 50 / 20                       | Bound matching load                                                                                                                                                                                                |
| `Inbox_Days`                                               | 30                            | Match Inbox window                                                                                                                                                                                                 |
| `Push_Mapping_Set`                                         | Opportunity_Default           | Active push mapping set                                                                                                                                                                                            |
| `Push_Max_Attempts`                                        | 3                             | Auto-push retries                                                                                                                                                                                                  |
| `Match_Listeners`                                          | NXP_AutoPushListener          | Classes called on new matches                                                                                                                                                                                      |
| `Http_Max_Attempts`, `Http_Timeout_Ms`                     | 3, 60000                      | Callout retry and timeout                                                                                                                                                                                          |
| `Batch_Max_Pages`, `Queue_Max_Pages`                       | 200, 50                       | Pages per run                                                                                                                                                                                                      |
| `Rest_Max_Records`                                         | 200                           | REST batch limit                                                                                                                                                                                                   |
| `Ebuy_Allowed_Senders`                                     | gsa.gov                       | Addresses or domains the eBuy inbox accepts                                                                                                                                                                        |
| `Ebuy_Default_Vehicle`                                     | GSA-MAS-IT                    | Vehicle for eBuy e-mail that isn't sent to a vehicle's Inbox Address                                                                                                                                               |
| `Ebuy_AI_Template` / `Ebuy_AI_Read_Attachments`            | NXP_Ebuy_RFQ_Extract / false  | AI extraction template; whether it also reads the first PDF                                                                                                                                                        |
| `Document_Analysis_Enabled` / `Document_Analysis_Template` | false / NXP_Document_Analysis | Document Reader on notice PDFs (needs `AI_Enabled`)                                                                                                                                                                |
| `Document_Max_MB` / `Document_Max_Per_Notice`              | 10 / 5                        | Largest PDF sent to the model; files read automatically per notice                                                                                                                                                 |
| `Ebuy_Share_Files_With_Notice`                             | true                          | Link eBuy attachments to the notice (false: admins only)                                                                                                                                                           |
| `Alert_OrgWide_Email_Id`                                   | (none)                        | Org-wide address alerts come from                                                                                                                                                                                  |
| `Description_Min_Fit`                                      | 50                            | Fetch SAM.gov description text automatically only for matched notices and this fit or higher (one API call each; 0 = all)                                                                                          |
| `Initial_Match_Max_Summaries`                              | 25                            | When a search is saved, AI summaries requested for at most this many existing matches                                                                                                                              |
| `AI_Max_Calls_Per_Day`                                     | 500                           | Most AI prompt calls a day across summaries, change summaries, documents, eBuy and criteria drafts; then AI work waits for the next day (0 = no limit). Today's count is in Setup > Custom Settings > NXP AI Usage |
| `Admin_Digest_Mode` / `Admin_Digest_Recipients`            | Problems / (blank)            | Daily problems e-mail at 07:00: Problems (only when something failed), Daily (always) or Off; blank recipients = active NXP_Admin users                                                                            |
| `Files_Auto_Download` / `Files_Min_Fit`                    | true / 70                     | Download SAM.gov attachments automatically for matched notices and this fit or higher                                                                                                                              |
| `Files_Max_Per_Notice` / `Files_Max_MB`                    | 10 / 6                        | Most files per notice; largest file in MB (keep at 8 or less)                                                                                                                                                      |
| `Similar_Keywords_Template`                                | NXP_Similar_Keywords          | Prompt template Find similar uses to suggest keywords (needs `AI_Enabled`; counts toward the daily limit)                                                                                                          |
| `Ebuy_Silence_Days`                                        | 3                             | The problems e-mail warns when no eBuy e-mail has arrived for this many days (0 = off)                                                                                                                             |
| `Bypass_NXP_GovNoticeTriggerHandler`                       | (none)                        | Emergency trigger switch (set Value to true)                                                                                                                                                                       |

## Monitoring

- **Daily problems e-mail** (`NXP_AdminDigestJob`, 07:00, scheduled by `schedule-jobs.apex`): eBuy e-mails rejected, failed or still waiting for review; no eBuy e-mail for `Ebuy_Silence_Days`; failed feed runs and active feeds that stopped running; pushes failed after retries; documents not read; the AI limit used up. On a quiet day nothing is sent unless `Admin_Digest_Mode = Daily`.
- Run `scripts/apex/feed-health.apex` or open the Feed Console daily during the first weeks.
- Open **Inbound Emails** for eBuy messages marked _Needs Review_, _Rejected_ or _Failed_.
- The **Nexus: Operations** dashboard shows feed, push, eBuy inbox, Document Reader and error health together; subscribe to it daily ([reports and dashboards](../design/reports-and-dashboards.md)).
- During the GovWin parallel run, load each week's GovWin export with `scripts/load-govwin-export` and check **Nexus: Adoption and GovWin cut-over** ([data/govwin](../../data/govwin/README.md)).
- Check reports on `NXP_Log__c` (Level = ERROR) and on `NXP_Push_Log__c` (Status = Failed).
- Check platform event subscriber status after deployments.
- To pause everything: `scripts/post-deploy/unschedule-jobs.apex`. To resume: `schedule-jobs.apex`.

## Troubleshooting

| Symptom                                                    | Check                                                                                                                                                          |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nobody gets alert e-mails                                  | Setup → Deliverability = _All email_; the search's alert setting and channels; the user's e-mail address. Digests go at 06:30 only when there are new matches. |
| No bell notifications                                      | _NXP Match Alert_ delivery is on; the search has the _Salesforce_ channel (Real Time); for follows, the user followed the record                               |
| A search shows matches in the preview but not in the inbox | The search was saved before this release: open it and **Save search** again to match existing notices                                                          |
| SAM.gov feed _Failed_ with 401/403                         | API key wrong or expired, or the parameter isn't named exactly `ApiKey`                                                                                        |
| SAM.gov feed _Failed_ with 429                             | The key's daily limit is used up; use a System Account key; untick **Active** on the feed and use **Run now** until then                                       |
| **Run now** is greyed out                                  | The feed is paused: tick **Active** on its NXP Feed Config record                                                                                              |
| Description shows only **Load description**                | Normal for unmatched, low-fit notices. If it fails, see **NXP Logs** for _Description fetch failed_                                                            |
| SAM.gov files don't arrive                                 | The Documents card status. "Unauthorized endpoint" names a host: add a Remote Site Setting for it                                                              |
| No AI summaries                                            | `AI_Enabled`, active prompt templates, the notice matched a search, Notice Analyst jobs scheduled, daily AI limit not reached                                  |
| eBuy e-mail _Rejected_                                     | Sender not in `Ebuy_Allowed_Senders` (forwarding changes the sender: use redirect)                                                                             |
| Push _Failed_                                              | The Push Log error: usually a required Opportunity field missing from the push mapping                                                                         |
| Settings tab: _Failed_ save mentioning permissions         | The admin needs **Customize Application** (profile or a permission set)                                                                                        |
| Settings tab: a value went back after a release            | **Reapply my settings** (health checks). If it's marked _Reset by each release_, change it in `env-config/<env>` too                                           |
| Find similar has keywords from the title only              | AI is off, the daily AI limit is used up, or the `NXP_Similar_Keywords` prompt template isn't active                                                           |
| Settings edit page shows only Label and Name               | The NXP custom metadata page layouts aren't deployed: deploy `packages/nxp-core`                                                                               |
