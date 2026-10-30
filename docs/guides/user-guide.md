# User guide

Nexus Pursuit Hub finds government opportunities for you, tells you about the ones that fit, helps you read them, and sends the ones you pursue to **Opportunity**. Open the **Nexus Pursuit Hub** app from the App Launcher. For what happens behind the screens, see [How Nexus works](how-it-works.md).

**Contents:** [Your first day](#your-first-day) · [1. Searches](#1-build-a-search) · [2. Match Inbox](#2-work-the-match-inbox) · [3. Notices](#3-read-a-notice) · [4. Alerts](#4-alerts-what-you-get-and-how) · [5. Follow and watch](#5-follow-and-watch) · [6. Look ahead](#6-look-ahead-forecasts-recompetes-agencies-vendors-vehicles) · [7. Push](#7-push-to-opportunity) · [8. Dashboards](#8-dashboards) · [9. Assistant](#9-ask-the-assistant) · [Power Users](#power-users) · [Daily routine](#a-good-daily-routine) · [FAQ](#faq) · [Quick reference](#quick-reference)

## Your first day

1. Open **My Searches** and start from a template (**Start from a template → Use template**) or build your own search. Save it.
2. Within a minute, open notices that match appear in **Match Inbox**.
3. Pick your alert frequency: most people use **Daily** (one e-mail at 06:30).
4. Turn on the bell: Salesforce notifications from Nexus are called **NXP Match Alert**. On your phone, install the Salesforce mobile app to get them there too.

## 1. Build a search

1. Go to **My Searches**. Either:
    - pick a template under **Start from a template** and click **Use template**. It shows how many open notices match it now and how many people use it, and makes a private copy you can change; or
    - click **+** for a blank search.
2. Describe what you want in **Describe it** and click **Draft criteria**, or fill in the criteria yourself. Always check what the draft filled in.
    - **Keywords**: `cyber AND ("zero trust" OR ZTA)`; `recruit*` matches recruiting, recruiter, Recruiting Command; `NOT training` excludes. Keywords are checked in the title and the description (untick one under _Search in_ to narrow).
    - **Buyer**: part of the agency or office name, for example `Army` or `Customs and Border Protection`. Sub-agencies are included.
    - **NAICS** (`5415*` covers a family), **PSC**, **set-aside**, **notice type**.
    - **Value**, **Due within** days, **Minimum fit score**.
3. Watch **Live preview**: today's match count, matches per week over the last 13 weeks, and the top 20. Too many? Add a filter. None? Remove one.
4. Choose **Alerts** (see [Alerts](#4-alerts-what-you-get-and-how)): **Daily** (recommended), **Weekly**, **Real Time** (narrow, urgent searches) or **None**. Tick the channels for Real Time: **Email**, **Salesforce** (bell).
5. Leave **Alert on changes** ticked to be told when a matched notice is amended.
6. Click **Save search**. Open notices that match appear in your Match Inbox within a minute, without alert e-mails. From then on, new and changed notices are matched as they arrive and alerted as you chose.

**Example**: "Alert me when a CRM solution is needed for the Army recruiting office" works well as keywords `(CRM OR "customer relationship management" OR Salesforce) AND recruit*`, buyer `Army`, notice types Sources Sought, RFI, Pre-solicitation and Solicitation, Real Time alerts. Leave NAICS empty: CRM work is posted under several codes.

**Descriptions**: SAM.gov sends the description separately. When only the description can decide a match, Nexus fetches it and checks again, so that notice can arrive up to an hour after it was posted.

To change a search, click it in the list on the left, edit, and **Save search**. To stop it, untick **Active**, or delete it with the bin icon (its matches go too).

## 2. Work the Match Inbox

Every match lands in **Match Inbox**, best fit first (or sort by due date or newest). The left column lists your searches with their new counts; click one to see only its matches.

Each card shows:

- **Fit score** with up to three reasons: the two rules that added the most points (green) and the one that cost the most (amber for some points, red for none).
- **Notice type** and **set-aside**, and what changed if it was amended (_Changed: Due date_).
- A red **document checks** chip when a read solicitation document disagrees with the notice (see [Document checks](#document-checks)).
- The **buyer**, **value** and **days left** (bold when 7 days or fewer).
- The **AI summary**, when one is ready.
- **Why it matched**: the search and the words or codes it matched on.

| Button                  | Does                                                                                                  |
| ----------------------- | ----------------------------------------------------------------------------------------------------- |
| **Push to Opportunity** | Shows what will be sent and whether an Opportunity already exists, then creates or links the record   |
| **Watch**               | Follows the notice (bell alerts when it changes) and keeps the card; see it with **Include watching** |
| **Dismiss**             | Removes the card; your reason ("Not a fit", "Already pursuing"…) helps tune searches                  |

**Several at once**: tick cards (or **Select all**) and use **Watch**, **Dismiss** (one reason for all) or **Push** in the bar above the list. Push of several cards needs the Power User permission.

Cards stay in the inbox for 30 days, or until you dismiss or push them.

## 3. Read a notice

Click a notice title. The page shows:

- **Header**: days to respond, fit score with its top reasons (**All rules** jumps to the full breakdown), due date, value, set-aside, NAICS/PSC and sources. Buttons: **Push to Opportunity** (or **Open Opportunity record** once pushed), **Follow**, **Open on SAM.gov**.
- **Summary**: the AI summary (a draft: check it against the solicitation). It's written for notices that match a saved search, within about 30 minutes.
- **Full description**: click to expand. If it only shows a **Load description** button, SAM.gov sent a link; click it to fetch the text (descriptions of matched and high-fit notices are fetched automatically).
- **Fit breakdown**, **Version history** (every amendment and what changed), **Contacts** and **Push history**.
- **Documents**: the notice's files.

### Documents

- **SAM.gov files** are downloaded automatically for notices that match a search or score 70+. For any other notice, click **Get SAM.gov files**; they arrive one by one over a few minutes (click refresh). Files over 6 MB stay on SAM.gov.
- **Add documents** uploads your own copies. eBuy RFQs bring their attachments.
- When AI reading is on, each PDF is read and the card lists requirements, deliverables, evaluation factors, submission rules (due date, page limit), key dates, clearance and risks. **Analyze** reads a file now; **Read again** after a new version. Word and Excel files are listed but not read. It's a head start, not the bid decision: check against the file.

### Document checks

When a document disagrees with the notice (due date, NAICS or set-aside), a red box at the top of the page shows what the notice says next to what the file says.

1. Click **Open document** and check the file.
2. Tell your team which is right, then click **Mark as checked**. The warning disappears for everyone (it comes back if the file is read again and still disagrees).

Nexus never changes the notice's own fields because of a document. The days-to-respond tile says _Check the date below_ while a due-date check is open, and the push dialog warns too.

## 4. Alerts: what you get and how

Nexus tells you things by **e-mail** and by **Salesforce notification** (the bell at the top of Salesforce, and push notifications in the Salesforce mobile app).

| Your search's alert setting | You get                                                                                                              |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **Real Time**               | Within minutes of a new match: an **e-mail** if _Email_ is ticked, a **bell** notification if _Salesforce_ is ticked |
| **Daily**                   | One **e-mail** at 06:30 with all your daily searches' new matches                                                    |
| **Weekly**                  | One **e-mail** on Monday at 06:30                                                                                    |
| **None**                    | Nothing; check the Match Inbox                                                                                       |

Also:

- **Followed and watched items** (next section) notify you by **bell only**, never e-mail.
- If you own an Opportunity that came from a pushed notice, you get a **bell** notification when the notice is amended.
- Real Time searches are limited (20 per person) to keep alerts useful. Use Daily for broad searches.

No e-mail at all? Ask your admin: e-mail may be turned off for the org (common in test sandboxes).

## 5. Follow and watch

Follow a record to be told when it changes, whether or not it matches your searches. Alerts come to the **bell** only.

| Follow or watch | Where                                                     | You're told when                                   |
| --------------- | --------------------------------------------------------- | -------------------------------------------------- |
| A **notice**    | **Follow** on the notice page; **Watch** on an inbox card | It changes: amendment, new due date, cancellation… |
| An **agency**   | **Watch this agency** on the agency profile               | It or any of its sub-agencies posts a new notice   |
| A **vendor**    | **Watch this vendor** on the vendor profile               | It wins a new award                                |
| A **forecast**  | **Watch** on the Forecasts tab                            | It's released as a notice                          |
| An **award**    | **Watch this recompete** on the Recompetes tab            | A likely follow-on is posted                       |

To stop, click the button again: on a notice it reads **Unfollow**; on profiles, forecasts and recompetes it reads **Watching** while you watch.

## 6. Look ahead: forecasts, recompetes, agencies, vendors, vehicles

- **Forecasts** tab: planned buys before a notice exists, grouped by when the agency expects to solicit (next 90 days, 3–6 months, 6–12 months, released). _Fits our company profile_ is on by default. Released forecasts link to their notice.
- **Recompetes** tab: contract awards in your market on a timeline, with today marked. Orange bars end within 6 months. The **Follow-on** column shows the notice that names the award as its predecessor, or a likely notice or forecast from the same agency with the same NAICS.
- **Vendor profile**: click an incumbent's name or open a Gov Vendor: their awards, where they overlap with your company profile, and open notices where they're the likely incumbent. Admins can **Refresh from SAM.gov**.
- **Agency profile**: open a Gov Agency: _What's coming_ (open notices, forecasts and awards ending, in date order), who holds its awards, spend by NAICS, contracting contacts and whether your searches cover it. **Alert me on new notices here** starts a search for it.
- **Vehicle Portfolio** tab: the contract vehicles you hold with their open notices (soonest due first), expiry (amber within 12 months) and whether a task-order inbox is set up. _Notices you can't bid alone_ lists open notices on vehicles you don't hold, for teaming. Admins record **We hold it** or **We no longer hold this**.
- **GSA eBuy RFQs** arrive by e-mail and appear as _Task Order_ notices with IDs like `EBUY:RFQ1234567`, with their attachments. You still quote in eBuy. A line starting _AI summary (check against the RFQ)_ was written by AI.

## 7. Push to Opportunity

1. Click **Push to Opportunity** on a card or notice.
2. Check the dialog: the values that will be sent, whether a matching Opportunity already exists (it will be linked, not duplicated), any document-check warning, and whether to link the notice's documents to the record.
3. Click **Push opportunity**. The notice leaves your inbox and shows **Open Opportunity record**.

After a push, the due date (and any other field your admin chose) follows amendments; capture fields such as stage and pWin are never touched. Work the pursuit in Opportunity.

## 8. Dashboards

**Dashboards → Nexus: Market and activity**: new notices by source and week, what happened to your matches, pushes to Opportunity, high-fit notices due soon that nobody has pushed, and eBuy RFQs by vehicle. Click a chart to open its report. It shows what you can see. **Reports** has the underlying reports.

## 9. Ask the assistant

Open the Agentforce panel and ask, for example:

- "Alert me daily on Army cloud migration, 541519, 8(a), over $5M"
- "Why is the fit score on this notice 72?" (open the notice first)
- "What changed in the latest amendment?"
- "What does the statement of work require?"
- "Who is the incumbent?"
- "Which VA recompetes over $10M expire in the next 18 months?"
- "Push this to Opportunity"

It answers only from Nexus data, always shows a preview, and waits for your **yes** before saving a search or pushing a notice. It can't delete or share searches, change an Opportunity, or write proposal text.

## Power Users

BD leads with the Power User permission can also:

- Share a search with a team (**Visibility: Team**, plus the public group name).
- Save a search as an **Org Template** so it appears under _Start from a template_ for everyone. Templates never alert, match or auto-push themselves; people use copies.
- Turn on **Auto-push** for a search: _Fit Threshold_ (for example 70) or _All Matches_. Matches are pushed to Opportunity without a click; failures are retried every hour.
- **Push** several selected inbox cards at once.

## A good daily routine

1. Read the morning digest e-mail (06:30) or open **Match Inbox**.
2. For each card: **Dismiss** what doesn't fit (with a reason), **Watch** what you're unsure about, **Push** what you'll pursue.
3. Check the bell for changes on what you follow, and any red document checks on notices you pushed.
4. Once a week: look at **Forecasts** and **Recompetes** for what's coming, and tune searches that are too noisy or too quiet.

## FAQ

- **Why don't I see a notice?** Searches include only _Active_ notices by default; _Due within_ hides notices with no due date; check the minimum fit. Notices that match only on description words can take up to an hour.
- **I saved a search but got no e-mail for what's already in my inbox.** That's on purpose: notices already open when you save appear in the inbox quietly. New ones alert as you chose.
- **I get no e-mails at all.** Check your search's alert setting and channels, then ask your admin whether org e-mail is turned on.
- **Does a push overwrite the Opportunity?** No. Only the fields your admin set to update (usually the due date) change. Stage, pWin and other capture fields are never touched.
- **Is the AI summary reliable?** It's a draft. Always confirm against the solicitation documents.
- **Why is there no summary?** Summaries are written only for notices that match a saved search, when AI is turned on, and there's a daily AI limit.
- **Where are the SAM.gov attachments?** On the Documents card. If they're not there, click **Get SAM.gov files**. Files over 6 MB open from SAM.gov.

## Quick reference

| I want to…                                  | Do this                                                    |
| ------------------------------------------- | ---------------------------------------------------------- |
| Be alerted about a kind of opportunity      | My Searches → template or **+** → Save search              |
| Be alerted about one notice                 | **Follow** on the notice, or **Watch** on its card         |
| Hear about everything an agency posts       | Agency profile → **Watch this agency**                     |
| Know when a forecast becomes a solicitation | Forecasts → **Watch**                                      |
| Know when a contract is being recompeted    | Recompetes → **Watch this recompete**                      |
| Get rid of noise                            | **Dismiss** with a reason, then tighten the search         |
| Read the description or files               | Notice page → **Load description** / **Get SAM.gov files** |
| Send a notice to capture                    | **Push to Opportunity**                                    |
| Change how often I'm told                   | My Searches → open the search → Alerts → Save              |
