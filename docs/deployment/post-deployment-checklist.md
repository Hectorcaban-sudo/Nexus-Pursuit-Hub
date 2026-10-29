# Post-deployment checklist

Copy into the release ticket and tick each item.

## Every release

- [ ] Deployment succeeded; job ID and manifest attached to the ticket
- [ ] `env-config/<env>` deployed
- [ ] `schedule-jobs.apex` ran; Setup → Scheduled Jobs shows _NXP Feed Scheduler_, _NXP Daily Digest_, _NXP Weekly Digest_, _NXP Notice Analyst_, _NXP Push Retry_
- [ ] Platform event subscribers running (Setup → Platform Events → NXP Gov Notice Changed → Subscriptions)
- [ ] Feed Console: _Run now_ on SAM_Opportunities → run Succeeded, records read > 0
- [ ] Smoke test: open a new notice → summary card renders; follow / unfollow works
- [ ] Smoke test: preview a saved search; save; a match appears after the next run
- [ ] Smoke test (UAT/prod): push one sample notice to TechnoMile → record created, Push Log Success; delete the test record afterwards
- [ ] No new ERROR rows in `NXP_Log__c` in the first hour
- [ ] QA only: `load-sample-data --reset` and `test-functional --apex-tests` pass; screen walkthrough done ([testing guide](../guides/testing-guide.md#3-walk-through-the-app))

## First release in an org (also)

- [ ] Setup → Deployment Settings: _Allow deployments of components when corresponding Apex jobs are pending or in progress_ on
- [ ] Permission sets assigned: NXP_User, NXP_Power_User, NXP_Admin, NXP_Integration
- [ ] SAM.gov `ApiKey` set on the NXP SAM.gov principal
- [ ] Forecast Named Credential URL and `FC_*` mappings set
- [ ] Active Company Profile created; `rescore-notices.apex` run
- [ ] Push mapping points at the TechnoMile object; duplicate field added and mapped
- [ ] Custom notification _NXP Match Alert_ delivery enabled
- [ ] Org-wide e-mail address set in `Alert_OrgWide_Email_Id` (optional)
- [ ] REST integration user, External Client App and NXP_Integration set up (if used)
- [ ] Data Cloud `NXP_Awards` connector and data stream created (if used)
- [ ] Prompt templates created and active; `AI_Enabled` true in env-config (if AI used)
- [ ] Nexus Pursuit Assistant built or deployed, tested with `tests/agents/assistant.yaml` (≥ 90%), activated, access assigned

## GovWin cut-over

- [ ] Four-week parallel run complete: share of GovWin-alerted notices also caught meets the agreed target
- [ ] Users trained (user guide), saved searches rebuilt
- [ ] GovWin → TechnoMile connector switched off after Nexus pushes are confirmed
