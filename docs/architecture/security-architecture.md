# Security architecture

Government notice data is public, so intel records are readable by every Nexus Pursuit Hub user. GSA eBuy RFQs are the exception: they are visible only to Schedule holders, so the e-mails they arrive in are kept on a private, admin-only object (see Inbound Email below), and the notices made from them are readable by Nexus users only, like every notice. What is private is each user's saved searches, matches and follows, and the Opportunity records a push creates, which follow Opportunity sharing.

## Sharing

| Object                                                                                          | Org-wide default                                     | Notes                                                                                                                                                                         |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gov Notice, Agency, Vendor, Contact, Forecast, Award Summary, Contract Vehicle, Company Profile | Public Read/Write                                    | Users get **read** through `NXP_User`; only ingestion (system mode) and admins write                                                                                          |
| Notice Version                                                                                  | Controlled by parent                                 |                                                                                                                                                                               |
| Saved Search                                                                                    | Private                                              | Apex-managed sharing: _Team_ shares read to a public group; _Org Template_ shares read to All Internal Users                                                                  |
| Search Match                                                                                    | Controlled by parent (master-detail to Saved Search) |                                                                                                                                                                               |
| Follow                                                                                          | Private                                              |                                                                                                                                                                               |
| Push Log, Feed Run, NXP Log                                                                     | Public Read/Write                                    | Users read push logs; feed runs and logs are admin-only by permission set                                                                                                     |
| Document Analysis                                                                               | Controlled by parent (Gov Notice)                    | What AI read from a notice's files; written by the Document Reader (system mode), read by whoever reads the notice                                                            |
| Usage, GovWin Alert                                                                             | Private                                              | Usage is per-user activity (screen name and count only); both are read through `NXP_Admin` (View All). The reports and dashboards about them sit in the _Nexus Admin_ folders |
| Inbound Email                                                                                   | Private                                              | eBuy e-mail as received (sender, body, attachments). Only `NXP_Admin` grants access (View All); the Inbound Emails screen also checks `NXP_Admin_Access`                      |

## Permission sets

| Permission set    | Who                                               | Grants                                                                                                             |
| ----------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `NXP_User`        | Every BD user                                     | App, tabs, read on intel objects, own searches/matches/follows, controller and agent action classes                |
| `NXP_Power_User`  | BD leads (assign with `NXP_User`)                 | Custom permission `NXP_Power_User`: share searches, bulk push, auto-push                                           |
| `NXP_Admin`       | Salesforce admins and the user who schedules jobs | Everything, plus `NXP_Admin_Access` (Feed Console Run now), `NXP_Integration_Access`, SAM.gov credential principal |
| `NXP_Integration` | REST integration user only                        | Create/edit intel objects, feed runs; REST resource classes; `NXP_Integration_Access`                              |

## Code-level controls

- Controllers, selectors used by UI, and agent actions run in **user mode** (`WITH USER_MODE`, `AccessLevel.USER_MODE`, `as user` DML).
- Ingestion, matching, alerts, auto-push, retry and sync run in **system mode** as background work, and each such class is marked `without sharing` with a comment.
- The REST API rejects callers without the `NXP_Integration_Access` custom permission (HTTP 403).
- Solicitation documents are untrusted: the Document Reader template only returns field values, `NXP_DocumentAnalysisParser` keeps known keys, cleans text and validates dates, and nothing acts on the content.
- The eBuy e-mail handler accepts only senders in `Ebuy_Allowed_Senders` (set the same list in the e-mail address's _Accept Email From_), drops executable and HTML attachments, and treats e-mail text as untrusted: the AI template may only return field values, which code validates; the RFQ number, which decides which notice is updated, is never taken from AI.
- Push and Save Search from the assistant require an HMAC **preview token**, issued by the matching preview action for the same user and subject today, so the model cannot skip the preview.
- Auto-push and team/org sharing check the `NXP_Power_User` custom permission server-side.

## Credentials

- `NXP_User` also has the SAM.gov credential principal, so **Load description** and the description fetch started when a user saves a search can call SAM.gov as that user. Users can't send their own requests: only the app's Apex uses the credential, and only Feed Console users (`NXP_Admin_Access`) can start feeds.
- The SAM.gov API key is never in code or metadata. It lives on the `NXP_SAM_Gov` External Credential principal (parameter `ApiKey`) and is sent as the `X-Api-Key` header by the Named Credential.
- USAspending and forecast endpoints use the `NXP_Public_API` External Credential: Custom protocol with a `Default` named principal and no parameters, so no key is sent. The running user needs access to the `NXP_Public_API-Default` principal (in `NXP_Admin`), the same as for SAM.gov.
- The REST integration uses OAuth 2.0 client credentials (External Client App or connected app) mapped to a dedicated integration user with only `NXP_Integration`.
- Release automation authenticates with web login or JWT, with the certificate stored outside the repository (`.gitignore` blocks `*.key`, `*.pem`).

## AI

- All prompt-template calls go through the Einstein Trust Layer (masking, zero data retention, audit). AI is off until `NXP_Setting.AI_Enabled = true`.
- AI output is labelled ("AI draft") in the UI, and agent actions cite notice IDs.
- AI coding assistants in the repo (Agentforce Vibes, DX MCP Server, others) stay off unless your ATO allows them.

## Audit

| Record                  | Kept for                                                                       |
| ----------------------- | ------------------------------------------------------------------------------ |
| `NXP_Feed_Run__c`       | Each feed run and REST call: caller, counts, errors, idempotency key, response |
| `NXP_Push_Log__c`       | Each push and sync: who, mode, target, status, error                           |
| `NXP_Notice_Version__c` | Each amendment: changed fields and diff                                        |
| Field history           | Notice type, status, NAICS, set-aside, value, response due                     |
| `NXP_Log__c`            | Errors and warnings from jobs and services                                     |
