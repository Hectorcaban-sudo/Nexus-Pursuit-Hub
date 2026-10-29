@IsTest
private class NXP_CoreTest {
    private class OkMock implements HttpCalloutMock {
        Integer status;
        OkMock(Integer status) {
            this.status = status;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    private static NXP_Company_Profile__c profile() {
        return new NXP_Company_Profile__c(
            Name = 'Test profile',
            Active__c = true,
            NAICS_Codes__c = '541512, 5415*',
            PSC_Codes__c = 'DA01',
            Set_Asides__c = 'Small Business; 8(a)',
            Target_Agency_Codes__c = 'Homeland Security',
            Keywords__c = 'cyber, zero trust, identity',
            Min_Value__c = 1000000,
            Max_Value__c = 50000000
        );
    }

    private static List<NXP_Fit_Rule__mdt> rules() {
        return new List<NXP_Fit_Rule__mdt>{
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'NAICS', Weight__c = 30, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'Agency', Weight__c = 20, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'Set-Aside', Weight__c = 15, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'Keyword', Weight__c = 20, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'Value Range', Weight__c = 15, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'PSC', Weight__c = 0, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'Vehicle', Weight__c = 0, Active__c = true)
        };
    }

    private static NXP_Gov_Notice__c notice() {
        return new NXP_Gov_Notice__c(
            Notice_Id__c = 'T-1',
            Title__c = 'Zero Trust and identity cyber engineering support',
            Agency_Path__c = 'Homeland Security › Customs and Border Protection',
            NAICS_Code__c = '541512',
            PSC_Code__c = 'DA01',
            Set_Aside__c = 'Total Small Business Set-Aside',
            Estimated_Value__c = 20000000,
            Status__c = 'Active'
        );
    }

    @IsTest
    static void textHelpers() {
        System.assertEquals('abc', NXP_Text.truncate('abcdef', 3));
        System.assertEquals(null, NXP_Text.truncate(null, 3));
        System.assertEquals(3, NXP_Text.splitList('a, b;\nc').size());
        System.assert(NXP_Text.matchesCodeList('541519', new List<String>{ '5415*' }));
        System.assert(!NXP_Text.matchesCodeList('541519', new List<String>{ '541512' }));
        System.assert(NXP_Text.containsAny('Homeland Security', new List<String>{ 'homeland' }));
        System.assertEquals(64, NXP_Text.sha256('x').length());
        System.assertEquals('2026-01-02', NXP_Text.valueToString(Date.newInstance(2026, 1, 2)));
        System.assert(NXP_Text.valueToString(Datetime.newInstanceGmt(2026, 1, 2, 3, 4, 5)).endsWith('Z'));
        System.assertEquals(2, NXP_Text.lowerSet(new List<String>{ 'A', 'a', 'b' }).size());
    }

    @IsTest
    static void jsonHelpers() {
        Object root = JSON.deserializeUntyped('{"a":{"b":[{"c":"x"}]},"n":"1,234.5"}');
        System.assertEquals('x', NXP_Json.getString(root, 'a.b[0].c'));
        System.assertEquals(null, NXP_Json.getPath(root, 'a.z.q'));
        System.assertEquals(1234.5, (Decimal) NXP_Json.coerce(NXP_Json.getPath(root, 'n'), 'Number'));
        System.assertEquals(Date.newInstance(2026, 11, 9), NXP_Json.toDate('11/09/2026'));
        System.assertEquals(Date.newInstance(2026, 11, 9), NXP_Json.toDate('2026-11-09T10:00:00Z'));
        System.assertNotEquals(null, NXP_Json.toDateTime('2026-11-09T14:00:00-05:00'));
        System.assertNotEquals(null, NXP_Json.toDateTime('2026-11-09'));
        System.assertEquals('ABC', NXP_Json.coerce('abc', 'Upper'));
        System.assertEquals(null, NXP_Json.coerce(' ', 'None'));
        System.assertEquals(null, NXP_Json.toDate('not a date'));
    }

