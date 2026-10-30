@IsTest
private class NXP_PushTest {
    /** Opportunity mapping that works in any org: the stage comes from the org's own active stages. */
    public static void useOpportunityMapping() {
        OpportunityStage stage = [
            SELECT ApiName
            FROM OpportunityStage
            WHERE IsActive = TRUE AND IsClosed = FALSE
            ORDER BY SortOrder
            LIMIT 1
        ];
        NXP_TechnoMilePushTarget.mappingOverride = new List<NXP_Push_Mapping__mdt>{
            row('Title__c', 'Name', true, 'Never', null),
            row('Response_Due__c', 'CloseDate', true, 'Update', null),
            row(null, 'StageName', true, 'Never', stage.ApiName),
            row('Estimated_Value__c', 'Amount', false, 'Alert Only', null),
            row('Solicitation_Number__c', 'NextStep', false, 'Never', null)
        };
    }

    private static NXP_Push_Mapping__mdt row(
        String source,
        String target,
        Boolean required,
        String sync,
        String defaultValue
    ) {
        return new NXP_Push_Mapping__mdt(
            Active__c = true,
            Mapping_Set__c = 'TechnoMile_Default',
            Target_Object__c = 'Opportunity',
            Source_Field__c = source,
            Target_Field__c = target,
            Required__c = required,
            Sync_Behavior__c = sync,
            Default_Value__c = defaultValue
        );
    }

