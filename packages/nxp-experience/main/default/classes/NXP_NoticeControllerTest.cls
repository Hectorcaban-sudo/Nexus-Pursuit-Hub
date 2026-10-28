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
}
