// Nexus Pursuit Hub functional smoke test. Run against a dev or QA org that has the sample data
// (scripts/load-sample-data.ps1 or .sh). Exercises the real services end to end and records one
// line per check:  <PASS|FAIL|WARN|SKIP>|<check>|<detail>
// Results are saved in an NXP_Log__c row (Source__c = 'NXP-SMOKE', Level__c = 'INFO') that the runner
// scripts (scripts/test-functional.ps1 / .sh) read back, and are also written to the debug log.
//
// Side effects (by design, so you can look at the results in the app afterwards):
//   - creates or updates the notice SAMPLE-REST-0001 through the REST ingestion resource;
//   - pushes the highest-fit SAMPLE notice to the push target (Opportunity by default) once;
//   - queues the daily digest batch (sends digest e-mail if deliverability is on).
List<String> out = new List<String>();
Integer fails = 0;
Id me = UserInfo.getUserId();

// 0. Apex REST ingestion API -----------------------------------------------------------------
// Calls the REST resource class directly: the same code a POST to /services/apexrest/nxp/v1/notices
// runs, without needing an access token. Sent twice with one Idempotency-Key to check the replay.
try {
    Date today = Date.today();
    Map<String, Object> restRecord = new Map<String, Object>{
        'noticeId' => 'SAMPLE-REST-0001',
        'sourceId' => 'REST-0001',
        'title' => 'Network Segmentation Pilot (REST sample)',
        'solicitationNumber' => 'SAMPLE-SOL-REST-0001',
        'noticeType' => 'Sources Sought',
        'agencyPath' => 'Homeland Security > Customs and Border Protection',
        'naics' => '541512',
        'psc' => 'DA01',
        'setAside' => 'Total Small Business Set-Aside',
        'estimatedValue' => 1500000,
        'postedDate' => String.valueOf(today),
        'responseDue' => String.valueOf(today.addDays(30)) + 'T17:00:00Z',
        'description' => '[SAMPLE DATA] Sent through the Apex REST ingestion resource by the functional test.',
        'url' => 'https://example.gov/notices/sample-rest-0001',
        'contacts' => new List<Object>{
            new Map<String, Object>{
                'name' => 'Sample Contact',
                'email' => 'sample.contact@example.gov',
                'role' => 'Program Manager'
            }
        }
    };
    String restBody = JSON.serialize(
        new Map<String, Object>{ 'source' => 'sample', 'records' => new List<Object>{ restRecord } }
    );
    String restKey = 'nxp-smoke-' + Datetime.now().getTime();

    RestRequest firstRequest = new RestRequest();
    firstRequest.requestURI = '/services/apexrest/nxp/v1/notices';
    firstRequest.httpMethod = 'POST';
    firstRequest.addHeader('Idempotency-Key', restKey);
    firstRequest.requestBody = Blob.valueOf(restBody);
    RestContext.request = firstRequest;
    RestContext.response = new RestResponse();
    NXP_NoticeIngestResource.ingest();
    RestResponse firstResponse = RestContext.response;
    String firstText = firstResponse.responseBody == null ? '' : firstResponse.responseBody.toString();
    Boolean accepted = false;
    if (firstResponse.statusCode == 200) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(firstText);
        Integer done =
            (Integer) payload.get('created') + (Integer) payload.get('updated') + (Integer) payload.get('unchanged');
        accepted = (Integer) payload.get('rejected') == 0 && done == 1;
    }
    out.add(
        (accepted ? 'PASS' : 'FAIL') + '|REST ingestion|HTTP ' + firstResponse.statusCode + ' ' + firstText.left(200) +
        (accepted ? '' : ' (the user needs the NXP_Integration or NXP_Admin permission set)')
    );
    fails += accepted ? 0 : 1;

    RestRequest secondRequest = new RestRequest();
    secondRequest.requestURI = '/services/apexrest/nxp/v1/notices';
    secondRequest.httpMethod = 'POST';
    secondRequest.addHeader('Idempotency-Key', restKey);
    secondRequest.requestBody = Blob.valueOf(restBody);
    RestContext.request = secondRequest;
    RestContext.response = new RestResponse();
    NXP_NoticeIngestResource.ingest();
    Boolean replayed = RestContext.response.headers.get('Idempotent-Replay') == 'true';
    out.add(
        (replayed ? 'PASS' : 'FAIL') + '|REST idempotency|' +
        (replayed ? 'same Idempotency-Key replayed the first response' : 'second call was not a replay')
    );
    fails += replayed ? 0 : 1;
} catch (Exception e) {
    out.add('FAIL|REST ingestion|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 1. Configuration --------------------------------------------------------------------------
try {
    Integer profiles = [SELECT COUNT() FROM NXP_Company_Profile__c WHERE Active__c = TRUE];
    Integer rules = [SELECT COUNT() FROM NXP_Fit_Rule__mdt WHERE Active__c = TRUE];
    Integer feeds = [SELECT COUNT() FROM NXP_Feed_Config__mdt];
    Boolean ok = profiles == 1 && rules > 0 && feeds > 0;
    out.add((ok ? 'PASS' : 'FAIL') + '|Configuration|active profiles=' + profiles + ', fit rules=' + rules + ', feed configs=' + feeds + ' (need exactly 1 active profile)');
    fails += ok ? 0 : 1;
} catch (Exception e) {
    out.add('FAIL|Configuration|' + e.getMessage());
    fails++;
}

// 2. Sample data ----------------------------------------------------------------------------
List<NXP_Gov_Notice__c> samples = [
    SELECT Id, Notice_Id__c, Title__c, Fit_Score__c, Fit_Breakdown__c, Pushed_Record_Id__c
    FROM NXP_Gov_Notice__c
    WHERE Notice_Id__c LIKE 'SAMPLE-%'
    ORDER BY Fit_Score__c DESC NULLS LAST
];
Boolean haveSamples = samples.size() >= 10;
out.add((haveSamples ? 'PASS' : 'FAIL') + '|Sample notices|' + samples.size() + ' found (expected 10 or more). Run load-sample-data first.');
fails += haveSamples ? 0 : 1;

// 3. Fit scoring (NXP_FitScoreService, runs in the Gov Notice trigger) ----------------------
if (haveSamples) {
    Integer scored = 0;
    for (NXP_Gov_Notice__c n : samples) {
        if (n.Fit_Score__c != null && String.isNotBlank(n.Fit_Breakdown__c)) {
            scored++;
        }
    }
    Boolean ok = scored == samples.size();
    out.add((ok ? 'PASS' : 'FAIL') + '|Fit scoring|' + scored + ' of ' + samples.size() + ' scored; top: ' + samples[0].Notice_Id__c + ' = ' + samples[0].Fit_Score__c);
    fails += ok ? 0 : 1;
    try {
        String why = NXP_FitScoreService.explain(
            new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byId(samples[0].Id)
        );
        Boolean explained = why != null && why.startsWith('Fit score');
        out.add((explained ? 'PASS' : 'FAIL') + '|Explain fit score|' + why.split('\n')[0]);
        fails += explained ? 0 : 1;
    } catch (Exception e) {
        out.add('FAIL|Explain fit score|' + e.getMessage());
        fails++;
    }
}

// 4. Search criteria: draft from plain English, preview (Search Builder) -------------------
try {
    NXP_CriteriaDraftService.Draft d = NXP_CriteriaDraftService.draft(
        'Homeland Security cyber notices, small business, 541512, daily'
    );
    Boolean ok = d != null && d.criteria != null && d.frequency == 'Daily' && d.criteria.naics.contains('541512');
    out.add((ok ? 'PASS' : 'FAIL') + '|Draft criteria|' + (d == null ? 'null' : d.criteriaJson));
    fails += ok ? 0 : 1;
} catch (Exception e) {
    out.add('FAIL|Draft criteria|' + e.getMessage());
    fails++;
}
try {
    NXP_SearchController.Preview p = NXP_SearchController.previewSearch(
        '{"agencies":["Homeland Security"],"naics":["5415*"],"setAsides":["Small Business"]}'
    );
    Boolean ok = p.count >= 4;
    out.add((ok ? 'PASS' : 'FAIL') + '|Search preview|' + p.count + ' notices match "DHS, 5415*, small business" (expected 4 or more)');
    fails += ok ? 0 : 1;
} catch (Exception e) {
    out.add('FAIL|Search preview|' + e.getMessage());
    fails++;
}

// 5. Saved searches and matching (event-driven) ---------------------------------------------
List<NXP_Saved_Search__c> searches = [
    SELECT Id, Name
    FROM NXP_Saved_Search__c
    WHERE Name LIKE 'SAMPLE - %' AND OwnerId = :me
];
if (searches.isEmpty()) {
    out.add('FAIL|Saved searches|No SAMPLE searches for this user. Run scripts/apex/seed-searches.apex.');
    fails++;
} else {
    out.add('PASS|Saved searches|' + searches.size() + ' SAMPLE searches');
    Integer matches = [SELECT COUNT() FROM NXP_Search_Match__c WHERE Saved_Search__c IN :searches];
    if (matches == 0 && haveSamples) {
        // The platform event subscriber has not run yet (or is suspended). Run matching
        // synchronously so the rest of the test can continue, and flag it.
        Map<Id, String> changeTypes = new Map<Id, String>();
        for (NXP_Gov_Notice__c n : samples) {
            changeTypes.put(n.Id, 'New');
        }
        NXP_SearchMatchService.process(changeTypes, changeTypes.keySet());
        matches = [SELECT COUNT() FROM NXP_Search_Match__c WHERE Saved_Search__c IN :searches];
        out.add('WARN|Event matching|No matches from the event subscriber yet; ran matching directly. Re-run in a minute, or check Setup > Platform Events > NXP Gov Notice Changed > Subscriptions.');
    }
    Boolean ok = matches >= 6;
    out.add((ok ? 'PASS' : 'FAIL') + '|Search matches|' + matches + ' matches across SAMPLE searches (expected 6 or more)');
    fails += ok ? 0 : 1;
    try {
        List<NXP_SearchController.SearchSummary> mine = NXP_SearchController.getMySearches();
        out.add((mine.isEmpty() ? 'FAIL' : 'PASS') + '|Match Inbox data|' + mine.size() + ' searches returned to the inbox');
        fails += mine.isEmpty() ? 1 : 0;
    } catch (Exception e) {
        out.add('FAIL|Match Inbox data|' + e.getMessage());
        fails++;
    }
}

// 6. Notice record page --------------------------------------------------------------------
if (haveSamples) {
    try {
        NXP_NoticeController.Detail detail = NXP_NoticeController.getDetail(samples[0].Id);
        out.add((detail != null ? 'PASS' : 'FAIL') + '|Notice summary|record page data loaded for ' + samples[0].Notice_Id__c);
        fails += detail != null ? 0 : 1;
    } catch (Exception e) {
        out.add('FAIL|Notice summary|' + e.getMessage());
        fails++;
    }
}

// 7. Push to TechnoMile (preview, token, push, idempotency) ---------------------------------
if (haveSamples) {
    NXP_Gov_Notice__c top = samples[0];
    try {
        NXP_PushService.PushPreview pv = NXP_PushService.preview(top.Id);
        Boolean previewOk = pv.fields != null && !pv.fields.isEmpty() && String.isNotBlank(pv.token);
        out.add((previewOk ? 'PASS' : 'FAIL') + '|Push preview|' + (pv.fields == null ? 0 : pv.fields.size()) + ' mapped fields to ' + pv.targetObject + (pv.alreadyPushed ? ' (already pushed)' : ''));
        fails += previewOk ? 0 : 1;

        NXP_PushService.PushResult bad = NXP_PushService.pushWithToken(top.Id, 'not-a-token', me);
        Boolean guarded = bad.status == 'Failed';
        out.add((guarded ? 'PASS' : 'FAIL') + '|Push guardrail|push without a valid preview token is refused');
        fails += guarded ? 0 : 1;

        if (pv.alreadyPushed) {
            out.add('PASS|Push|already pushed earlier to ' + pv.existingRecordId + ' (not pushed twice)');
        } else {
            NXP_PushService.PushResult r = NXP_PushService.pushWithToken(top.Id, pv.token, me);
            Boolean pushed = r.targetId != null && r.status != 'Failed';
            out.add((pushed ? 'PASS' : 'FAIL') + '|Push|' + r.status + ' ' + (r.targetId == null ? '' : String.valueOf(r.targetId)) + ' ' + (r.message == null ? '' : r.message));
            fails += pushed ? 0 : 1;
        }
        Integer logs = [SELECT COUNT() FROM NXP_Push_Log__c WHERE Gov_Notice__c = :top.Id];
        out.add((logs > 0 ? 'PASS' : 'FAIL') + '|Push log|' + logs + ' push log rows for ' + top.Notice_Id__c);
        fails += logs > 0 ? 0 : 1;
    } catch (Exception e) {
        out.add('FAIL|Push|' + e.getMessage() + ' (check Opportunity validation rules and the NXP_Push_Mapping records)');
        fails++;
    }
}

// 7b. Market intel: award, vendor and forecast data (Find Incumbent, Recompete Query, forecasts) ----
try {
    Integer awardCount = [SELECT COUNT() FROM NXP_Award_Summary__c WHERE PIID__c LIKE 'SAMPLE-%'];
    Integer vendorCount = [SELECT COUNT() FROM NXP_Gov_Vendor__c WHERE UEI__c LIKE 'SMPLUEI%'];
    Integer forecastCount = [SELECT COUNT() FROM NXP_Gov_Forecast__c WHERE Forecast_Id__c LIKE 'SAMPLE-%'];
    Boolean haveMarket = awardCount >= 6 && vendorCount >= 4 && forecastCount >= 3;
    out.add(
        (haveMarket ? 'PASS' : 'FAIL') + '|Market data|' + awardCount + ' awards, ' + vendorCount + ' vendors, ' +
        forecastCount + ' forecasts (expected 6, 4, 3; run load-sample-data again)'
    );
    fails += haveMarket ? 0 : 1;
    if (haveMarket) {
        Map<String, Id> noticeIdByKey = new Map<String, Id>();
        for (NXP_Gov_Notice__c n : [
            SELECT Id, Notice_Id__c
            FROM NXP_Gov_Notice__c
            WHERE Notice_Id__c IN ('SAMPLE-0001', 'SAMPLE-0002', 'SAMPLE-0003')
        ]) {
            noticeIdByKey.put(n.Notice_Id__c, n.Id);
        }
        NXP_FindIncumbentAction.Request linked = new NXP_FindIncumbentAction.Request();
        linked.noticeId = noticeIdByKey.get('SAMPLE-0001');
        NXP_FindIncumbentAction.Request candidates = new NXP_FindIncumbentAction.Request();
        candidates.noticeId = noticeIdByKey.get('SAMPLE-0003');
        List<NXP_FindIncumbentAction.Response> answers = NXP_FindIncumbentAction.run(
            new List<NXP_FindIncumbentAction.Request>{ linked, candidates }
        );
        Boolean incumbentOk =
            answers[0].answer.contains('SAMPLE-PIID-0001') && answers[1].answer.contains('SAMPLE-PIID-0002');
        out.add(
            (incumbentOk ? 'PASS' : 'FAIL') + '|Find incumbent|SAMPLE-0001 -> predecessor SAMPLE-PIID-0001; ' +
            'SAMPLE-0003 -> candidate SAMPLE-PIID-0002' + (incumbentOk ? '' : '. Got: ' + answers[0].answer.left(120))
        );
        fails += incumbentOk ? 0 : 1;

        NXP_RecompeteQueryAction.Request rq = new NXP_RecompeteQueryAction.Request();
        rq.agency = 'Veterans';
        rq.monthsAhead = 18;
        rq.minValue = 10000000;
        String recompetes = NXP_RecompeteQueryAction.run(new List<NXP_RecompeteQueryAction.Request>{ rq })[0].recompetes;
        Boolean recompeteOk = recompetes.contains('SAMPLE-PIID-0003') && recompetes.contains('SAMPLE-PIID-0004');
        out.add(
            (recompeteOk ? 'PASS' : 'FAIL') + '|Recompete query|VA awards over $10M ending within 18 months: ' +
            (recompeteOk ? 'SAMPLE-PIID-0003, SAMPLE-PIID-0004' : recompetes.left(150))
        );
        fails += recompeteOk ? 0 : 1;

        NXP_Gov_Forecast__c fc = [
            SELECT Matched_Notice__c
            FROM NXP_Gov_Forecast__c
            WHERE Forecast_Id__c = 'SAMPLE-FC-0001'
        ];
        Boolean forecastOk = fc.Matched_Notice__c != null && fc.Matched_Notice__c == noticeIdByKey.get('SAMPLE-0002');
        out.add(
            (forecastOk ? 'PASS' : 'FAIL') + '|Forecast link|SAMPLE-FC-0001 ' +
            (forecastOk ? 'is linked to notice SAMPLE-0002' : 'is not linked to SAMPLE-0002')
        );
        fails += forecastOk ? 0 : 1;
    }
} catch (Exception e) {
    out.add('FAIL|Market data|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 8. Feed console and REST/feed run history -------------------------------------------------
try {
    NXP_FeedConsoleController.Console c = NXP_FeedConsoleController.getConsole();
    out.add((c.feeds.isEmpty() ? 'FAIL' : 'PASS') + '|Feed console|' + c.feeds.size() + ' feeds, scheduler active=' + c.schedulerActive + ', recent runs=' + c.runs.size());
    fails += c.feeds.isEmpty() ? 1 : 0;
    if (c.schedulerActive != true) {
        out.add('WARN|Scheduled jobs|Feed scheduler is not scheduled. Run scripts/post-deploy/schedule-jobs.apex.');
    }
} catch (Exception e) {
    out.add('FAIL|Feed console|' + e.getMessage());
    fails++;
}

// 9. Digest batch ---------------------------------------------------------------------------
try {
    Id jobId = Database.executeBatch(new NXP_DigestBatch('Daily'), 50);
    out.add('PASS|Daily digest|batch queued ' + jobId + ' (check Setup > Apex Jobs)');
} catch (Exception e) {
    out.add('FAIL|Daily digest|' + e.getMessage());
    fails++;
}

// 10. AI and errors -------------------------------------------------------------------------
out.add(
    NXP_Settings.getBoolean('AI_Enabled', false)
        ? 'PASS|AI setting|AI_Enabled = true (summaries run from the Notice Analyst job)'
        : 'SKIP|AI setting|AI_Enabled = false in this org; AI summaries are not tested'
);
Integer errors = [SELECT COUNT() FROM NXP_Log__c WHERE Level__c = 'ERROR' AND CreatedDate = TODAY];
out.add((errors == 0 ? 'PASS' : 'WARN') + '|Error log|' + errors + ' ERROR rows in NXP Logs today');

out.add('SUMMARY|' + (fails == 0 ? 'PASS' : 'FAIL') + '|' + fails + ' failed of ' + (out.size()) + ' checks');

// Save the results where the runner can read them, whatever the size of the debug log.
insert new NXP_Log__c(
    Level__c = 'INFO',
    Source__c = 'NXP-SMOKE',
    Transaction_Id__c = Request.getCurrent().getRequestId(),
    Message__c = String.join(out, '\n')
);
for (String line : out) {
    System.debug(LoggingLevel.ERROR, 'NXP-SMOKE|' + line);
}