    public static NXP_Gov_Notice__c notice(String key) {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = key,
            Title__c = 'Zero Trust Architecture Engineering Support ' + key,
            Solicitation_Number__c = 'SOL-' + key,
            Agency_Path__c = 'Homeland Security',
            Notice_Type__c = 'Solicitation',
            Status__c = 'Active',
            Estimated_Value__c = 20000000,
            Response_Due__c = Datetime.newInstance(2027, 1, 15, 14, 0, 0),
            Fit_Score__c = 85
        );
        insert n;
        return n;
    }

    @IsTest
    static void previewThenManualPushThenAlreadyPushed() {
        useOpportunityMapping();
        NXP_Gov_Notice__c n = notice('A');
        NXP_PushService.PushPreview p = NXP_PushController.previewPush(n.Id);
        System.assertEquals('Opportunity', p.targetObject);
        System.assertEquals(5, p.fields.size());
        System.assertEquals(null, p.existingRecordId);
        System.assertNotEquals(null, p.token);

        NXP_PushService.PushResult r = NXP_PushController.pushNoticeFrom(n.Id, true, 'Match Inbox');
        System.assertEquals('Success', r.status, r.message);
        System.assertEquals('Match Inbox', [SELECT Source__c FROM NXP_Push_Log__c].Source__c);
        System.assertEquals(null, NXP_PushService.source, 'cleared after the push');
        System.assertEquals('Assistant', NXP_PushService.sourceFor('Agent'));
        System.assertEquals('Auto-Push', NXP_PushService.sourceFor('Auto'));
        Opportunity o = [SELECT Name, CloseDate, Amount, NextStep FROM Opportunity WHERE Id = :r.targetId];
        System.assertEquals(Date.newInstance(2027, 1, 15), o.CloseDate);
        System.assertEquals('SOL-A', o.NextStep);
        n = [SELECT Pushed__c, Pushed_Record_Id__c FROM NXP_Gov_Notice__c WHERE Id = :n.Id];
        System.assert(n.Pushed__c);
        System.assertEquals('Success', [SELECT Status__c FROM NXP_Push_Log__c].Status__c);

        System.assertEquals('Linked Existing', NXP_PushController.pushNotice(n.Id, null, true).status);
        System.assert(NXP_PushController.previewPush(n.Id).alreadyPushed);
        System.assertEquals(1, NXP_PushController.getPushLogs(n.Id).size());
    }

    @IsTest
    static void existingRecordIsLinkedNotDuplicated() {
        useOpportunityMapping();
        NXP_Gov_Notice__c n = notice('B');
        OpportunityStage stage = [
            SELECT ApiName
            FROM OpportunityStage
            WHERE IsActive = TRUE AND IsClosed = FALSE
            LIMIT 1
        ];
        Opportunity existing = new Opportunity(
            Name = 'Already tracked',
            StageName = stage.ApiName,
            CloseDate = Date.today().addDays(30),
            NextStep = 'SOL-B'
        );
        insert existing;
        System.assertEquals(existing.Id, NXP_PushService.preview(n.Id).existingRecordId);
        NXP_PushService.PushResult r = NXP_PushService.push(
            new List<Id>{ n.Id },
            null,
            NXP_PushService.MODE_MANUAL,
            false
        )[0];
        System.assertEquals('Linked Existing', r.status);
        System.assertEquals(existing.Id, r.targetId);
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity]);
    }

    @IsTest
    static void agentPushNeedsPreviewToken() {
        useOpportunityMapping();
        NXP_Gov_Notice__c n = notice('C');
        System.assertEquals('Failed', NXP_PushService.pushWithToken(n.Id, 'nope', null).status);
        String token = NXP_PushService.preview(n.Id).token;
        System.assertEquals('Success', NXP_PushService.pushWithToken(n.Id, token, null).status);
        System.assertEquals('Agent', [SELECT Mode__c FROM NXP_Push_Log__c LIMIT 1].Mode__c);
    }

    @IsTest
    static void missingRequiredValueAndMissingMappingFail() {
        useOpportunityMapping();
        NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Name = 'No due date',
            Notice_Id__c = 'D',
            Title__c = 'No due date',
            Status__c = 'Active'
        );
        insert n;
        NXP_PushService.PushResult r = NXP_PushService.push(
            new List<Id>{ n.Id },
            null,
            NXP_PushService.MODE_AUTO,
            false
        )[0];
        System.assertEquals('Failed', r.status);
        System.assertEquals('Retry Pending', [SELECT Status__c FROM NXP_Push_Log__c].Status__c);

        NXP_TechnoMilePushTarget.mappingOverride = new List<NXP_Push_Mapping__mdt>();
        r = NXP_PushService.push(new List<Id>{ n.Id }, null, NXP_PushService.MODE_MANUAL, false)[0];
        System.assertEquals('Failed', r.status);
        System.assert(r.message.contains('No active'), r.message);
    }

    @IsTest
    static void autoPushListenerPushesAsSearchOwner() {
        useOpportunityMapping();
        NXP_Gov_Notice__c n = notice('E');
        NXP_Saved_Search__c s = new NXP_Saved_Search__c(
            Name = 'Auto',
            Criteria_JSON__c = '{}',
            Active__c = true,
            Auto_Push__c = 'Fit Threshold',
            Auto_Push_Min_Fit__c = 80
        );
        insert s;
        NXP_Search_Match__c m = new NXP_Search_Match__c(
            Saved_Search__c = s.Id,
            Gov_Notice__c = n.Id,
            Match_Key__c = 'mk',
            Change_Type__c = 'New',
            User_Action__c = 'None'
        );
        insert m;
        Test.startTest();
        new NXP_AutoPushListener().onMatches(new List<NXP_Search_Match__c>{ m });
        Test.stopTest();
        Opportunity o = [SELECT OwnerId FROM Opportunity];
        System.assertEquals(UserInfo.getUserId(), o.OwnerId);
        System.assertEquals('Pushed', [SELECT User_Action__c FROM NXP_Search_Match__c].User_Action__c);
        System.assertEquals('Auto', [SELECT Mode__c FROM NXP_Push_Log__c].Mode__c);
    }

    @IsTest
    static void amendmentSyncsPushedRecord() {
        useOpportunityMapping();
        NXP_Gov_Notice__c n = notice('F');
        Id oppId = NXP_PushService.push(new List<Id>{ n.Id }, null, NXP_PushService.MODE_MANUAL, false)[0].targetId;
        n.Response_Due__c = Datetime.newInstance(2027, 2, 1, 14, 0, 0);
        n.Estimated_Value__c = 30000000;
        update n;
        insert new NXP_Notice_Version__c(
            Gov_Notice__c = n.Id,
            Version_Number__c = 2,
            Change_Type__c = 'Due date, Value',
            Changed_Fields__c = 'Response_Due__c, Estimated_Value__c',
            Diff_Summary__c = 'Response Due: x → y'
        );
        Test.startTest();
        NXP_PostPushSyncHandler.handle(
            new List<NXP_Gov_Notice_Changed__e>{
                new NXP_Gov_Notice_Changed__e(
                    Notice_Record_Id__c = n.Id,
                    Change_Type__c = 'Due date, Value',
                    Is_New__c = false
                )
            }
        );
        Test.stopTest();
        Opportunity o = [SELECT CloseDate, Amount FROM Opportunity WHERE Id = :oppId];
        System.assertEquals(Date.newInstance(2027, 2, 1), o.CloseDate);
        System.assertEquals(20000000, o.Amount, 'Alert-only fields are not overwritten');
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Push_Log__c WHERE Mode__c = 'Sync']);
    }

    @IsTest
    static void retryJobAndBulkPushPermission() {
        useOpportunityMapping();
        NXP_Gov_Notice__c n = notice('G');
        insert new NXP_Push_Log__c(
            Gov_Notice__c = n.Id,
            Status__c = 'Retry Pending',
            Mode__c = 'Auto',
            Attempts__c = 1,
            Pushed_By__c = UserInfo.getUserId()
        );
        Test.startTest();
        new NXP_PushRetryJob().execute((SchedulableContext) null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity]);
        System.assertEquals('Failed', [SELECT Status__c FROM NXP_Push_Log__c WHERE Attempts__c = 2].Status__c);
        try {
            NXP_PushController.bulkPush(new List<Id>{ n.Id });
            System.assert(false, 'Needs NXP Power User');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
