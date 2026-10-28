@IsTest
private class NXP_IngestionTest {
    public static final String SAM_PAGE =
        '{"totalRecords":2,"limit":1000,"offset":0,"opportunitiesData":[' +
        '{"noticeId":"abc123","title":"Zero Trust Architecture Engineering Support","solicitationNumber":"70B03C27R00000012",' +
        '"fullParentPathName":"HOMELAND SECURITY, DEPARTMENT OF.US CUSTOMS AND BORDER PROTECTION","fullParentPathCode":"070.7014",' +
        '"postedDate":"2026-10-20","type":"Solicitation","archiveDate":"2026-12-31",' +
        '"typeOfSetAsideDescription":"Total Small Business Set-Aside (FAR 19.5)","responseDeadLine":"2026-11-09T14:00:00-05:00",' +
        '"naicsCode":"541512","classificationCode":"DA01","active":"Yes",' +
        '"pointOfContact":[{"fullName":"Jane Doe","email":"jane.doe@example.gov","phone":"555-0100","type":"primary"}],' +
        '"description":"https://api.sam.gov/prod/opportunities/v1/noticedesc?noticeid=abc123",' +
        '"uiLink":"https://sam.gov/opp/abc123/view","placeOfPerformance":{"city":{"name":"Washington"},"state":{"code":"DC"}}},' +
        '{"noticeId":"def456","title":"Cloud Migration and Managed Services","solicitationNumber":"W52P1J-27-R-0001",' +
        '"fullParentPathName":"DEPT OF DEFENSE.DEPT OF THE ARMY","fullParentPathCode":"097.2100","postedDate":"2026-10-21",' +
        '"type":"Sources Sought","typeOfSetAsideDescription":"8(a) Set-Aside","naicsCode":"541519","active":"Yes"}]}';

    public class Router implements HttpCalloutMock {
        public Integer status = 200;
        public HttpResponse respond(HttpRequest req) {
            String url = req.getEndpoint();
            String body = '{}';
            if (url.contains('/opportunities/v2/search')) {
                body = SAM_PAGE;
            } else if (url.contains('noticedesc')) {
                body = '{"description":"<p>Hello <b>world</b> &amp; friends</p>"}';
            } else if (url.contains('spending_by_award')) {
                body =
                    '{"results":[{"Award ID":"HSBP1019C00001","Recipient Name":"Acme Federal LLC","Recipient UEI":"ABCDEFGHJK12",' +
                    '"Award Amount":12500000.5,"Start Date":"2022-01-01","End Date":"2027-03-31","Awarding Agency":"Department of Homeland Security",' +
                    '"Awarding Sub Agency":"U.S. Customs and Border Protection","Description":"CYBER OPERATIONS SUPPORT"}],"page_metadata":{"hasNext":false}}';
            } else if (url.contains('entity-information')) {
                body =
                    '{"entityData":[{"entityRegistration":{"legalBusinessName":"Acme Federal LLC","cageCode":"1ABC2"},' +
                    '"coreData":{"physicalAddress":{"city":"Reston","stateOrProvinceCode":"VA"},' +
                    '"businessTypes":{"sbaBusinessTypeList":[{"sbaBusinessTypeDesc":"8(a) Program Participant"}]}}}]}';
            } else if (url.contains('forecasts')) {
                body =
                    '{"results":[{"id":"FC-1","title":"Zero Trust Architecture Engineering","naics":"541512","estimatedValue":"20000000",' +
                    '"estimatedSolicitationDate":"2026-10-01","fiscalYear":"2027","agency":"HOMELAND SECURITY, DEPARTMENT OF.US CUSTOMS AND BORDER PROTECTION"}]}';
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    private static NXP_Feed_Config__mdt samConfig() {
        return NXP_ConnectorSupport.config('SAM_Opportunities');
    }

    private static List<NXP_IngestRecord> samRecords() {
        NXP_FeedConnector c = NXP_ConnectorSupport.connectorFor(samConfig());
        return c.fetchPage(c.initialCheckpoint(null)).records;
    }

    @IsTest
    static void samPageIsIngestedWithAgenciesContactsAndVersions() {
        Test.setMock(HttpCalloutMock.class, new Router());
        Test.startTest();
        NXP_FeedConnector c = NXP_ConnectorSupport.connectorFor(samConfig());
        NXP_FeedPage page = c.fetchPage(c.initialCheckpoint(Datetime.now().addDays(-1)));
        NXP_IngestionService.Result r = NXP_IngestionService.ingest(page.records);
        Test.stopTest();

        System.assertEquals(2, r.created, r.errors);
        System.assertEquals(false, page.hasMore);
        NXP_Gov_Notice__c n = [
            SELECT
                Notice_Type__c,
                Agency__c,
                Agency_Path__c,
                Office__c,
                Place_Of_Performance__c,
                Needs_Description__c,
                Response_Due__c,
                Version_Count__c,
                Content_Hash__c,
                Source_Lineage__c
            FROM NXP_Gov_Notice__c
            WHERE Notice_Id__c = 'abc123'
        ];
        System.assertEquals('Solicitation', n.Notice_Type__c);
        System.assertEquals('Washington, DC', n.Place_Of_Performance__c);
        System.assert(n.Needs_Description__c);
        System.assertNotEquals(null, n.Agency__c);
        System.assert(n.Agency_Path__c.contains('›'), n.Agency_Path__c);
        System.assertEquals(1, n.Version_Count__c);
        System.assertEquals(4, [SELECT COUNT() FROM NXP_Gov_Agency__c]);
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Gov_Contact__c]);
        System.assertEquals(2, [SELECT COUNT() FROM NXP_Notice_Version__c WHERE Change_Type__c = 'Original']);
    }

