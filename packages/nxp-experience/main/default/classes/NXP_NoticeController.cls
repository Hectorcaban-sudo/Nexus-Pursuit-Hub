/**
 * Everything the Gov Notice record page component (nxpNoticeSummary) shows, in one call.
 */
public with sharing class NXP_NoticeController {
    public class Detail {
        @AuraEnabled
        public NXP_Gov_Notice__c notice;
        @AuraEnabled
        public List<NXP_FitScoreService.RuleResult> breakdown = new List<NXP_FitScoreService.RuleResult>();
        @AuraEnabled
        public List<NXP_Notice_Version__c> versions = new List<NXP_Notice_Version__c>();
        @AuraEnabled
        public List<NXP_Gov_Contact__c> contacts = new List<NXP_Gov_Contact__c>();
        @AuraEnabled
        public List<NXP_Push_Log__c> pushLogs = new List<NXP_Push_Log__c>();
        @AuraEnabled
        public Boolean following = false;
        @AuraEnabled
        public List<String> sources = new List<String>();
    }

    @AuraEnabled
    public static Detail getDetail(Id noticeId) {
        Detail d = new Detail();
        d.notice = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (d.notice == null) {
            throw new AuraHandledException('Notice not found or not visible to you.');
        }
        if (String.isNotBlank(d.notice.Fit_Breakdown__c)) {
            d.breakdown = (List<NXP_FitScoreService.RuleResult>) JSON.deserialize(
                d.notice.Fit_Breakdown__c,
                List<NXP_FitScoreService.RuleResult>.class
            );
        }
        if (String.isNotBlank(d.notice.Source_Lineage__c)) {
            d.sources = (List<String>) JSON.deserialize(d.notice.Source_Lineage__c, List<String>.class);
        }
        d.versions = [
            SELECT Id, Version_Number__c, Change_Type__c, Diff_Summary__c, AI_Change_Summary__c, CreatedDate
            FROM NXP_Notice_Version__c
            WHERE Gov_Notice__c = :noticeId
            WITH USER_MODE
            ORDER BY Version_Number__c DESC
            LIMIT 20
        ];
        d.contacts = [
            SELECT Id, Name, Email__c, Phone__c, Role__c
            FROM NXP_Gov_Contact__c
            WHERE Gov_Notice__c = :noticeId
            WITH USER_MODE
            ORDER BY Role__c
            LIMIT 20
        ];
        d.pushLogs = NXP_PushController.getPushLogs(noticeId);
        d.following = NXP_SearchController.isFollowing(noticeId);
        return d;
    }

    /**
     * Fetches the SAM.gov description text for one notice on request (one SAM.gov API call) and saves it.
     * The feed only fetches text automatically for matched and high-fit notices.
     */
    @AuraEnabled
    public static String loadDescription(Id noticeId) {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            throw new AuraHandledException('Notice not found or not visible to you.');
        }
        if (!NXP_NoticeEnrichBatch.needsText(n)) {
            return n.Description__c;
        }
        try {
            NXP_NoticeEnrichBatch.apply(n);
        } catch (Exception e) {
            throw new AuraHandledException('SAM.gov did not return the description. ' + e.getMessage());
        }
        // Notices are read-only for most users; only the fetched text is written.
        Database.update(
            new NXP_Gov_Notice__c(
                Id = n.Id,
                Description__c = n.Description__c,
                Needs_Description__c = false,
                Content_Hash__c = n.Content_Hash__c
            ),
            AccessLevel.SYSTEM_MODE
        );
        return n.Description__c;
    }
}
