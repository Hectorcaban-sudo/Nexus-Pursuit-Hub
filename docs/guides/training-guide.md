# Training guide

A ready-to-run plan for training BD users and admins on Nexus Pursuit Hub, with talking points, live demos and hands-on exercises. Run it in a sandbox with sample data, so people can push and dismiss freely.

**Contents:** [Before the session](#before-the-session) · [Session 1: BD users](#session-1-bd-users-90-minutes) · [Session 2: Power Users](#session-2-power-users-30-minutes) · [Session 3: admins](#session-3-admins-2-hours) · [Handout](#handout-one-page-summary) · [After training](#after-training)

## Before the session

**In the training sandbox** (an admin, the day before):

1. Deploy the current release and load sample data: `.\scripts\load-sample-data.ps1 -Org <alias> -Reset` (creates sample notices, vehicles, forecasts, awards, an eBuy e-mail, searches and the four search templates).
2. Setup → Deliverability → **All email**, so trainees receive alert e-mails.
3. Setup → Custom Notifications → **NXP Match Alert** → Desktop and Mobile on.
4. Create a training user per trainee (or reuse sandbox users) with the **Nexus Pursuit Hub** app and `NXP_User`; add `NXP_Power_User` for leads and `NXP_Admin` for admins. Check each user's e-mail address.
5. Run `scripts/apex/smoke-test.apex`; everything should be PASS or WARN.
6. If SAM.gov is connected in the sandbox, run the SAM.gov feed once (**Feed Console → Run now**) so there are real notices too.

**For trainees:** ask them to bring two or three real examples of opportunities they'd want to hear about ("CRM work for Army recruiting", "DHS zero trust under $10M").

**Hand out:** the [user guide](user-guide.md) (or its _Quick reference_), and the [handout](#handout-one-page-summary) below.

## Session 1: BD users (90 minutes)

### Part 1 — How it fits together (10 min)

Draw or show the flow from [How Nexus works](how-it-works.md#the-big-picture):

- Notices come in by themselves (SAM.gov every hour, eBuy by e-mail).
- **You** describe what you want once, as saved searches.
- Nexus scores every notice for fit, matches it to your searches and tells you.
- You decide: dismiss, watch, or push to Opportunity. Capture happens in Opportunity, not in Nexus.

Key message: _"Your job is to keep your searches good and work your inbox daily. Nexus does the watching."_

### Part 2 — Build your first search (20 min)

**Demo** (My Searches):

1. **Start from a template**: point out the "N now" count and "Used by". Click **Use template** on _High fit, due in 30 days_, save it.
2. **Describe it**: type a trainee's example, click **Draft criteria**, and show that the draft must be checked (leftover words become required keywords). Fix the keywords live, for example `(CRM OR "customer relationship management") AND recruit*`, buyer `Army`.
3. Show the **Live preview** changing as you add and remove filters.
4. Explain **Alerts**: Daily (one 06:30 e-mail), Weekly, Real Time (e-mail and/or bell within minutes), None.

**Exercise 1** (each trainee):

| Step                                                                  | Expected result                                                                        |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Copy a template and save it as your own                               | It appears in _My searches_ on the left                                                |
| Build a search for one of your own examples, Daily alerts             | Preview shows a count; after saving, matches appear in the Match Inbox within a minute |
| Set one narrow search to **Real Time**, Email and Salesforce channels | Saved; it alerts as new matches arrive                                                 |

### Part 3 — Work the Match Inbox (20 min)

**Demo** (Match Inbox):

1. Cards are sorted best fit first. Read the **fit reasons** chips (green = full points, amber = partial, red = none).
2. **Why it matched** line, the **days left**, the AI summary when there is one.
3. **Watch** (follow + keep), **Dismiss** with a reason, **Push to Opportunity** (shows the preview, duplicate check, then the Opportunity).
4. Select several cards: **Select all → Dismiss** with one reason.
5. **Include watching** shows watched cards again.

**Exercise 2:**

| Step                                            | Expected result                                           |
| ----------------------------------------------- | --------------------------------------------------------- |
| Dismiss two cards with a reason                 | They leave the inbox                                      |
| Watch one card                                  | It disappears until _Include watching_ is on              |
| Push one sample notice to Opportunity           | The dialog shows the values; the Opportunity record opens |
| Select three cards and **Watch** them in one go | A _Watching_ message for 3 notices                        |

### Part 4 — Read a notice (15 min)

**Demo** (open a notice):

1. Header: days to respond, fit reasons, **All rules**.
2. **Load description** on an unmatched notice; matched ones have it already.
3. **Documents**: **Get SAM.gov files**, then **Analyze** a PDF (if AI is on). Walk through requirements, evaluation factors, key dates and risks.
4. A **document check** (needs the Document Reader on): attach a PDF whose due date differs from the notice's and click **Analyze**; the red box appears. Then **Open document** and **Mark as checked**. Without AI in the sandbox, show the screenshot from the mockups instead.
5. **Version history**: what an amendment changed.

### Part 5 — Alerts, follow and watch (15 min)

Show the table from [user guide › Alerts](user-guide.md#4-alerts-what-you-get-and-how) and [Follow and watch](user-guide.md#5-follow-and-watch). Make these points:

- **Searches** tell you about _new opportunities_; **follow/watch** tells you about _changes to things you already know_.
- **E-mail**: Real Time (with the Email channel), Daily and Weekly digests.
- **Bell** (and the Salesforce mobile app): Real Time with the Salesforce channel, everything you follow or watch, and amendments to notices you pushed.
- Watch an **agency** to hear about every new notice it posts; a **vendor** for its new awards; a **forecast** for its release; an **award** for its follow-on.

**Exercise 3:**

| Step                                                                       | Expected result                  |
| -------------------------------------------------------------------------- | -------------------------------- |
| Follow a notice                                                            | Button reads **Unfollow**        |
| Watch an agency (Agency profile) and a forecast (Forecasts)                | Buttons read **Watching**        |
| Trainer: amend the followed notice (re-run its feed, or edit its due date) | Trainees see a bell notification |
| Check your e-mail after a Real Time match                                  | One alert e-mail per search      |

### Part 6 — Look ahead and ask the assistant (10 min)

- **Forecasts** and **Recompetes**: what's coming before a notice exists.
- **Agency** and **Vendor** profiles, **Vehicle Portfolio**.
- **Assistant**: ask "Why is the fit score on this notice 72?", "What changed in the latest amendment?", "Push this to Opportunity" (it previews and waits for **yes**).

Close with the [daily routine](user-guide.md#a-good-daily-routine).

## Session 2: Power Users (30 minutes)

For BD leads (`NXP_Power_User`).

1. **Share a search** with a team (Visibility _Team_ + public group name).
2. **Create a template**: Visibility _Org Template_. Explain it never alerts; people copy it. Check it appears under _Start from a template_ for a regular user.
3. **Auto-push**: on a search, _Fit Threshold_ 70. Explain retries and that capture fields are never overwritten. Typical use: eBuy RFQs on vehicles you hold.
4. **Bulk push** from the Match Inbox.
5. **Dashboards → Nexus: Market and activity** and the **Match Outcomes** report: use dismiss reasons to tune templates.

**Exercise:** create one Org Template for your team's core market; a colleague copies it.

## Session 3: admins (2 hours)

For Nexus admins (`NXP_Admin`). Follow the [admin guide](admin-guide.md); demo each part in the sandbox.

| Time   | Topic                          | Show                                                                                                                                         |
| ------ | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| 15 min | How it works                   | [How Nexus works](how-it-works.md): sources, matching, alerts, jobs                                                                          |
| 15 min | Users and permissions          | [Adding users](admin-guide.md#adding-users); the four permission sets                                                                        |
| 20 min | Feeds                          | Feed Console, **Run now**, Errors, turning a feed on (NXP Feed Config → Active); the SAM.gov key and its limits                              |
| 15 min | Notifications                  | Deliverability, NXP Match Alert, org-wide address, the problems e-mail                                                                       |
| 15 min | Company Profile and fit rules  | Change a NAICS, run `rescore-notices.apex`, see scores change                                                                                |
| 15 min | eBuy inbox                     | **Inbound Emails**: an _Ingested_ and a _Needs Review_ e-mail; **Reprocess** with an RFQ number                                              |
| 10 min | Documents and SAM.gov files    | Get SAM.gov files, Document Reader settings, Remote Site Settings                                                                            |
| 10 min | AI                             | Prompt templates, `AI_Enabled`, `AI_Max_Calls_Per_Day`, NXP AI Usage                                                                         |
| 15 min | Monitoring and troubleshooting | Problems e-mail (run it with `Admin_Digest_Mode = Daily`), Operations dashboard, NXP Logs, [troubleshooting](admin-guide.md#troubleshooting) |

**Exercises:**

| Step                                                                                  | Expected result                                         |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Assign `NXP_User` to a new user and log in as them                                    | They see the app and can save a search                  |
| Feed Console → **Run now** on SAM.gov Opportunities                                   | A new run, _Succeeded_                                  |
| Set `Admin_Digest_Mode = Daily`; run `NXP_AdminDigestJob.run();` in Execute Anonymous | The problems e-mail arrives (set it back to _Problems_) |
| Reprocess the sample eBuy e-mail                                                      | Status _Ingested_, notice `EBUY:RFQ9990001` updated     |
| Change `Description_Min_Fit` to 40                                                    | More notices get description text after the next run    |
| Create an Org Template                                                                | Users see it under _Start from a template_              |

## Handout: one-page summary

**Every day:** read the 06:30 digest or open **Match Inbox** → Dismiss / Watch / Push each card.

| I want to…                            | Where                                                 |
| ------------------------------------- | ----------------------------------------------------- |
| Hear about a kind of opportunity      | **My Searches** → template or **+** → Save search     |
| Hear about one notice changing        | **Follow** (notice) or **Watch** (inbox card)         |
| Hear about an agency's new notices    | Agency profile → **Watch this agency**                |
| Hear when a forecast is released      | **Forecasts** → **Watch**                             |
| Hear when a contract comes up again   | **Recompetes** → **Watch this recompete**             |
| Read the description or SAM.gov files | Notice → **Load description** / **Get SAM.gov files** |
| Send to capture                       | **Push to Opportunity**                               |

| How you're told                | By                                    |
| ------------------------------ | ------------------------------------- |
| Real Time search               | E-mail and/or bell, within minutes    |
| Daily / Weekly search          | One e-mail at 06:30 (Weekly: Mondays) |
| Anything you follow or watch   | Bell (and Salesforce mobile app)      |
| A notice you pushed is amended | Bell, to the Opportunity's owner      |

**Fit chips:** green = full points, amber = partial, red = none. **Red "document checks" chip** = a file disagrees with the notice: open the notice and check.

**Ask the assistant** (Agentforce panel): "Why this score?", "What changed?", "What does the SOW require?", "Push this to Opportunity".

## After training

- Ask each trainee to keep at least one Daily search and work the inbox for a week.
- After a week, review the **Nexus: Adoption** dashboard (active users, searches by user, pushes by source) and the Match Outcomes report; follow up with anyone not using it.
- Collect the questions you got and add them to the user guide's FAQ.