    @IsTest
    static void amendmentMakesNewVersionAndRepeatIsUnchanged() {
        Test.setMock(HttpCalloutMock.class, new Router());
        Test.startTest();
        List<NXP_IngestRecord> first = samRecords();
        List<NXP_IngestRecord> amended = samRecords();
        NXP_IngestionService.ingest(first);
        amended[0].values.put('Response_Due__c', Datetime.newInstanceGmt(2026, 11, 23, 19, 0, 0));
        amended[0].values.put('Set_Aside__c', '8(a) Set-Aside');
        NXP_IngestionService.Result r2 = NXP_IngestionService.ingest(amended);
        NXP_IngestionService.Result r3 = NXP_IngestionService.ingest(amended);
        Test.stopTest();

        System.assertEquals(1, r2.updated, r2.errors);
        System.assertEquals(1, r2.unchanged);
        System.assertEquals(2, r3.unchanged);
        NXP_Gov_Notice__c n = [
            SELECT Version_Count__c, Last_Change_Type__c
            FROM NXP_Gov_Notice__c
            WHERE Notice_Id__c = 'abc123'
        ];
        System.assertEquals(2, n.Version_Count__c);
        System.assert(n.Last_Change_Type__c.contains('Due date'), n.Last_Change_Type__c);
        System.assert(n.Last_Change_Type__c.contains('Set-aside'), n.Last_Change_Type__c);
        NXP_Notice_Version__c v = [SELECT Diff_Summary__c FROM NXP_Notice_Version__c WHERE Version_Number__c = 2];
        System.assert(v.Diff_Summary__c.contains('→'), v.Diff_Summary__c);
    }

    @IsTest
    static void sameSolicitationFromAnotherSourceMerges() {
        Test.setMock(HttpCalloutMock.class, new Router());
        Test.startTest();
        NXP_IngestionService.ingest(samRecords());
        NXP_IngestRecord other = new NXP_IngestRecord(NXP_IngestRecord.TYPE_NOTICE, 'PARTNER:9', 'REST_Partner');
        other.put('Title__c', 'Zero Trust Architecture Engineering Support');
        other.put('Solicitation_Number__c', '70B03C27R00000012');
        other.put('Estimated_Value__c', 25000000);
        NXP_IngestionService.Result r = NXP_IngestionService.ingest(new List<NXP_IngestRecord>{ other });
        Test.stopTest();
        System.assertEquals(1, r.updated, r.errors);
        System.assertEquals(2, [SELECT COUNT() FROM NXP_Gov_Notice__c]);
        NXP_Gov_Notice__c n = [
            SELECT Notice_Id__c, Source_Lineage__c, Estimated_Value__c
            FROM NXP_Gov_Notice__c
            WHERE Solicitation_Number__c = '70B03C27R00000012'
        ];
        System.assertEquals('abc123', n.Notice_Id__c);
        System.assert(n.Source_Lineage__c.contains('REST_Partner'));
        System.assertEquals(25000000, n.Estimated_Value__c);
    }

