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
        /** Points where a read document disagrees with the notice and nobody has checked them yet. */
        @AuraEnabled
        public List<DocumentCheck> checks = new List<DocumentCheck>();
    }

    public class DocumentCheck {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Id analysisId;
        @AuraEnabled
        public Id documentId;
        @AuraEnabled
        public String fileName;
        @AuraEnabled
        public String field;
        @AuraEnabled
        public String noticeValue;
        @AuraEnabled
        public String documentValue;
        @AuraEnabled
        public String text;
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
        d.checks = openChecks(noticeId);
        return d;
    }

    @TestVisible
    private static List<DocumentCheck> openChecks(Id noticeId) {
        List<DocumentCheck> out = new List<DocumentCheck>();
        for (NXP_Document_Analysis__c a : [
            SELECT Id, Content_Document_Id__c, File_Name__c, Result_Json__c
            FROM NXP_Document_Analysis__c
            WHERE
                Gov_Notice__c = :noticeId
                AND Status__c = 'Complete'
                AND Check_Count__c > 0
                AND Checks_Reviewed__c = NULL
            WITH USER_MODE
            ORDER BY Analyzed__c DESC
            LIMIT 20
        ]) {
            if (String.isBlank(a.Result_Json__c)) {
                continue;
            }
            Map<String, Object> result;
            try {
                result = (Map<String, Object>) JSON.deserializeUntyped(a.Result_Json__c);
            } catch (Exception e) {
                continue;
            }
            List<Object> items = result.get('checkItems') instanceof List<Object>
                ? (List<Object>) result.get('checkItems')
                : new List<Object>();
            for (Object o : items) {
                Map<String, Object> item = (Map<String, Object>) o;
                DocumentCheck c = new DocumentCheck();
                c.key = a.Id + '-' + out.size();
                c.analysisId = a.Id;
                c.documentId = Id.valueOf(a.Content_Document_Id__c);
                c.fileName = a.File_Name__c;
                c.field = (String) item.get('field');
                c.noticeValue = (String) item.get('notice');
                c.documentValue = (String) item.get('document');
                c.text = (String) item.get('text');
                out.add(c);
            }
        }
        return out;
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
        if (n.Description_Requested__c == true) {
            // A saved search was waiting for this text: match the notice again.
            Database.update(
                new NXP_Gov_Notice__c(Id = n.Id, Description_Requested__c = false),
                AccessLevel.SYSTEM_MODE
            );
            EventBus.publish(
                new NXP_Gov_Notice_Changed__e(
                    Notice_Record_Id__c = n.Id,
                    Change_Type__c = NXP_SearchMatchService.DESCRIPTION_FETCHED,
                    Is_New__c = false,
                    Source_Feed__c = n.Source_Feed__c
                )
            );
        }
        return n.Description__c;
    }
}
