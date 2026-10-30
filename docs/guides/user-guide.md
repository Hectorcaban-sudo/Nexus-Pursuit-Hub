# User guide

Nexus Pursuit Hub finds government opportunities for you and sends the good ones to Opportunity. Open the **Nexus Pursuit Hub** app from the App Launcher.

## 1. Build a search

1. Go to **My Searches** and click **+**, or pick one under **Start from a template** and click **Use template**. A template makes a private copy you can change; it shows how many notices match it now and how many people use it.
2. Either describe what you want in **Describe it** and click **Draft criteria**, or fill in the criteria yourself:
    - Keywords: `cyber AND ("zero trust" OR ZTA)`; `icam*` for word beginnings; `NOT training` to exclude.
    - Buyer, NAICS (`5415*` covers a family), PSC, set-aside, notice type.
    - Value, _Due within_ days, _Minimum fit score_.
3. Watch **Live preview**: today's match count, matches per week over the last 13 weeks, and the top 20. Too many? Add a filter. None? Remove one.
4. Choose alerts: **Daily** digest (recommended), **Weekly**, **Real Time** (for narrow, urgent searches) or **None**.
5. Click **Save search**. Open notices that match it now appear in your Match Inbox within a minute, without alert e-mails. From then on, new and changed notices are matched as they arrive and alerted as you chose. Keywords are checked against the title and the description. SAM.gov sends descriptions separately, so a notice whose keywords appear only in its description can arrive in your inbox up to an hour after the notice itself.

## 2. Work the Match Inbox

Every new match lands in **Match Inbox**, best fit first. Each card shows:

- The fit score, with up to three reasons: the two rules that added the most points (green) and the one that cost the most (amber for some points, red for none).
- The notice type and set-aside, plus what changed if it was amended. A red **document checks** chip means a read solicitation document disagrees with the notice (see below).
- The buyer, value and how many days are left.
- An AI summary when one is available.
- Why the notice matched.

| Button                  | Does                                                                                                               |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **Push to Opportunity** | Shows exactly what will be sent and whether an Opportunity already exists for it, then creates or links the record |
| **Watch**               | Follows the notice; you're alerted when it changes                                                                 |
| **Dismiss**             | Removes it from the inbox; your reason helps tune searches                                                         |

To act on several at once, tick the cards (or **Select all**) and use **Watch**, **Dismiss** (one reason for all) or **Push** above the list. Push needs the Power User permission.

## 3. Read a notice

Open a notice title to see:

- Days to respond and the fit score, with the top reasons under the header (**All rules** jumps to the full breakdown).
- A red box when a read document disagrees with the notice (due date, NAICS or set-aside): what the notice says next to what the file says, with **Open document** and **Mark as checked**. Marking it hides it for everyone; if the file is read again and still disagrees, it comes back. The days-to-respond tile says _Check the date below_ when the due dates differ, and the push dialog warns too.
- The AI summary (check it against the solicitation), the full description and contacts. SAM.gov sends only a link to the description; it is fetched automatically for notices that match a search or score high. For others, click **Load description**. Summaries are written for notices that match a saved search.
- Version history: every amendment and what changed.
- Push history, plus **Open on SAM.gov** and **Follow**.
- **Documents**: the notice's files. Add the solicitation documents with **Add documents** (eBuy RFQs bring theirs). Each PDF is read by AI, which lists requirements, deliverables, evaluation factors, submission rules (due date, page limit), key dates, clearance and risks, and flags where the document disagrees with the notice (for example a different due date). It's a head start for the capture team, not the bid decision: check it against the file. **Analyze** reads a file now; **Read again** after a new version. Word and Excel files are listed but not read. SAM.gov attachments are added automatically for notices that match your searches or score high; for any other notice, click **Get SAM.gov files**. Files over 6 MB stay on SAM.gov (**Open on SAM.gov**).

## 4. Look ahead: forecasts, recompetes and competitors

- **Forecasts** tab: planned buys before a notice exists, grouped by when the agency expects to solicit (next 90 days, 3–6 months, 6–12 months, released). _Fits our company profile_ is on by default. Click **Watch** on a forecast to get an alert when it is released as a notice; released forecasts link to their notice.
- **Recompetes** tab: contract awards in your market on a timeline, with today marked. Orange bars end within 6 months. The **Follow-on** column shows the notice that names the award as its predecessor, or a likely notice or forecast from the same agency with the same NAICS. Click an award's title for details; **Watch this recompete** alerts you when a likely follow-on is posted.
- **Vendor profile**: click an incumbent's name (or open a Gov Vendor). You see their awards in Nexus, where they overlap with your company profile (NAICS, agencies, set-aside eligibility) and open notices where they are the likely incumbent. **Watch this vendor** alerts you when they win a new award. Admins can **Refresh from SAM.gov**.

- **Agency profile**: open a Gov Agency (or click an agency link). _What's coming_ lists its open notices, forecasts and awards ending, in date order; you also see who holds its awards, where it spends by NAICS, its contracting contacts, and whether any of your saved searches covers it. A department includes its sub-agencies. **Watch this agency** alerts you on every new notice it posts.

- **Vehicle Portfolio** tab: the contract vehicles you hold, each with its open notices (soonest due first), expiry date (amber within 12 months) and whether a task-order inbox address is set up. _Notices you can't bid alone_ lists open notices that require a vehicle you don't hold, so you can find a teaming partner; **Follow** a notice there to hear when it changes. Admins can record **We hold it** or **We no longer hold this**, which re-scores that vehicle's open notices. A vehicle counts as held when **We Hold** is ticked on it or its code is listed in the Company Profile's _Vehicles We Hold_.
- **GSA eBuy RFQs** arrive by e-mail and show up as _Task Order_ notices with IDs like `EBUY:RFQ1234567`, linked to the vehicle and to eBuy (you still quote in eBuy). The RFQ's attachments are on the notice. A line starting _AI summary (check against the RFQ)_ in the description was written by AI.

Watches show in the bell icon as **NXP Match Alert** notifications, like followed notices.

## 5. Dashboards

Open **Dashboards → Nexus: Market and activity** for new notices by source, what happened to your matches, pushes to Opportunity and the high-fit notices due soon that nobody has pushed. Click a chart to open its report. It shows what you can see, so your own searches and matches.

## 6. Ask the assistant

Open the Agentforce panel and ask, for example:

- "Alert me daily on Army cloud migration, 541519, 8(a), over $5M"
- "Why is the fit score on this notice 72?"
- "What changed in the latest amendment?"
- "What does the statement of work require?"
- "Which VA recompetes over $10M expire in the next 18 months?"
- "Push this to Opportunity"

The assistant always shows a preview and waits for your **yes** before saving a search or pushing a notice.

## Power Users

- Share a search with your team (**Visibility: Team**, plus the public group name) or as an **Org Template**.
- Turn on **Auto-push** for a search: _Fit Threshold_ (for example 70) or _All Matches_.
- Select several cards and click **Push**.
- Save a search as an **Org Template** to list it under _Start from a template_ for everyone. Templates never alert, match or auto-push themselves; people use copies.

## FAQ

- **Why don't I see a notice?** Searches only include _Active_ notices by default, and _Due within_ hides notices with no due date. Also check the minimum fit.
- **Does a push overwrite the Opportunity?** No. After a push, only the fields your admin set to update (usually the due date) change. Capture fields such as stage and pWin are never touched.
- **Is the AI summary reliable?** It's a draft; always confirm against the solicitation documents.
