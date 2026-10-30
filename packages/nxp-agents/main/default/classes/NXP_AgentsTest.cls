@IsTest
private class NXP_AgentsTest {
    private static void useOpportunityMapping() {
        OpportunityStage stage = [
            SELECT ApiName
            FROM OpportunityStage
            WHERE IsActive = TRUE AND IsClosed = FALSE
            ORDER BY SortOrder
            LIMIT 1
        ];
        List<NXP_Push_Mapping__mdt> rows = new List<NXP_Push_Mapping__mdt>();
        for (
            List<String> r : new List<List<String>>{
                new List<String>{ 'Title__c', 'Name', 'true', null },
                new List<String>{ 'Response_Due__c', 'CloseDate', 'true', null },
                new List<String>{ null, 'StageName', 'true', stage.ApiName }
            }
        ) {
            rows.add(
                new NXP_Push_Mapping__mdt(
                    Active__c = true,
                    Mapping_Set__c = 'Opportunity_Default',
                    Target_Object__c = 'Opportunity',
                    Source_Field__c = r[0],
                    Target_Field__c = r[1],
                    Required__c = r[2] == 'true',
                    Sync_Behavior__c = 'Never',
                    Default_Value__c = r[3]
                )
            );
        }
        NXP_OpportunityPushTarget.mappingOverride = rows;
    }