    @IsTest
    static void invalidRecordsAreRejected() {
        NXP_IngestRecord noKey = new NXP_IngestRecord(NXP_IngestRecord.TYPE_NOTICE, null, 'X');
        NXP_IngestRecord badField = new NXP_IngestRecord(NXP_IngestRecord.TYPE_NOTICE, 'K1', 'X');
        badField.values.put('Not_A_Field__c', 'x');
        NXP_IngestRecord badPicklist = new NXP_IngestRecord(NXP_IngestRecord.TYPE_NOTICE, 'K2', 'X');
        badPicklist.put('Title__c', 'T');
        badPicklist.put('Status__c', 'Nonsense');
        NXP_IngestionService.Result r = NXP_IngestionService.ingest(
            new List<NXP_IngestRecord>{ noKey, badField, badPicklist }
        );
        System.assertEquals(3, r.rejected, r.results);
        System.assertEquals(0, NXP_IngestionService.ingest(null).read);
    }

    @IsTest
    static void queueablePipelineRun() {
        Test.setMock(HttpCalloutMock.class, new Router());
        NXP_Feed_Run__c run = NXP_FeedRunService.start('SAM_Opportunities', NXP_FeedRunService.CH_PIPELINE, null);
        Test.startTest();
        System.enqueueJob(new NXP_FeedFetchJob('SAM_Opportunities', run.Id, 0));
        Test.stopTest();
        run = [SELECT Status__c, Records_Created__c, Checkpoint__c FROM NXP_Feed_Run__c WHERE Id = :run.Id];
        System.assertEquals('Succeeded', run.Status__c);
        System.assertEquals(2, run.Records_Created__c);
        System.assertNotEquals(null, NXP_FeedRunService.lastSuccess('SAM_Opportunities'));
        System.assert(!NXP_FeedRunService.isRunning('SAM_Opportunities'));
    }

    @IsTest
    static void batchChannelRun() {
        Test.setMock(HttpCalloutMock.class, new Router());
        NXP_Settings.setForTest('Batch_Max_Pages', '1');
        Test.startTest();
        Database.executeBatch(new NXP_FeedFetchBatch('SAM_Backfill', null), 1);
        Test.stopTest();
        NXP_Feed_Run__c run = [SELECT Status__c, Channel__c, Records_Created__c FROM NXP_Feed_Run__c LIMIT 1];
        System.assertEquals('Scheduled Batch', run.Channel__c);
        System.assertEquals('Succeeded', run.Status__c);
        System.assertEquals(2, run.Records_Created__c);
    }

