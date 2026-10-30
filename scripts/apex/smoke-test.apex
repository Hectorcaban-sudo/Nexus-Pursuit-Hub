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

// 7. Push to Opportunity (preview, token, push, idempotency) ---------------------------------
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

// 7c. Market screens (Forecasts, Recompetes, Vendor profile) and Watch -----------------------------
try {
    NXP_MarketController.ForecastBoard board = NXP_MarketController.getForecastBoard(null, null, null, null, false);
    Integer forecastCards = 0;
    for (NXP_MarketController.ForecastColumn col : board.columns) {
        forecastCards += col.cards.size();
    }
    Boolean boardOk = board.columns.size() == 5 && forecastCards >= 3 && board.released >= 1;
    out.add(
        (boardOk ? 'PASS' : 'FAIL') + '|Forecast board|' + forecastCards + ' forecasts on the board, ' +
        board.released + ' released, ' + board.next90 + ' due in 90 days'
    );
    fails += boardOk ? 0 : 1;

    List<NXP_MarketController.AwardRow> recompetes = NXP_MarketController.getRecompetes(null, null, 18, null);
    Integer withFollowOn = 0;
    for (NXP_MarketController.AwardRow r : recompetes) {
        withFollowOn += r.followOnKind == 'none' ? 0 : 1;
    }
    Boolean timelineOk = recompetes.size() >= 4 && withFollowOn >= 3;
    out.add(
        (timelineOk ? 'PASS' : 'FAIL') + '|Recompete timeline|' + recompetes.size() +
        ' awards in the 18-month window, ' + withFollowOn + ' with a follow-on'
    );
    fails += timelineOk ? 0 : 1;

    List<NXP_Gov_Vendor__c> meridian = [SELECT Id FROM NXP_Gov_Vendor__c WHERE UEI__c = 'SMPLUEI00004' LIMIT 1];
    if (meridian.isEmpty()) {
        out.add('FAIL|Vendor profile|sample vendor SMPLUEI00004 not found; run load-sample-data again');
        fails++;
    } else {
        NXP_MarketController.VendorProfile vp = NXP_MarketController.getVendorProfile(meridian[0].Id);
        Boolean vendorOk = vp.awardCount == 2 && vp.overlap.size() == 3 && !vp.openNotices.isEmpty();
        out.add(
            (vendorOk ? 'PASS' : 'FAIL') + '|Vendor profile|Meridian Health IT: ' + vp.awardCount + ' awards, ' +
            vp.openNotices.size() + ' open notices where they are the likely incumbent'
        );
        fails += vendorOk ? 0 : 1;

        Boolean wasWatching = vp.watching;
        NXP_MarketController.watch(meridian[0].Id, !wasWatching);
        Boolean flipped = NXP_MarketController.getVendorProfile(meridian[0].Id).watching != wasWatching;
        NXP_MarketController.watch(meridian[0].Id, wasWatching);
        out.add((flipped ? 'PASS' : 'FAIL') + '|Watch|watch and unwatch a vendor (left as it was)');
        fails += flipped ? 0 : 1;
    }
} catch (Exception e) {
    out.add('FAIL|Market screens|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 7d. Agency profile ----------------------------------------------------------------------------
try {
    List<NXP_Gov_Agency__c> vha = [SELECT Id FROM NXP_Gov_Agency__c WHERE Agency_Code__c = '036.3600' LIMIT 1];
    if (vha.isEmpty()) {
        out.add('FAIL|Agency profile|sample agency 036.3600 not found; run load-sample-data again');
        fails++;
    } else {
        NXP_MarketController.AgencyProfile ap = NXP_MarketController.getAgencyProfile(vha[0].Id);
        Boolean agencyOk =
            ap.openNotices >= 2 && ap.coming.size() >= 4 && !ap.incumbents.isEmpty() && !ap.contacts.isEmpty();
        out.add(
            (agencyOk ? 'PASS' : 'FAIL') + '|Agency profile|Veterans Health Administration: ' + ap.openNotices +
            ' open notices, ' + ap.forecasts + ' forecasts, ' + ap.endingSoon + ' awards ending, ' +
            ap.contacts.size() + ' contacts'
        );
        fails += agencyOk ? 0 : 1;
    }
} catch (Exception e) {
    out.add('FAIL|Agency profile|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 7e. Vehicle portfolio (Vehicle Portfolio tab) ------------------------------------------------
try {
    NXP_VehicleController.Portfolio vp = NXP_VehicleController.getVehiclePortfolio();
    Map<String, NXP_VehicleController.VehicleCard> byCode = new Map<String, NXP_VehicleController.VehicleCard>();
    for (NXP_VehicleController.VehicleCard c : vp.held) {
        byCode.put('held:' + c.code, c);
    }
    for (NXP_VehicleController.VehicleCard c : vp.notHeld) {
        byCode.put('lack:' + c.code, c);
    }
    Boolean vehiclesOk =
        byCode.containsKey('held:OASIS+') && byCode.get('held:OASIS+').open >= 1 &&
        byCode.containsKey('held:GSA-MAS-IT') && byCode.get('held:GSA-MAS-IT').open >= 1 &&
        byCode.containsKey('lack:CIO-SP4') && byCode.get('lack:CIO-SP4').open >= 1 &&
        vp.expiringSoon >= 1;
    out.add(
        (vehiclesOk ? 'PASS' : 'FAIL') + '|Vehicle portfolio|' + vp.held.size() + ' held, ' + vp.openOnHeld +
        ' open notices on them, ' + vp.blockedNotices + ' on vehicles not held, ' + vp.expiringSoon +
        ' expiring within 12 months'
    );
    fails += vehiclesOk ? 0 : 1;
} catch (Exception e) {
    out.add('FAIL|Vehicle portfolio|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 7f. eBuy e-mail intake (NXP_Ebuy_Inbox handler, extraction job, Inbound Emails screen) ------
try {
    List<NXP_Inbound_Email__c> ebuy = [
        SELECT Id, Status__c, Status_Detail__c, RFQ_Number__c, Attachment_Count__c, Gov_Notice__r.Notice_Id__c,
            Gov_Notice__r.Contract_Vehicle__r.Vehicle_Code__c
        FROM NXP_Inbound_Email__c
        WHERE Message_Id__c = '<sample-ebuy-rfq9990001@nexus-sample.example>'
        LIMIT 1
    ];
    if (ebuy.isEmpty()) {
        out.add('FAIL|eBuy e-mail|sample e-mail not found; run load-sample-data again');
        fails++;
    } else if (ebuy[0].Status__c == 'Received') {
        out.add('WARN|eBuy e-mail|still waiting for the extraction job; re-run in a minute');
    } else {
        NXP_Inbound_Email__c em = ebuy[0];
        Boolean ebuyOk =
            em.Status__c == 'Ingested' && em.Gov_Notice__r != null &&
            em.Gov_Notice__r.Notice_Id__c == 'EBUY:RFQ9990001' &&
            em.Gov_Notice__r.Contract_Vehicle__r.Vehicle_Code__c == 'GSA-MAS-IT' && em.Attachment_Count__c == 1;
        NXP_EmailLogController.EmailLog log = NXP_EmailLogController.getEmails(null, 'RFQ9990001', 10);
        ebuyOk = ebuyOk && !log.rows.isEmpty();
        out.add(
            (ebuyOk ? 'PASS' : 'FAIL') + '|eBuy e-mail|' + em.Status__c + ', ' + em.RFQ_Number__c + ' -> ' +
            (em.Gov_Notice__r == null ? 'no notice' : em.Gov_Notice__r.Notice_Id__c) +
            (ebuyOk ? '' : ' (' + String.valueOf(em.Status_Detail__c).left(200) + ')')
        );
        fails += ebuyOk ? 0 : 1;
    }
} catch (Exception e) {
    out.add('FAIL|eBuy e-mail|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 7g. eBuy auto-push (saved search "SAMPLE - eBuy RFQs on our vehicles", Fit Threshold 60) -----
try {
    List<NXP_Gov_Notice__c> rfq = [
        SELECT Id, Pushed__c, Pushed_Record_Id__c, Fit_Score__c, Push_Details__c
        FROM NXP_Gov_Notice__c
        WHERE Notice_Id__c = 'EBUY:RFQ9990001'
        LIMIT 1
    ];
    List<NXP_Saved_Search__c> ebuySearch = [
        SELECT Id
        FROM NXP_Saved_Search__c
        WHERE Name = 'SAMPLE - eBuy RFQs on our vehicles' AND OwnerId = :me
        LIMIT 1
    ];
    if (rfq.isEmpty() || ebuySearch.isEmpty()) {
        out.add('WARN|eBuy auto-push|sample eBuy notice or search not there yet; re-run in a minute');
    } else if (rfq[0].Pushed__c) {
        out.add('PASS|eBuy auto-push|EBUY:RFQ9990001 (fit ' + rfq[0].Fit_Score__c + ') pushed to ' + rfq[0].Pushed_Record_Id__c + '; description: ' + String.valueOf(rfq[0].Push_Details__c).left(120));
    } else {
        Integer m = [SELECT COUNT() FROM NXP_Search_Match__c WHERE Gov_Notice__c = :rfq[0].Id AND Saved_Search__c = :ebuySearch[0].Id];
        out.add(
            'WARN|eBuy auto-push|not pushed yet (fit ' + rfq[0].Fit_Score__c + ', ' + m +
            ' match). Matching and auto-push run in the background; re-run in a minute, then check Push Logs.'
        );
    }
} catch (Exception e) {
    out.add('FAIL|eBuy auto-push|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 7h. Document Reader (files on notices -> NXP_Document_Analysis__c) ------------------------------
try {
    List<NXP_Document_Analysis__c> docs = [
        SELECT File_Name__c, Status__c, Status_Detail__c
        FROM NXP_Document_Analysis__c
        WHERE Gov_Notice__r.Notice_Id__c = 'EBUY:RFQ9990001'
    ];
    Boolean readerOn = NXP_DocumentService.isEnabled();
    if (docs.isEmpty()) {
        out.add('FAIL|Document reader|the sample eBuy notice has no document rows (is the eBuy e-mail processed?)');
        fails++;
    } else if (docs[0].Status__c == 'Complete') {
        out.add('PASS|Document reader|' + docs[0].File_Name__c + ' read');
    } else if (docs[0].Status__c == 'Failed') {
        out.add('FAIL|Document reader|' + docs[0].File_Name__c + ': ' + docs[0].Status_Detail__c);
        fails++;
    } else {
        out.add(
            (readerOn ? 'WARN' : 'SKIP') + '|Document reader|' + docs[0].File_Name__c + ' is ' + docs[0].Status__c +
            (readerOn ? '; re-run in a minute' : ' (Document_Analysis_Enabled or AI_Enabled is off)')
        );
    }
} catch (Exception e) {
    out.add('FAIL|Document reader|' + e.getTypeName() + ': ' + e.getMessage());
    fails++;
}

// 7i. Reporting data: GovWin comparison, usage log, reports and dashboards ------------------------
try {
    List<NXP_GovWin_Alert__c> gw = [
        SELECT Id, GovWin_Id__c, Solicitation_Number__c
        FROM NXP_GovWin_Alert__c
        WHERE GovWin_Id__c LIKE 'SAMPLE-GW-%'
    ];
    if (gw.isEmpty()) {
        out.add('FAIL|GovWin comparison|no sample GovWin alerts; run load-sample-data again');
        fails++;
    } else {
        NXP_GovWinCompareBatch.compare(gw);
        Map<String, String> result = new Map<String, String>();
        for (NXP_GovWin_Alert__c a : [SELECT GovWin_Id__c, Result__c FROM NXP_GovWin_Alert__c WHERE Id IN :gw]) {
            result.put(a.GovWin_Id__c, a.Result__c);
        }
        Boolean gwOk =
            result.get('SAMPLE-GW-001') == NXP_GovWinCompareBatch.CAUGHT &&
            result.get('SAMPLE-GW-005') == NXP_GovWinCompareBatch.MISSING;
        out.add((gwOk ? 'PASS' : 'FAIL') + '|GovWin comparison|' + JSON.serialize(result));
        fails += gwOk ? 0 : 1;
    }
    NXP_UsageService.record('Match Inbox');
    Integer usage = [SELECT COUNT() FROM NXP_Usage__c WHERE User__c = :me AND Week__c = THIS_WEEK];
    out.add((usage == 1 ? 'PASS' : 'FAIL') + '|Usage log|' + usage + ' row for you this week');
    fails += usage == 1 ? 0 : 1;
    Integer reports = [SELECT COUNT() FROM Report WHERE DeveloperName LIKE 'NXP_%'];
    Integer dashboards = [SELECT COUNT() FROM Dashboard WHERE DeveloperName LIKE 'NXP_%'];
    if (reports == 0 && dashboards == 0) {
        out.add('WARN|Reports and dashboards|none found; deploy packages/nxp-analytics');
    } else {
        Boolean analyticsOk = reports >= 27 && dashboards == 3;
        out.add((analyticsOk ? 'PASS' : 'FAIL') + '|Reports and dashboards|' + reports + ' reports, ' + dashboards + ' dashboards');
        fails += analyticsOk ? 0 : 1;
    }
} catch (Exception e) {
    out.add('FAIL|Reporting data|' + e.getTypeName() + ': ' + e.getMessage());
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