    private static NXP_Gov_Notice__c notice() {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'AG-1',
            Title__c = 'Cyber zero trust support',
            Agency_Path__c = 'Homeland Security',
            NAICS_Code__c = '541512',
            Notice_Type__c = 'Solicitation',
            Status__c = 'Active',
            Response_Due__c = Datetime.now().addDays(20),
            Posted_Date__c = Date.today(),
            Fit_Breakdown__c = '[{"rule":"NAICS","weight":30,"points":30,"reason":"NAICS 541512 is in our profile"}]',
            AI_Summary_Status__c = 'Pending'
        );
        insert n;
        n.Fit_Score__c = 30;
        update n;
        return n;
    }

    @IsTest
    static void searchActionsRequirePreviewBeforeSave() {
        notice();
        NXP_DraftSearchCriteriaAction.Request dr = new NXP_DraftSearchCriteriaAction.Request();
        dr.text = 'cyber notices, NAICS 541512, daily';
        NXP_DraftSearchCriteriaAction.Response d = NXP_DraftSearchCriteriaAction.run(
            new List<NXP_DraftSearchCriteriaAction.Request>{ dr }
        )[0];
        System.assertEquals('Daily', d.frequency);

        NXP_PreviewSearchAction.Request pr = new NXP_PreviewSearchAction.Request();
        pr.criteriaJson = d.criteriaJson;
        NXP_PreviewSearchAction.Response p = NXP_PreviewSearchAction.run(
            new List<NXP_PreviewSearchAction.Request>{ pr }
        )[0];
        System.assertEquals(1, p.matchCount);
        System.assert(p.topMatches.contains('AG-1'));

        NXP_SaveSearchAction.Request sr = new NXP_SaveSearchAction.Request();
        sr.name = 'Cyber';
        sr.criteriaJson = d.criteriaJson;
        sr.frequency = d.frequency;
        sr.previewToken = 'forged';
        System.assertEquals(null, NXP_SaveSearchAction.run(new List<NXP_SaveSearchAction.Request>{ sr })[0].searchId);
        sr.previewToken = p.previewToken;
        NXP_SaveSearchAction.Response saved = NXP_SaveSearchAction.run(new List<NXP_SaveSearchAction.Request>{ sr })[0];
        System.assertNotEquals(null, saved.searchId, saved.message);

        NXP_SetAutoPushRuleAction.Request ar = new NXP_SetAutoPushRuleAction.Request();
        ar.searchId = saved.searchId;
        ar.mode = 'All Matches';
        System.assert(
            NXP_SetAutoPushRuleAction.run(new List<NXP_SetAutoPushRuleAction.Request>{ ar })[0]
                .message.contains('Power User')
        );
    }

    @IsTest
    static void aiDraftIsUsedWhenEnabled() {
        NXP_AiService.responsesForTest = new Map<String, String>{
            'NXP_Search_Criteria_Draft' => '```json\n{"keywords":"cloud","naics":["541519"]}\n```'
        };
        NXP_DraftSearchCriteriaAction.Request dr = new NXP_DraftSearchCriteriaAction.Request();
        dr.text = 'army cloud work';
        NXP_DraftSearchCriteriaAction.Response d = NXP_DraftSearchCriteriaAction.run(
            new List<NXP_DraftSearchCriteriaAction.Request>{ dr }
        )[0];
        System.assert(d.criteriaJson.contains('541519'), d.criteriaJson);
    }

    @IsTest
    static void noticeBriefingActions() {
        NXP_Gov_Notice__c n = notice();
        insert new NXP_Notice_Version__c(
            Gov_Notice__c = n.Id,
            Version_Number__c = 2,
            Change_Type__c = 'Due date',
            Diff_Summary__c = 'Response Due: a → b'
        );
        NXP_ExplainFitScoreAction.Request er = new NXP_ExplainFitScoreAction.Request();
        er.noticeId = n.Id;
        System.assert(
            NXP_ExplainFitScoreAction.run(new List<NXP_ExplainFitScoreAction.Request>{ er })[0]
                .explanation.contains('NAICS')
        );
        NXP_CompareVersionsAction.Request cr = new NXP_CompareVersionsAction.Request();
        cr.noticeId = n.Id;
        System.assert(
            NXP_CompareVersionsAction.run(new List<NXP_CompareVersionsAction.Request>{ cr })[0]
                .changes.contains('Amendment 1')
        );
    }

    @IsTest
    static void pushActions() {
        useOpportunityMapping();
        NXP_Gov_Notice__c n = notice();
        NXP_PreviewPushAction.Request pr = new NXP_PreviewPushAction.Request();
        pr.noticeId = n.Id;
        NXP_PreviewPushAction.Response p = NXP_PreviewPushAction.run(new List<NXP_PreviewPushAction.Request>{ pr })[0];
        System.assert(p.preview.contains('new one will be created'), p.preview);

        NXP_PushToOpportunityAction.Request push = new NXP_PushToOpportunityAction.Request();
        push.noticeId = n.Id;
        push.previewToken = 'forged';
        System.assertEquals(
            'Failed',
            NXP_PushToOpportunityAction.run(new List<NXP_PushToOpportunityAction.Request>{ push })[0].status
        );
        push.previewToken = p.previewToken;
        System.assertEquals(
            'Success',
            NXP_PushToOpportunityAction.run(new List<NXP_PushToOpportunityAction.Request>{ push })[0].status
        );

        NXP_PushStatusAction.Request st = new NXP_PushStatusAction.Request();
        st.noticeId = n.Id;
        System.assert(
            NXP_PushStatusAction.run(new List<NXP_PushStatusAction.Request>{ st })[0].status.contains('Success')
        );
    }

    @IsTest
    static void marketIntelActions() {
        NXP_Gov_Agency__c agency = new NXP_Gov_Agency__c(
            Name = 'CBP',
            Agency_Code__c = '070.7014',
            Full_Path__c = 'Homeland Security › CBP'
        );
        insert agency;
        NXP_Gov_Vendor__c vendor = new NXP_Gov_Vendor__c(Name = 'Acme Federal', UEI__c = 'ABCDEFGHJK12');
        insert vendor;
        NXP_Award_Summary__c award = new NXP_Award_Summary__c(
            Name = 'Cyber ops',
            PIID__c = 'P1',
            Agency__c = agency.Id,
            Vendor__c = vendor.Id,
            NAICS_Code__c = '541512',
            Obligated_Amount__c = 12000000,
            Period_End__c = Date.today().addMonths(6)
        );
        insert award;
        NXP_Gov_Notice__c n = notice();
        n.Agency__c = agency.Id;
        update n;

        NXP_FindIncumbentAction.Request fr = new NXP_FindIncumbentAction.Request();
        fr.noticeId = n.Id;
        System.assert(
            NXP_FindIncumbentAction.run(new List<NXP_FindIncumbentAction.Request>{ fr })[0]
                .answer.contains('Acme Federal')
        );
        n.Predecessor_Award__c = award.Id;
        update n;
        System.assert(
            NXP_FindIncumbentAction.run(new List<NXP_FindIncumbentAction.Request>{ fr })[0]
                .answer.startsWith('Predecessor award P1')
        );

        NXP_RecompeteQueryAction.Request rr = new NXP_RecompeteQueryAction.Request();
        rr.agency = 'CBP';
        rr.naics = '5415*';
        System.assert(
            NXP_RecompeteQueryAction.run(new List<NXP_RecompeteQueryAction.Request>{ rr })[0].recompetes.contains('P1')
        );
        rr.minValue = 50000000;
        System.assert(
            NXP_RecompeteQueryAction.run(new List<NXP_RecompeteQueryAction.Request>{ rr })[0]
                .recompetes.startsWith('No awards')
        );
    }

    @IsTest
    static void noticeAnalystWritesSummariesAndChangeSummaries() {
        NXP_Gov_Notice__c n = notice();
        insert new NXP_Notice_Version__c(
            Gov_Notice__c = n.Id,
            Version_Number__c = 2,
            Change_Type__c = 'Due date',
            Diff_Summary__c = 'x'
        );
        NXP_AiService.responsesForTest = new Map<String, String>{
            'NXP_Solicitation_Summary' => 'A short summary.',
            'NXP_Amendment_Impact' => 'Due date moved.'
        };
        System.assert(NXP_AiService.isEnabled());
        Test.startTest();
        Database.executeBatch(new NXP_NoticeAnalystJob(NXP_NoticeAnalystJob.SUMMARIES), 5);
        Test.stopTest();
        n = [SELECT AI_Summary__c, AI_Summary_Status__c FROM NXP_Gov_Notice__c WHERE Id = :n.Id];
        System.assertEquals('Complete', n.AI_Summary_Status__c);
        System.assertEquals('A short summary.', n.AI_Summary__c);
    }

    @IsTest
    static void dailyAiLimitStopsCallsAndLeavesWorkPending() {
        NXP_Gov_Notice__c n = notice();
        NXP_AiService.responsesForTest = new Map<String, String>{ 'NXP_Solicitation_Summary' => 'A short summary.' };
        NXP_Settings.setForTest('AI_Max_Calls_Per_Day', '1');
        System.assertEquals('Test response', NXP_AiService.generate('X', new Map<String, Object>()));
        System.assert(NXP_AiService.limitReached());
        try {
            NXP_AiService.generate('X', new Map<String, Object>());
            System.assert(false, 'expected: limit reached');
        } catch (NXP_AiService.AiLimitException e) {
            System.assert(e.getMessage().contains('AI_Max_Calls_Per_Day'), e.getMessage());
        }
        NXP_AiService.flushUsage();
        NXP_AI_Usage__c u = [SELECT Day__c, Calls__c FROM NXP_AI_Usage__c LIMIT 1];
        System.assertEquals(Date.today(), u.Day__c);
        System.assertEquals(1, u.Calls__c);
        System.assertEquals(1, NXP_AiService.callsToday());

        Test.startTest();
        Database.executeBatch(new NXP_NoticeAnalystJob(NXP_NoticeAnalystJob.SUMMARIES), 5);
        Test.stopTest();
        n = [SELECT AI_Summary_Status__c FROM NXP_Gov_Notice__c WHERE Id = :n.Id];
        System.assertEquals('Pending', n.AI_Summary_Status__c, 'Waits for tomorrow instead of failing');

        NXP_Settings.setForTest('AI_Max_Calls_Per_Day', '0');
        System.assert(!NXP_AiService.limitReached(), '0 means no limit');
    }

    @IsTest
    static void changeSummariesAndSchedule() {
        NXP_Gov_Notice__c n = notice();
        insert new NXP_Notice_Version__c(
            Gov_Notice__c = n.Id,
            Version_Number__c = 2,
            Change_Type__c = 'Due date',
            Diff_Summary__c = 'x'
        );
        NXP_AiService.responsesForTest = new Map<String, String>{ 'NXP_Amendment_Impact' => 'Due date moved.' };
        Test.startTest();
        Database.executeBatch(new NXP_NoticeAnalystJob(NXP_NoticeAnalystJob.CHANGES), 5);
        List<Id> jobIds = NXP_NoticeAnalystJob.scheduleDefaults();
        System.assertEquals(2, jobIds.size());
        for (Id jobId : jobIds) {
            System.abortJob(jobId);
        }
        Test.stopTest();
        System.assertEquals(
            'Due date moved.',
            [SELECT AI_Change_Summary__c FROM NXP_Notice_Version__c WHERE Version_Number__c = 2].AI_Change_Summary__c
        );
    }

    @IsTest
    static void aiServiceIsOffByDefault() {
        // UAT and production switch AI on through env-config; force it off for this test.
        NXP_Settings.setForTest('AI_Enabled', 'false');
        System.assert(!NXP_AiService.isEnabled());
        try {
            NXP_AiService.generate('NXP_Solicitation_Summary', new Map<String, Object>());
            System.assert(false);
        } catch (NXP_AiService.AiUnavailableException e) {
            System.assert(e.getMessage().contains('switched off'));
        }
    }

    @IsTest
    static void ebuyAiExtractCallsTheTemplate() {
        NXP_Settings.setForTest('Ebuy_AI_Template', 'NXP_Ebuy_RFQ_Extract');
        NXP_AiService.responsesForTest = new Map<String, String>{ 'NXP_Ebuy_RFQ_Extract' => '{"title":"X"}' };
        NXP_EbuyAiExtract ai = new NXP_EbuyAiExtract();
        System.assert(ai.isEnabled());
        NXP_Inbound_Email__c em = new NXP_Inbound_Email__c(Subject__c = 'RFQ1234567', Status__c = 'Received');
        insert em;
        System.assertEquals('{"title":"X"}', ai.extract(em.Id, null));
        System.assert(Type.forName('NXP_EbuyAiExtract').newInstance() instanceof NXP_EbuyAiExtractor);
    }

    @IsTest
    static void documentReaderReadsAttachedPdfs() {
        NXP_Settings.setForTest('Document_Analysis_Enabled', 'true');
        NXP_Settings.setForTest('Document_Analysis_Template', 'NXP_Document_Analysis');
        NXP_AiService.responsesForTest = new Map<String, String>{
            'NXP_Document_Analysis' => '{"summary":"Help desk support.","documentType":"SOW",' +
            '"requirements":["Tier 1 coverage"],"evaluationFactors":["Price"],' +
            '"submission":{"dueDate":"2026-11-12"},"keyDates":[{"label":"Questions due","date":"2026-11-05"}]}'
        };
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'T-DOC-AG',
            Title__c = 'Help desk',
            Status__c = 'Active',
            Response_Due__c = Datetime.newInstanceGmt(2026, 11, 20, 19, 0, 0)
        );
        insert n;
        Test.startTest();
        insert new ContentVersion(
            Title = 'SOW',
            PathOnClient = 'SOW.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            FirstPublishLocationId = n.Id
        );
        Test.stopTest();

        NXP_Document_Analysis__c a = [
            SELECT Status__c, Result_Json__c
            FROM NXP_Document_Analysis__c
            WHERE Gov_Notice__c = :n.Id
        ];
        System.assertEquals('Complete', a.Status__c);
        System.assert(a.Result_Json__c.contains('Tier 1 coverage'));
        System.assert(a.Result_Json__c.contains('responses are due 2026-11-12'), 'differs from the notice');

        String text = NXP_NoticeDocumentsAction.run(new List<NXP_NoticeDocumentsAction.Request>{ request(n.Id) })[0]
            .documents;
        System.assert(text.contains('SOW.pdf (SOW): Help desk support.'), text);
        System.assert(text.contains('Requirements: Tier 1 coverage'), text);
        System.assert(text.contains('Date: Questions due 2026-11-05'), text);

        // A model that answers with prose marks the row Failed and keeps going.
        NXP_AiService.responsesForTest.put('NXP_Document_Analysis', 'Sorry, I cannot read that.');
        update new NXP_Document_Analysis__c(
            Id = [SELECT Id FROM NXP_Document_Analysis__c WHERE Gov_Notice__c = :n.Id]
            .Id,
            Status__c = 'Pending'
        );
        new NXP_DocumentAnalysisJob(null).execute(null);
        System.assertEquals(
            'Failed',
            [SELECT Status__c FROM NXP_Document_Analysis__c WHERE Gov_Notice__c = :n.Id].Status__c
        );
        System.assert(
            NXP_NoticeDocumentsAction.run(new List<NXP_NoticeDocumentsAction.Request>{ request(n.Id) })[0]
                .documents.contains('Failed')
        );
    }

    private static NXP_NoticeDocumentsAction.Request request(Id noticeId) {
        NXP_NoticeDocumentsAction.Request r = new NXP_NoticeDocumentsAction.Request();
        r.noticeId = noticeId;
        return r;
    }
}
