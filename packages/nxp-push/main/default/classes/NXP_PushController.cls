/**
 * Push dialog and push status for the nxpPushDialog, nxpMatchInbox and nxpNoticeSummary LWCs.
 */
public with sharing class NXP_PushController {
    @AuraEnabled
    public static NXP_PushService.PushPreview previewPush(Id noticeId) {
        try {
            return NXP_PushService.preview(noticeId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static NXP_PushService.PushResult pushNotice(Id noticeId, Id ownerId, Boolean includeDocuments) {
        List<NXP_PushService.PushResult> results = NXP_PushService.push(
            new List<Id>{ noticeId },
            ownerId,
            NXP_PushService.MODE_MANUAL,
            includeDocuments
        );
        if (results.isEmpty()) {
            throw new AuraHandledException('Notice not found or not visible to you.');
        }
        return results[0];
    }

    @AuraEnabled
    public static List<NXP_PushService.PushResult> bulkPush(List<Id> noticeIds) {
        if (!FeatureManagement.checkPermission('NXP_Power_User')) {
            throw new AuraHandledException('Bulk push needs the NXP Power User permission.');
        }
        if (noticeIds == null || noticeIds.size() > 200) {
            throw new AuraHandledException('Select between 1 and 200 notices.');
        }
        return NXP_PushService.push(noticeIds, null, NXP_PushService.MODE_MANUAL, true);
    }

    @AuraEnabled
    public static List<NXP_Push_Log__c> getPushLogs(Id noticeId) {
        return [
            SELECT
                Id,
                Name,
                Status__c,
                Mode__c,
                Target_Object__c,
                Target_Record_Id__c,
                Pushed_By__r.Name,
                Error__c,
                CreatedDate
            FROM NXP_Push_Log__c
            WHERE Gov_Notice__c = :noticeId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
    }
}
