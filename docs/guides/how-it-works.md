# How Nexus Pursuit Hub works

A plain-language walk through the whole system, for training BD users and admins. The [user guide](user-guide.md) says which buttons to press; the [admin guide](admin-guide.md) says how to set it up and keep it running. This page explains what happens in between.

## The big picture

Nexus finds U.S. government opportunities, decides which ones matter to you, tells you about them, helps you read them, and sends the ones you pursue to **Opportunity**, where capture and proposals happen. Nexus never manages the pursuit itself.

```text
Sources ──► Notices ──► Fit score ──► Saved searches ──► Match Inbox + alerts ──► Push ──► Opportunity
SAM.gov       one per      0–100 vs       yours, your        what you work           preview,    capture,
eBuy e-mail   opportunity  the company    team's or          every day               then yes    pipeline,
REST, Data    with its     profile        templates                                              proposal
Cloud         versions
```

## 1. Where notices come from

| Source                    | How it arrives                                                               | How often                                     |
| ------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------- |
| **SAM.gov opportunities** | The SAM.gov feed calls the SAM.gov API with your organisation's API key      | Every hour (at minute 5), when the feed is on |
| **GSA eBuy RFQs**         | eBuy e-mails are redirected to the Nexus eBuy inbox address and read by code | As the e-mail arrives                         |
| **Other systems**         | The Nexus REST API (`/nxp/v1/...`) or a Data Cloud connector                 | When those systems send                       |
| **Forecasts and awards**  | Agency forecast and USAspending feeds; vendor details from SAM.gov           | Weekly or daily, when turned on               |

Every opportunity becomes one **Gov Notice**. When SAM.gov publishes an amendment, Nexus doesn't create a second notice: it updates the notice and keeps a **version** that lists what changed (due date, set-aside, value, scope, status…). The same solicitation arriving from two sources is merged into one notice.

### Description text and attachments

SAM.gov's search sends only a **link** to each notice's description and attachments. Fetching them costs one SAM.gov API call each, and the key has a daily limit, so Nexus fetches them only where they're needed:

- **Automatically** for notices that match someone's saved search, or score high on fit (50+ for descriptions, 70+ for files), and for notices whose match depends on words in the description.
- **On request** on any notice: **Load description** and **Get SAM.gov files**.

Files up to 6 MB are saved on the notice; larger ones stay on SAM.gov. eBuy RFQs bring their attachments in the e-mail.

## 2. The fit score

Each notice gets a **fit score from 0 to 100** against your company's **Company Profile** (kept by the admin). Rules and their weights:

| Rule        | Points | Full points when                                              |
| ----------- | ------ | ------------------------------------------------------------- |
| NAICS       | 30     | The notice's NAICS is one of ours                             |
| Agency      | 20     | It's a target agency                                          |
| Set-aside   | 15     | We qualify for the set-aside (full and open gets half)        |
| Keywords    | 20     | Three or more of our capability keywords appear               |
| Value range | 15     | The value is in our range (not published gets half)           |
| Vehicle     | off    | Can be turned on: the notice is on a contract vehicle we hold |

Fit **75+** is high (blue), **60–74** medium (amber), below 60 low. Every card and notice shows the reasons: the two rules that added the most and the one that cost the most. The score is a sorting aid, not a bid decision.

## 3. Saved searches and matching

A **saved search** describes what you want: keywords, buyer, NAICS, PSC, set-aside, notice type, value, due date, minimum fit. Keywords support `AND`, `OR`, `NOT`, quotes and `word*`, and are checked against the title **and** the description.

- **When a notice arrives or changes**, Nexus checks it against every active saved search. A hit is a **match**, which lands in that search owner's **Match Inbox**.
- **When you save a search**, Nexus also checks it against the open notices already loaded, so what the live preview showed appears in your inbox within a minute. These existing notices don't send alerts.
- If only the description could decide a match (it's still a link), Nexus fetches the description and checks again; the match can arrive up to an hour after the notice.

**Find similar** (on a notice) starts a search from that notice: it offers the notice's buyer, NAICS, PSC, set-aside and early notice types as choices, each with a narrower and a wider option, and suggests keywords. With AI on, the keywords come from the `NXP_Similar_Keywords` prompt template (one AI call, checked as a valid keyword expression before it's used); otherwise from the notice title. The result is an ordinary saved search.

Searches can be **Private** (default), shared with a **Team**, or an **Org Template** that everyone can copy with **Use template** (Power Users). Templates never alert by themselves.

## 4. Alerts and notifications

