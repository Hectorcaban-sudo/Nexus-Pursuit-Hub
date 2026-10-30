/**
 * Data for the Documents card on the Gov Notice page (nxpNoticeDocuments): the notice's Files and
 * what the Document Reader read from each, plus Analyze. Reads run in user mode.
 */
public with sharing class NXP_DocumentController {
    public class DocumentRow {
        @AuraEnabled
        public Id documentId;
        @AuraEnabled
        public String fileName;
        @AuraEnabled
        public Integer size;
        @AuraEnabled
        public Datetime added;
        @AuraEnabled
        public Id analysisId;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String statusDetail;
        @AuraEnabled
        public Datetime analyzed;
        /** Checked JSON from NXP_DocumentAnalysisParser, or null. */
        @AuraEnabled
        public String resultJson;
    }

    public class Documents {
        @AuraEnabled
        public List<DocumentRow> rows = new List<DocumentRow>();
        @AuraEnabled
        public Boolean enabled = false;
        /** SAM.gov attachments listed for the notice, and what happened to them. */
        @AuraEnabled
        public Integer samFiles = 0;
        @AuraEnabled
        public Boolean samFilesPending = false;
        @AuraEnabled
        public String samFilesStatus;
    }

    @AuraEnabled
    public static Documents getDocuments(Id noticeId) {
        try {
            Documents out = new Documents();
            out.enabled = NXP_DocumentService.isEnabled();
            for (NXP_Gov_Notice__c n : [
                SELECT Resource_Links__c, Files_Pending__c, Files_Status__c
                FROM NXP_Gov_Notice__c
                WHERE Id = :noticeId
                WITH USER_MODE
            ]) {
                out.samFiles = String.isBlank(n.Resource_Links__c) ? 0 : n.Resource_Links__c.split('\n').size();
                out.samFilesPending = n.Files_Pending__c;
                out.samFilesStatus = n.Files_Status__c;
            }
            Map<Id, ContentDocumentLink> links = new Map<Id, ContentDocumentLink>();
            for (ContentDocumentLink l : [
                SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.FileExtension,
                    ContentDocument.ContentSize,
                    ContentDocument.CreatedDate
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :noticeId
                WITH USER_MODE
            ]) {
                links.put(l.ContentDocumentId, l);
            }
            Map<Id, NXP_Document_Analysis__c> byDoc = new Map<Id, NXP_Document_Analysis__c>();
            for (NXP_Document_Analysis__c a : [
                SELECT Id, Content_Document_Id__c, Status__c, Status_Detail__c, Analyzed__c, Result_Json__c
                FROM NXP_Document_Analysis__c
                WHERE Gov_Notice__c = :noticeId
                WITH USER_MODE
            ]) {
                byDoc.put(Id.valueOf(a.Content_Document_Id__c), a);
            }
            for (ContentDocumentLink l : links.values()) {
                DocumentRow r = new DocumentRow();
                r.documentId = l.ContentDocumentId;
                r.fileName = String.isBlank(l.ContentDocument.FileExtension)
                    ? l.ContentDocument.Title
                    : l.ContentDocument.Title + '.' + l.ContentDocument.FileExtension;
                r.size = l.ContentDocument.ContentSize;
                r.added = l.ContentDocument.CreatedDate;
                NXP_Document_Analysis__c a = byDoc.get(l.ContentDocumentId);
                if (a == null) {
                    // Attached before the Document Reader existed; Analyze registers it.
                    r.status = 'Not read';
                } else {
                    r.analysisId = a.Id;
                    r.status = a.Status__c;
                    r.statusDetail = a.Status_Detail__c;
                    r.analyzed = a.Analyzed__c;
                    r.resultJson = a.Result_Json__c;
                }
                out.rows.add(r);
            }
            return out;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static String analyze(Id noticeId, Id documentId) {
        try {
            // The user must be able to read the notice; the file link must be visible to them too.
            if (
                [SELECT COUNT() FROM NXP_Gov_Notice__c WHERE Id = :noticeId WITH USER_MODE] == 0 ||
                [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :noticeId AND ContentDocumentId = :documentId
                    WITH USER_MODE
                ] == 0
            ) {
                throw new AuraHandledException('That file is not attached to this notice.');
            }
            return NXP_DocumentService.requestAnalysis(noticeId, documentId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Get SAM.gov files: downloads this notice's SAM.gov attachments in the background. */
    @AuraEnabled
    public static String requestSamFiles(Id noticeId) {
        try {
            List<NXP_Gov_Notice__c> rows = [
                SELECT Id, Resource_Links__c
                FROM NXP_Gov_Notice__c
                WHERE Id = :noticeId
                WITH USER_MODE
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('Notice not found or not visible to you.');
            }
            if (String.isBlank(rows[0].Resource_Links__c)) {
                throw new AuraHandledException('SAM.gov lists no files for this notice.');
            }
            // Notices are read-only for most users; only the request flags are written.
            Database.update(
                new NXP_Gov_Notice__c(
                    Id = noticeId,
                    Files_Requested__c = true,
                    Files_Pending__c = true,
                    Files_Status__c = 'Getting the files from SAM.gov…'
                ),
                AccessLevel.SYSTEM_MODE
            );
            System.enqueueJob(new NXP_SamFileJob(new List<Id>{ noticeId }));
            return 'Getting the files from SAM.gov. They appear here in a few minutes, one at a time.';
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * Records that someone checked where this document disagrees with the notice, so the warning
     * on the notice page goes away for everyone. Reading the file again brings it back if it still
     * disagrees.
     */
    @AuraEnabled
    public static void markChecked(Id analysisId) {
        try {
            if ([SELECT COUNT() FROM NXP_Document_Analysis__c WHERE Id = :analysisId WITH USER_MODE] == 0) {
                throw new AuraHandledException('Document not found or not visible to you.');
            }
            // Analyses are read-only for most users; only these two fields are written.
            Database.update(
                new NXP_Document_Analysis__c(
                    Id = analysisId,
                    Checks_Reviewed__c = Datetime.now(),
                    Checks_Reviewed_By__c = UserInfo.getUserId()
                ),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static Exception handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return e;
        }
        AuraHandledException a = new AuraHandledException(e.getMessage());
        a.setMessage(e.getMessage());
        return a;
    }
}
