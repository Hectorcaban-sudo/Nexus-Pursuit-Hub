@IsTest
private class NXP_NoticeControllerTest {
    @IsTest
    static void detailBringsTogetherBreakdownVersionsContactsAndFollow() {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'EXP-1',
            Title__c = 'Zero Trust support',
            Status__c = 'Active',
            Source_Lineage__c = '["SAM_Opportunities","REST_partner"]',
            Fit_Breakdown__c = '[{"rule":"NAICS","weight":30,"points":30,"reason":"In profile"}]'
        );
        insert n;
        insert new NXP_Notice_Version__c(
            Gov_Notice__c = n.Id,
            Version_Number__c = 1,
            Change_Type__c = 'Original',
            Diff_Summary__c = 'First version received.'
        );
        insert new NXP_Gov_Contact__c(
            Name = 'Jane Doe',
            Gov_Notice__c = n.Id,
            Email__c = 'jane@example.gov',
            Role__c = 'Contracting Officer',
            Contact_Key__c = 'EXP-1|jane'
        );
        NXP_SearchController.followNotice(n.Id, true);

        NXP_NoticeController.Detail d = NXP_NoticeController.getDetail(n.Id);
        System.assertEquals('EXP-1', d.notice.Notice_Id__c);
        System.assertEquals(1, d.breakdown.size());
        System.assertEquals(2, d.sources.size());
        System.assertEquals(1, d.versions.size());
        System.assertEquals(1, d.contacts.size());
        System.assert(d.following);
        System.assertEquals(0, d.pushLogs.size());

        delete n;
        try {
            NXP_NoticeController.getDetail(n.Id);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    private class DescriptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"description":"<p>Help desk <b>tier 1</b> support</p>"}');
            return res;
        }
    }

    @IsTest
    static void loadDescriptionFetchesTextOnce() {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'EXP-DESC',
            Title__c = 'Help desk',
            Status__c = 'Active',
            Description__c = 'https://api.sam.gov/prod/opportunities/v1/noticedesc?noticeid=EXP-DESC',
            Needs_Description__c = true
        );
        insert n;
        Test.setMock(HttpCalloutMock.class, new DescriptionMock());
        Test.startTest();
        String text = NXP_NoticeController.loadDescription(n.Id);
        Test.stopTest();
        System.assert(text.contains('Help desk tier 1 support'), text);
        n = [SELECT Description__c, Needs_Description__c FROM NXP_Gov_Notice__c WHERE Id = :n.Id];
        System.assertEquals(false, n.Needs_Description__c);
        System.assertEquals(text, n.Description__c);
        // Already fetched: returns the text without another call.
        System.assertEquals(text, NXP_NoticeController.loadDescription(n.Id));
    }

    private class AnalyzerMock implements NXP_DocumentAnalyzer {
        public Boolean active = true;
        public Set<Id> queued = new Set<Id>();
        public Boolean isEnabled() {
            return active;
        }
        public void enqueue(Set<Id> analysisIds) {
            queued.addAll(analysisIds);
        }
    }

    @IsTest
    static void documentsCardListsFilesAndAnalyzes() {
        AnalyzerMock mock = new AnalyzerMock();
        mock.active = false;
        NXP_DocumentService.analyzerOverride = mock;
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(Notice_Id__c = 'EXP-DOC', Title__c = 'Docs', Status__c = 'Active');
        insert n;
        // Attached while the Document Reader was bypassed, as files attached before it existed.
        NXP_TriggerHandler.bypass(NXP_DocumentService.HANDLER);
        ContentVersion v = new ContentVersion(
            Title = 'SOW',
            PathOnClient = 'SOW.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            FirstPublishLocationId = n.Id
        );
        insert v;
        NXP_TriggerHandler.clearBypass(NXP_DocumentService.HANDLER);
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;

        NXP_DocumentController.Documents d = NXP_DocumentController.getDocuments(n.Id);
        System.assert(!d.enabled);
        System.assertEquals(1, d.rows.size());
        System.assertEquals('SOW.pdf', d.rows[0].fileName);
        System.assertEquals('Not read', d.rows[0].status);

        try {
            NXP_DocumentController.analyze(n.Id, docId);
            System.assert(false, 'expected: reading is off');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('off'), e.getMessage());
        }
        mock.active = true;
        System.assert(NXP_DocumentController.analyze(n.Id, docId).startsWith('Reading'));
        System.assertEquals(1, mock.queued.size());
        d = NXP_DocumentController.getDocuments(n.Id);
        System.assertEquals('Pending', d.rows[0].status);
        System.assert(d.enabled);

        try {
            NXP_DocumentController.analyze(n.Id, UserInfo.getUserId());
            System.assert(false, 'expected: not attached');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not attached'));
        }
    }
}