There are two ways Nexus tells you something: **e-mail**, and **Salesforce notifications** (the bell in Salesforce, and the Salesforce mobile app; Slack or Teams only if your org's Salesforce integration forwards them).

| What happens                                        | Who is told                    | How                                                                                            | When               |
| --------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------- | ------------------ |
| New match on a **Real Time** search                 | The search's owner             | **E-mail** (if the Email channel is ticked) and **bell** (if the Salesforce channel is ticked) | Within minutes     |
| New matches on a **Daily** search                   | The search's owner             | One **e-mail digest** per person, all their daily searches together                            | Every day at 06:30 |
| New matches on a **Weekly** search                  | The search's owner             | One **e-mail digest**                                                                          | Mondays at 06:30   |
| Search set to **None**                              | Nobody                         | Inbox only                                                                                     | –                  |
| A matched notice is amended (_alert on changes_ on) | The search's owner             | Same as a new match, marked _Updated (Due date)_ and so on                                     | As above           |
| A **followed or watched** item changes (see 5)      | Whoever follows it             | **Bell** only                                                                                  | Within minutes     |
| A pushed notice is amended                          | The Opportunity record's owner | **Bell**                                                                                       | Within minutes     |
| Something failed in the last 24 hours               | Admins                         | **E-mail** (problems e-mail)                                                                   | Every day at 07:00 |

Daily and weekly digests always come by e-mail; the channel ticks apply to Real Time alerts. Times are in the time zone of the admin who scheduled the jobs.

E-mail only goes out when the org allows it: in a sandbox, **Setup → Deliverability** is usually _System email only_, so no Nexus e-mail arrives until an admin sets it to _All email_. Bell notifications need the _NXP Match Alert_ notification turned on (admin setup).

## 5. Follow and watch

**Following** (or **watching**, the same thing) is for a specific record you care about, regardless of your searches. It never sends e-mail, only bell notifications.

| You follow or watch | Where                                                  | You're told when                                                                                  |
| ------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| A notice            | **Follow** on the notice; **Watch** in the Match Inbox | It changes (an amendment, a cancellation, a new due date…)                                        |
| An agency           | **Watch this agency** on its profile                   | It, or any of its sub-agencies, posts a new notice                                                |
| A vendor            | **Watch this vendor** on its profile                   | It wins a new award                                                                               |
| A forecast          | **Watch** on the Forecasts tab                         | It's released as a notice                                                                         |
| An award            | **Watch this recompete** on Recompetes                 | A likely follow-on is posted (linked to the award, or same agency and NAICS near the award's end) |

**Watch** in the Match Inbox also keeps the card in your inbox (switch on _Include watching_ to see those), while **Dismiss** removes it. Stop by clicking the same button again (**Unfollow** on a notice, **Watching** elsewhere).

## 6. Reading a notice

The notice page brings together:

- **Facts**: days to respond, fit with reasons, value, set-aside, NAICS/PSC, sources, contacts, versions.
- **AI summary**: written for notices that match a saved search (when AI is on), within about 30 minutes, after the description is fetched. It's a draft: check it against the solicitation.
- **Documents**: every file on the notice. The **Document Reader** (AI, when on) reads each PDF and lists requirements, evaluation factors, submission rules, key dates, clearance and risks.
- **Document checks**: when a file disagrees with the notice (a different due date, NAICS or set-aside), a red box shows both values. Someone checks the file and clicks **Mark as checked**. Inbox cards show a _document checks_ chip, and the push dialog warns.

## 7. Push to Opportunity

When you decide to pursue, **Push to Opportunity** shows exactly which values will be sent and whether an Opportunity already exists for that solicitation, then creates or links the record after you confirm. After that:

- Fields your admin set to **Update** (usually the due date) follow amendments automatically.
- Fields set to **Alert only** (value, set-aside) and **Never** don't change.
- Whenever the notice is amended, the Opportunity's owner gets a bell notification saying what changed.
- Capture fields (stage, pWin, owner, team) are never touched by Nexus.

**Auto-push** (Power Users) pushes matches of a search automatically above a fit threshold; it's used for eBuy RFQs, which close fast. **Bulk push** pushes several selected cards at once.

## 8. The assistant

The **Nexus Pursuit Assistant** (Agentforce panel) answers questions from Nexus data: drafts and saves searches, explains a fit score, says what changed or what the documents require, finds the incumbent and recompetes, previews and pushes notices. It always shows a preview and waits for **yes** before it saves or pushes anything.

## 9. Settings

Admins change Nexus settings on the **Settings** tab rather than in Setup: alert, feed, search, AI, file, eBuy, fit rule and push settings, each with a description. Saving deploys the custom metadata (about 30 seconds) and records who changed what in **Setting Changes**. Deploying a release puts shipped values back; the release scripts then reapply what admins saved there, except the values `env-config` sets on purpose (AI on or off, feed switches). The tab's health checks show whether e-mail, the bell, the SAM.gov key, the jobs, file downloads, the Company Profile and AI are working.

## 10. What runs on its own

| Job                | When                   | Does                                                                          |
| ------------------ | ---------------------- | ----------------------------------------------------------------------------- |
| NXP Feed Scheduler | Every hour at :05      | Runs due feeds; after SAM.gov runs, fetches descriptions and files as above   |
| Matching           | Continuously           | Checks new and changed notices against saved searches; sends Real Time alerts |
| NXP Notice Analyst | :15 and :45 every hour | AI summaries, amendment summaries, documents waiting to be read               |
| NXP Push Retry     | Every hour at :20      | Retries failed auto-pushes                                                    |
| NXP Daily Digest   | 06:30 daily            | Daily e-mail digests                                                          |
| NXP Weekly Digest  | 06:30 Mondays          | Weekly e-mail digests                                                         |
| NXP Admin Digest   | 07:00 daily            | Problems e-mail to admins                                                     |

## 11. Limits to know

- **SAM.gov key**: each call counts against the key's daily limit. Personal keys expire every 90 days; production should use a System Account key. When the limit is reached, feeds and downloads wait until the key resets.
- **AI**: at most `AI_Max_Calls_Per_Day` (500) AI calls a day. After that, summaries and document reading wait for the next day.
- **Who sees what**: everyone sees notices, forecasts, awards, agencies and vendors. Saved searches and matches are private to their owner unless shared. Inbound eBuy e-mail, logs and feed controls are for admins.
