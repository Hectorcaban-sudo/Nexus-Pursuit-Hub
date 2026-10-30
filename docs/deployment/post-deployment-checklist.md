# Post-deployment checklist

Copy into the release ticket and tick each item.

## Every release

- [ ] Deployment succeeded; job ID and manifest attached to the ticket
- [ ] `env-config/<env>` deployed
- [ ] `schedule-jobs.apex` ran; Setup → Scheduled Jobs shows _NXP Feed Scheduler_, _NXP Daily Digest_, _NXP Weekly Digest_, _NXP Notice Analyst :15_, _NXP Notice Analyst :45_, _NXP Push Retry_
- [ ] Platform event subscribers running (Setup → Platform Events → NXP Gov Notice Changed → Subscriptions)
- [ ] Feed Console: _Run now_ on SAM_Opportunities → run Succeeded, records read > 0
- [ ] Smoke test: open a new notice → summary card renders; follow / unfollow works
- [ ] Smoke test: preview a saved search; save; a match appears after the next run
- [ ] Smoke test (UAT/prod): push one sample notice to Opportunity → record created, Push Log Success; delete the test record afterwards
- [ ] Smoke test: Forecasts, Recompetes, Vehicle Portfolio and a vendor and agency page load with data
- [ ] Smoke test (if eBuy is set up): send a test eBuy e-mail → **Inbound Emails** shows it _Ingested_ and the notice exists
- [ ] Smoke test (if the Document Reader is on): attach a PDF to a notice → Documents card shows _Read_ within a few minutes
- [ ] Dashboards _Nexus: Market and activity_, _Nexus: Operations_ and _Nexus: Adoption and GovWin cut-over_ open without errors
- [ ] No new ERROR rows in `NXP_Log__c` in the first hour
- [ ] QA only: `load-sample-data --reset` and `test-functional --apex-tests` pass; screen walkthrough done ([testing guide](../guides/testing-guide.md#3-walk-through-the-app))

## First release in an org (also)

- [ ] Setup → Deployment Settings: _Allow deployments of components when corresponding Apex jobs are pending or in progress_ on
- [ ] Permission sets assigned: NXP_User, NXP_Power_User, NXP_Admin, NXP_Integration
- [ ] SAM.gov `ApiKey` set on the NXP SAM.gov principal (System Account key in production) and _Run now_ on SAM_Opportunities succeeds ([steps](deployment-guide.md#samgov-api-key))
- [ ] Personal key only: reminder set to replace it before it expires (90 days)
- [ ] Forecast Named Credential URL and `FC_*` mappings set
- [ ] Active Company Profile created; `rescore-notices.apex` run
- [ ] Push mapping points at the Opportunity object; duplicate field added and mapped; `Contract_Vehicle_Code__c` mapped if the Opportunity has a vehicle field
- [ ] Contract vehicles we hold created (We Hold, expiry, Inbox Address)
- [ ] eBuy (if used): `NXP_Ebuy_Inbox` address created with the integration user as context user; eBuy mail routed to it; `Ebuy_Allowed_Senders` set; auto-push search for eBuy RFQs created by a Power User (optional)
- [ ] Report and dashboard folders shared: _Nexus Pursuit Hub_ with BD users, _Nexus Admin_ with admins and the project lead; subscriptions set up (optional)
- [ ] GovWin parallel run: first GovWin export loaded with `load-govwin-export` (if the cut-over is in progress)
- [ ] Custom notification _NXP Match Alert_ delivery enabled
- [ ] Org-wide e-mail address set in `Alert_OrgWide_Email_Id` (optional)
- [ ] REST integration user, External Client App and NXP_Integration set up (if used)
- [ ] Data Cloud `NXP_Awards` connector and data stream created (if used)
- [ ] Prompt templates created and active; `AI_Enabled` true in env-config (if AI used); `NXP_Document_Analysis` with a File input and `Document_Analysis_Enabled` (if the Document Reader is used); ATO covers sending solicitation documents and eBuy RFQs to the model
- [ ] Nexus Pursuit Assistant built or deployed, tested with `tests/agents/assistant.yaml` (≥ 90%), activated, access assigned

## GovWin cut-over

- [ ] Four-week parallel run complete: share of GovWin-alerted notices also caught meets the agreed target
- [ ] Users trained (user guide), saved searches rebuilt
- [ ] GovWin → Opportunity connector switched off after Nexus pushes are confirmed