    @IsTest
    static void failedBatchMarksRunFailed() {
        Router failing = new Router();
        failing.status = 500;
        Test.setMock(HttpCalloutMock.class, failing);
        NXP_Settings.setForTest('Batch_Max_Pages', '1');
        NXP_Settings.setForTest('Http_Max_Attempts', '1');
        NXP_Feed_Run__c run = NXP_FeedRunService.start('SAM_Backfill', NXP_FeedRunService.CH_BATCH, null);
        Test.startTest();
        Database.executeBatch(new NXP_FeedFetchBatch('SAM_Backfill', run.Id), 1);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Log__c WHERE Level__c = 'ERROR']);
        NXP_FeedRunService.fail(run.Id, 'manual');
        System.assertEquals('Failed', [SELECT Status__c FROM NXP_Feed_Run__c WHERE Id = :run.Id].Status__c);
    }

    @IsTest
    static void schedulerDecidesAndStarts() {
        Test.setMock(HttpCalloutMock.class, new Router());
        Test.startTest();
        System.assert(NXP_FeedScheduler.isDue(samConfig()));
        Id runId = NXP_FeedScheduler.runNow('SAM_Opportunities');
        try {
            NXP_FeedScheduler.runNow('SAM_Opportunities');
            System.assert(false, 'Expected already running');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('already running'));
        }
        // Shipped feed configs are inactive until env-config switches them on.
        NXP_FeedScheduler.runDueFeeds();
        Id jobId = NXP_FeedScheduler.scheduleHourly();
        System.abortJob(jobId);
        Test.stopTest();
        System.assertNotEquals(null, runId);
        System.assert(!NXP_FeedScheduler.isDue(samConfig()));
    }

    @IsTest
    static void restIngestionCreatesUpdatesAndReplays() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/nxp/v1/notices';
        req.httpMethod = 'POST';
        req.headers.put('Idempotency-Key', 'key-1');
        req.requestBody = Blob.valueOf(
            '{"source":"partner","records":[{"sourceId":"9","title":"Network Segmentation Pilot","noticeType":"sources sought",' +
                '"agencyPath":"Homeland Security > Customs and Border Protection","naics":"541512","estimatedValue":"1,500,000",' +
                '"responseDue":"2026-11-20T17:00:00Z","postedDate":"2026-10-25","contacts":[{"name":"Sam Lee","email":"sam@example.gov","role":"Program Manager"}]},' +
                '{"sourceId":"10"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();
        NXP_NoticeIngestResource.ingest();
        System.assertEquals(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(1, body.get('created'));
        System.assertEquals(1, body.get('rejected'));
        System.assertEquals(
            'Sources Sought',
            [SELECT Notice_Type__c FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'PARTNER:9'].Notice_Type__c
        );

        RestContext.response = new RestResponse();
        NXP_NoticeIngestResource.ingest();
        System.assertEquals('true', RestContext.response.headers.get('Idempotent-Replay'));

        NXP_Feed_Run__c run = [SELECT Id FROM NXP_Feed_Run__c WHERE Channel__c = 'Apex REST' LIMIT 1];
        RestRequest get = new RestRequest();
        get.requestURI = '/services/apexrest/nxp/v1/runs/' + run.Id;
        RestContext.request = get;
        RestContext.response = new RestResponse();
        NXP_FeedRunResource.getRun();
        System.assertEquals(200, RestContext.response.statusCode);
        get.requestURI = '/services/apexrest/nxp/v1/runs/a0X000000000000';
        RestContext.response = new RestResponse();
        NXP_FeedRunResource.getRun();
        System.assertEquals(404, RestContext.response.statusCode);
    }

    @IsTest
    static void restRejectsBadRequestsAndLinksTaskOrders() {
        insert new NXP_Contract_Vehicle__c(Name = 'OASIS+', Vehicle_Code__c = 'OASIS+');
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('not json');
        NXP_NoticeIngestResource.ingest();
        System.assertEquals(400, RestContext.response.statusCode);

        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('{"source":"bad source!","records":[{}]}');
        NXP_NoticeIngestResource.ingest();
        System.assertEquals(400, RestContext.response.statusCode);

        NXP_Settings.setForTest('Rest_Max_Records', '1');
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(
            '{"source":"relay","records":[{"sourceId":"1","title":"a"},{"sourceId":"2","title":"b"}]}'
        );
        NXP_NoticeIngestResource.ingest();
        System.assertEquals(413, RestContext.response.statusCode);

        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(
            '{"source":"relay","records":[{"sourceId":"TO-1","title":"Help desk task order","vehicleCode":"oasis+"}]}'
        );
        NXP_TaskOrderIngestResource.ingest();
        System.assertEquals(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        NXP_Gov_Notice__c n = [
            SELECT Notice_Type__c, Contract_Vehicle__c
            FROM NXP_Gov_Notice__c
            WHERE Notice_Id__c = 'RELAY:TO-1'
        ];
        System.assertEquals('Task Order', n.Notice_Type__c);
        System.assertNotEquals(null, n.Contract_Vehicle__c);
    }

    @IsTest
    static void enrichBatchFetchesDescriptionText() {
        Test.setMock(HttpCalloutMock.class, new Router());
        NXP_IngestionService.ingest(samRecords());
        Test.startTest();
        Database.executeBatch(new NXP_NoticeEnrichBatch(), 20);
        Test.stopTest();
        NXP_Gov_Notice__c n = [
            SELECT Description__c, Needs_Description__c, Content_Hash__c
            FROM NXP_Gov_Notice__c
            WHERE Notice_Id__c = 'abc123'
        ];
        System.assertEquals(false, n.Needs_Description__c);
        System.assert(n.Description__c.contains('Hello world & friends'), n.Description__c);
    }

    @IsTest
    static void awardsVendorsAndForecasts() {
        insert new NXP_Company_Profile__c(Name = 'P', Active__c = true, NAICS_Codes__c = '5415*');
        insert new NXP_Gov_Vendor__c(Name = 'Stale', UEI__c = 'ABCDEFGHJK12');
        Test.setMock(HttpCalloutMock.class, new Router());
        Test.startTest();
        // All callouts first: Apex cannot call out after uncommitted DML in the same transaction.
        Map<String, NXP_FeedPage> pages = new Map<String, NXP_FeedPage>();
        for (String feed : new List<String>{ 'USAspending_Awards', 'SAM_Entity', 'Agency_Forecasts' }) {
            NXP_FeedConnector c = NXP_ConnectorSupport.connectorFor(NXP_ConnectorSupport.config(feed));
            pages.put(feed, c.fetchPage(c.initialCheckpoint(null)));
        }
        NXP_IngestRecord one = NXP_SamEntityConnector.lookup('ABCDEFGHJK12');
        for (String feed : pages.keySet()) {
            NXP_IngestionService.Result r = NXP_IngestionService.ingest(pages.get(feed).records);
            System.assertEquals(0, r.rejected, feed + ': ' + r.errors);
        }
        Test.stopTest();
        System.assertEquals('1ABC2', one.values.get('CAGE_Code__c'));
        NXP_Award_Summary__c a = [
            SELECT Vendor__c, Obligated_Amount__c, Period_End__c, Agency__c
            FROM NXP_Award_Summary__c
        ];
        System.assertNotEquals(null, a.Vendor__c);
        System.assertNotEquals(null, a.Agency__c);
        System.assertEquals(Date.newInstance(2027, 3, 31), a.Period_End__c);
        NXP_Gov_Vendor__c v = [SELECT Name, CAGE_Code__c, Business_Size__c FROM NXP_Gov_Vendor__c];
        System.assertEquals('1ABC2', v.CAGE_Code__c);
        System.assertEquals('Small', v.Business_Size__c);
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Gov_Forecast__c WHERE Fiscal_Year__c = '2027']);
    }

    @IsTest
    static void feedConsoleController() {
        NXP_Feed_Run__c run = NXP_FeedRunService.start('REST_partner', NXP_FeedRunService.CH_REST, 'tester');
        NXP_IngestionService.Result r = new NXP_IngestionService.Result();
        r.read = 1;
        r.rejected = 1;
        r.errors.add('K: bad');
        NXP_FeedRunService.recordPage(run.Id, r, new Map<String, Object>{ 'offset' => 1 });
        NXP_FeedRunService.finish(run.Id, 'Succeeded');
        System.assertEquals('Partial', [SELECT Status__c FROM NXP_Feed_Run__c WHERE Id = :run.Id].Status__c);

        NXP_FeedConsoleController.Console c = NXP_FeedConsoleController.getConsole();
        System.assert(c.feeds.size() >= 1);
        System.assert(NXP_FeedConsoleController.getRunErrors(run.Id).contains('bad'));
        try {
            NXP_FeedConsoleController.runNow('SAM_Opportunities');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void helpers() {
        System.assertEquals('a\n\nb', NXP_ConnectorSupport.htmlToText('<p>a</p><p>b</p>').replace(' ', ''));
        System.assertEquals('2', NXP_ConnectorSupport.parseParams('a=1&b=2&bad').get('b'));
        System.assertEquals('Pre-solicitation', NXP_SamOpportunityConnector.normalizeType('Presolicitation'));
        System.assertEquals('Other', NXP_SamOpportunityConnector.normalizeType('Justification'));
        System.assertEquals('Other', NXP_IngestionService.normalizeNoticeType(null));
        System.assert(
            NXP_IngestionService.similarity('Zero Trust Architecture Engineering', 'Zero Trust Architecture Support') >=
            0.5
        );
        System.assertEquals(2, NXP_AgencyResolver.splitNames('A › B').size());
        System.assertEquals(
            'Customs and Border Protection',
            NXP_AgencyResolver.titleCase('CUSTOMS AND BORDER PROTECTION')
        );
        System.assertEquals('DHS', NXP_AgencyResolver.titleCase('DHS'));
        try {
            NXP_ConnectorSupport.config('Nope');
            System.assert(false);
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Nope'));
        }
    }
}
