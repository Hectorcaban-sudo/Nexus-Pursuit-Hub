# User guide

Nexus Pursuit Hub finds government opportunities for you and sends the good ones to TechnoMile. Open the **Nexus Pursuit Hub** app from the App Launcher.

## 1. Build a search

1. Go to **My Searches** and click **+**.
2. Either describe what you want in **Describe it** and click **Draft criteria**, or fill in the criteria yourself:
    - Keywords: `cyber AND ("zero trust" OR ZTA)`; `icam*` for word beginnings; `NOT training` to exclude.
    - Buyer, NAICS (`5415*` covers a family), PSC, set-aside, notice type.
    - Value, _Due within_ days, _Minimum fit score_.
3. Watch **Live preview**: today's match count, matches per week over the last 13 weeks, and the top 20. Too many? Add a filter. None? Remove one.
4. Choose alerts: **Daily** digest (recommended), **Weekly**, **Real Time** (for narrow, urgent searches) or **None**.
5. Click **Save search**.

## 2. Work the Match Inbox

Every new match lands in **Match Inbox**, best fit first. Each card shows:

- The fit score.
- The notice type and set-aside, plus what changed if it was amended.
- The buyer, value and how many days are left.
- An AI summary when one is available.
- Why the notice matched.

| Button                 | Does                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------- |
| **Push to TechnoMile** | Shows exactly what will be sent and whether TechnoMile already has it, then creates or links the record |
| **Watch**              | Follows the notice; you're alerted when it changes                                                      |
| **Dismiss**            | Removes it from the inbox; your reason helps tune searches                                              |

## 3. Read a notice

Open a notice title to see:

- Days to respond and the fit score, with _why it scores_ rule by rule.
- The AI summary (check it against the solicitation), the full description and contacts.
- Version history: every amendment and what changed.
- Push history, plus **Open on SAM.gov** and **Follow**.

## 4. Look ahead: forecasts, recompetes and competitors

- **Forecasts** tab: planned buys before a notice exists, grouped by when the agency expects to solicit (next 90 days, 3–6 months, 6–12 months, released). _Fits our company profile_ is on by default. Click **Watch** on a forecast to get an alert when it is released as a notice; released forecasts link to their notice.
- **Recompetes** tab: contract awards in your market on a timeline, with today marked. Orange bars end within 6 months. The **Follow-on** column shows the notice that names the award as its predecessor, or a likely notice or forecast from the same agency with the same NAICS. Click an award's title for details; **Watch this recompete** alerts you when a likely follow-on is posted.
- **Vendor profile**: click an incumbent's name (or open a Gov Vendor). You see their awards in Nexus, where they overlap with your company profile (NAICS, agencies, set-aside eligibility) and open notices where they are the likely incumbent. **Watch this vendor** alerts you when they win a new award. Admins can **Refresh from SAM.gov**.

- **Agency profile**: open a Gov Agency (or click an agency link). _What's coming_ lists its open notices, forecasts and awards ending, in date order; you also see who holds its awards, where it spends by NAICS, its contracting contacts, and whether any of your saved searches covers it. A department includes its sub-agencies. **Watch this agency** alerts you on every new notice it posts.

- **Vehicle Portfolio** tab: the contract vehicles you hold, each with its open notices (soonest due first), expiry date (amber within 12 months) and whether a task-order inbox address is set up. _Notices you can't bid alone_ lists open notices that require a vehicle you don't hold, so you can find a teaming partner; **Follow** a notice there to hear when it changes. Admins can record **We hold it** or **We no longer hold this**, which re-scores that vehicle's open notices. A vehicle counts as held when **We Hold** is ticked on it or its code is listed in the Company Profile's _Vehicles We Hold_.

Watches show in the bell icon as **NXP Match Alert** notifications, like followed notices.

## 5. Ask the assistant

Open the Agentforce panel and ask, for example:

- "Alert me daily on Army cloud migration, 541519, 8(a), over $5M"
- "Why is the fit score on this notice 72?"
- "What changed in the latest amendment?"
- "Which VA recompetes over $10M expire in the next 18 months?"
- "Push this to TechnoMile"

The assistant always shows a preview and waits for your **yes** before saving a search or pushing a notice.

## Power Users

- Share a search with your team (**Visibility: Team**, plus the public group name) or as an **Org Template**.
- Turn on **Auto-push** for a search: _Fit Threshold_ (for example 70) or _All Matches_.
- Select several cards and click **Push selected**.

## FAQ

- **Why don't I see a notice?** Searches only include _Active_ notices by default, and _Due within_ hides notices with no due date. Also check the minimum fit.
- **Does a push overwrite TechnoMile?** No. After a push, only the fields your admin set to update (usually the due date) change. Capture fields such as stage and pWin are never touched.
- **Is the AI summary reliable?** It's a draft; always confirm against the solicitation documents.