    @IsTest
    static void settingsAndTokens() {
        NXP_Settings.setForTest('X_Int', '7');
        NXP_Settings.setForTest('X_Bool', 'true');
        NXP_Settings.setForTest('X_Bad', 'oops');
        System.assertEquals(7, NXP_Settings.getInteger('X_Int', 1));
        System.assertEquals(1, NXP_Settings.getInteger('X_Bad', 1));
        System.assertEquals(2.5, NXP_Settings.getDecimal('X_Missing', 2.5));
        System.assert(NXP_Settings.getBoolean('X_Bool', false));
        System.assert(!NXP_Settings.isBypassed('Nothing'));

        String token = NXP_PreviewToken.issue('push', 'abc');
        System.assert(NXP_PreviewToken.verify('push', 'abc', token));
        System.assert(!NXP_PreviewToken.verify('push', 'xyz', token));
        System.assert(!NXP_PreviewToken.verify('push', 'abc', null));
    }

    @IsTest
    static void loggerWritesBufferedEntries() {
        NXP_Logger.info('Test', 'hello');
        NXP_Logger.warn('Test', 'careful');
        NXP_Logger.error('Test', 'bad');
        NXP_Logger.error('Test', new IllegalArgumentException('boom'));
        System.assertEquals(4, NXP_Logger.pending().size());
        NXP_Logger.flush();
        System.assertEquals(4, [SELECT COUNT() FROM NXP_Log__c]);
        NXP_Logger.flush();
    }

    @IsTest
    static void fitScoreAndTrigger() {
        NXP_FitScoreService.profileOverride = profile();
        NXP_FitScoreService.rulesOverride = rules();
        NXP_Gov_Notice__c n = notice();
        insert n;
        n = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byId(n.Id);
        System.assertEquals(100, n.Fit_Score__c, n.Fit_Breakdown__c);
        System.assertEquals(n.Title__c.left(80), n.Name);
        System.assert(NXP_FitScoreService.explain(n).contains('Fit score'));

        n.NAICS_Code__c = '236220';
        n.Estimated_Value__c = null;
        update n;
        n = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byId(n.Id);
        System.assertEquals(63, n.Fit_Score__c, n.Fit_Breakdown__c);

        n.Set_Aside__c = 'None';
        n.Estimated_Value__c = 999;
        update n;
        n = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byId(n.Id);
        System.assert(n.Fit_Score__c < 63);
        System.assert(NXP_FitScoreService.explain(new NXP_Gov_Notice__c()).contains('not been scored'));
    }

    @IsTest
    static void triggerBypassAndSelectors() {
        NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
        NXP_Gov_Notice__c n = notice();
        n.Name = 'Manual';
        n.Solicitation_Number__c = 'SOL-1';
        insert n;
        NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
        System.assert(!NXP_TriggerHandler.isBypassed('NXP_GovNoticeTriggerHandler'));
        NXP_GovNoticeSelector s = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE);
        System.assertEquals('Manual', s.byId(n.Id).Name);
        System.assertEquals(1, s.byNoticeIds(new Set<String>{ 'T-1' }).size());
        System.assertEquals(1, s.bySolicitationNumbers(new Set<String>{ 'SOL-1' }).size());
        System.assertEquals(
            1,
            s.whereClause('NAICS_Code__c = :c', new Map<String, Object>{ 'c' => '541512' }, null, 10).size()
        );
        System.assertEquals(1, s.whereClause(null, null, 'Name', 10).size());
    }

    @IsTest
    static void httpClientRetriesThenFails() {
        // Plain endpoints: nxp-core is versioned without the ingestion package's Named Credentials.
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('https://example.com/x');
        Test.setMock(HttpCalloutMock.class, new OkMock(200));
        Test.startTest();
        HttpResponse ok = new NXP_HttpClient().send(req);
        System.assertEquals(200, ok.getStatusCode());
        System.assertEquals('?a=1+2', NXP_HttpClient.buildQuery(new Map<String, String>{ 'a' => '1 2', 'b' => null }));
        System.assertEquals('', NXP_HttpClient.buildQuery(null));
        Test.setMock(HttpCalloutMock.class, new OkMock(503));
        try {
            new NXP_HttpClient().send(req);
            System.assert(false, 'Expected failure');
        } catch (NXP_HttpClient.CalloutFailureException e) {
            System.assertEquals(503, e.statusCode);
        }
        Test.stopTest();
    }
}
