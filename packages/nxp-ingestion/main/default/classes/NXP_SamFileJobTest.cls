@IsTest
private class NXP_SamFileJobTest {
    private static final String SMALL = 'https://sam.gov/api/prod/opps/v3/opportunities/resources/files/aaa111/download?api_key=null&token=';
    private static final String BIG = 'https://sam.gov/api/prod/opps/v3/opportunities/resources/files/bbb222/download?api_key=null&token=';

    /** sam.gov redirects to storage; storage answers a Range request with the size, then the file. */
    private class StorageMock implements HttpCalloutMock {
        public Integer calls = 0;
        public HttpResponse respond(HttpRequest req) {
            calls++;
            HttpResponse res = new HttpResponse();
            String url = req.getEndpoint();
            Boolean big = url.contains('bbb222');
            if (url.startsWith('callout:NXP_SAM_Files')) {
                res.setStatusCode(303);
                res.setHeader('Location', 'https://s3.amazonaws.com/files/' + (big ? 'big' : 'small') + '?sig=1');
            } else if (req.getHeader('Range') == 'bytes=0-0') {
                res.setStatusCode(206);
                res.setHeader('Content-Range', 'bytes 0-0/' + (url.contains('/big') ? '99999999' : '15'));
                res.setHeader(
                    'Content-Disposition',
                    'attachment; filename="' + (url.contains('/big') ? 'Drawings.pdf' : 'Statement of Work.pdf') + '"'
                );
            } else {
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 sample'));
            }
            return res;
        }
    }

    private static NXP_Gov_Notice__c notice(String key, Decimal fit, Boolean requested) {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = key,
            Title__c = 'Files ' + key,
            Status__c = 'Active',
            Resource_Links__c = SMALL + '\n' + BIG,
            Files_Pending__c = true,
            Files_Requested__c = requested
        );
        insert n;
        if (fit != null) {
            update new NXP_Gov_Notice__c(Id = n.Id, Fit_Score__c = fit);
        }
        return n;
    }

    @IsTest
    static void downloadsOneFilePerRun() {
        NXP_Gov_Notice__c n = notice('FILES-1', null, true);
        Test.setMock(HttpCalloutMock.class, new StorageMock());
        Test.startTest();
        System.enqueueJob(new NXP_SamFileJob(new List<Id>{ n.Id }));
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :n.Id
        ];
        System.assertEquals(1, links.size());
        System.assertEquals('Statement of Work', links[0].ContentDocument.Title);
        n = [
            SELECT Files_Pending__c, Files_Requested__c, Files_Fetched__c, Files_Status__c
            FROM NXP_Gov_Notice__c
            WHERE Id = :n.Id
        ];
        System.assertEquals(true, n.Files_Pending__c, 'One more file to go');
        System.assertEquals(true, n.Files_Requested__c);
        System.assert(n.Files_Fetched__c.contains('aaa111') && !n.Files_Fetched__c.contains('bbb222'));
        System.assert(n.Files_Status__c.contains('1 of 2'), n.Files_Status__c);
    }

    @IsTest
    static void skipsFilesThatAreTooLargeAndFinishes() {
        NXP_Gov_Notice__c n = notice('FILES-2', null, true);
        update new NXP_Gov_Notice__c(Id = n.Id, Files_Fetched__c = SMALL);
        Test.setMock(HttpCalloutMock.class, new StorageMock());
        Test.startTest();
        System.enqueueJob(new NXP_SamFileJob(new List<Id>{ n.Id }));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :n.Id]);
        n = [
            SELECT Files_Pending__c, Files_Requested__c, Files_Fetched__c, Files_Status__c
            FROM NXP_Gov_Notice__c
            WHERE Id = :n.Id
        ];
        System.assertEquals(false, n.Files_Pending__c);
        System.assertEquals(false, n.Files_Requested__c);
        System.assert(n.Files_Fetched__c.contains('bbb222'));
        System.assert(n.Files_Status__c.contains('Files_Max_MB'), n.Files_Status__c);
        System.assert(n.Files_Status__c.contains('2 of 2'), n.Files_Status__c);
    }

    @IsTest
    static void picksRequestedAndHighFitNotices() {
        NXP_Gov_Notice__c high = notice('FILES-HIGH', 85, false);
        NXP_Gov_Notice__c low = notice('FILES-LOW', 10, false);
        NXP_Gov_Notice__c asked = notice('FILES-ASKED', 10, true);
        Set<Id> ids = new Set<Id>(NXP_SamFileJob.pendingIds());
        System.assert(ids.contains(high.Id));
        System.assert(ids.contains(asked.Id));
        System.assert(!ids.contains(low.Id));

        NXP_Settings.setForTest('Files_Auto_Download', 'false');
        ids = new Set<Id>(NXP_SamFileJob.pendingIds());
        System.assert(!ids.contains(high.Id), 'Automatic downloads off');
        System.assert(ids.contains(asked.Id));
    }

    @IsTest
    static void fileNamesAndSizes() {
        System.assertEquals('SOW.pdf', NXP_SamFileJob.fileName('attachment; filename="SOW.pdf"', SMALL));
        System.assertEquals('A B.pdf', NXP_SamFileJob.fileName('attachment; filename*=UTF-8\'\'A%20B.pdf', SMALL));
        System.assertEquals('SAM.gov file aaa111', NXP_SamFileJob.fileName(null, SMALL));
        System.assertEquals(123456, NXP_SamFileJob.totalSize('bytes 0-0/123456'));
        System.assertEquals(null, NXP_SamFileJob.totalSize('bytes 0-0/*'));
    }

    @IsTest
    static void connectorKeepsTheFileLinks() {
        NXP_IngestRecord rec = NXP_SamOpportunityConnector.toRecord(
            'SAM_Opportunities',
            JSON.deserializeUntyped(
                '{"noticeId":"L1","title":"Links","type":"Solicitation","active":"Yes","resourceLinks":["' +
                    SMALL +
                    '","not a link"]}'
            )
        );
        System.assertEquals(SMALL, rec.values.get('Resource_Links__c'));
        System.assertEquals(true, rec.values.get('Files_Pending__c'));
    }
}
