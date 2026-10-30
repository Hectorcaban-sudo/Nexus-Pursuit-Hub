/**
 * Keeps one NXP_Document_Analysis__c row per File attached to a Gov Notice and starts the
 * analysis. Called from NXP_ContentDocumentLinkTrigger when files are attached (eBuy attachments,
 * uploads on the notice page) and from the notice page's Analyze button.
 * Files are read only when Document_Analysis_Enabled and AI_Enabled are on; rows are kept either
 * way so the page can show what is waiting. PDFs only: the model reads PDF files, not Word or Excel.
 * Runs as background bookkeeping for any user who attaches a file, so it is without sharing.
 */
public without sharing class NXP_DocumentService {
    public static final String HANDLER = 'NXP_DocumentService';

    @TestVisible
    private static NXP_DocumentAnalyzer analyzerOverride;

    /** After-insert on ContentDocumentLink: register files linked to notices. Never throws. */
    public static void onLinksInserted(List<ContentDocumentLink> links) {
        if (NXP_TriggerHandler.isBypassed(HANDLER)) {
            return;
        }
        try {
            Map<Id, Set<Id>> docsByNotice = new Map<Id, Set<Id>>();
            for (ContentDocumentLink l : links) {
                if (l.LinkedEntityId != null && l.LinkedEntityId.getSObjectType() == NXP_Gov_Notice__c.SObjectType) {
                    if (!docsByNotice.containsKey(l.LinkedEntityId)) {
                        docsByNotice.put(l.LinkedEntityId, new Set<Id>());
                    }
                    docsByNotice.get(l.LinkedEntityId).add(l.ContentDocumentId);
                }
            }
            if (docsByNotice.isEmpty()) {
                return;
            }
            List<NXP_Document_Analysis__c> created = register(docsByNotice, true);
            Set<Id> pending = new Set<Id>();
            for (NXP_Document_Analysis__c a : created) {
                if (a.Status__c == 'Pending' && String.isBlank(a.Status_Detail__c)) {
                    pending.add(a.Id);
                }
            }
            start(pending);
        } catch (Exception e) {
            NXP_Logger.error(HANDLER, 'Could not register notice documents', e, null);
            NXP_Logger.flush();
        }
    }

    /**
     * Creates the missing rows for these notice files and returns them (existing rows are left as
     * they are). With applyLimit, files beyond Document_Max_Per_Notice stay unread until Analyze.
     */
    public static List<NXP_Document_Analysis__c> register(Map<Id, Set<Id>> docsByNotice, Boolean applyLimit) {
        Set<Id> docIds = new Set<Id>();
        Set<String> keys = new Set<String>();
        for (Id noticeId : docsByNotice.keySet()) {
            for (Id docId : docsByNotice.get(noticeId)) {
                docIds.add(docId);
                keys.add(key(noticeId, docId));
            }
        }
        Set<String> existing = new Set<String>();
        Map<Id, Integer> countByNotice = new Map<Id, Integer>();
        for (NXP_Document_Analysis__c a : [
            SELECT Analysis_Key__c, Gov_Notice__c
            FROM NXP_Document_Analysis__c
            WHERE Gov_Notice__c IN :docsByNotice.keySet()
        ]) {
            existing.add(a.Analysis_Key__c);
            countByNotice.put(
                a.Gov_Notice__c,
                (countByNotice.containsKey(a.Gov_Notice__c) ? countByNotice.get(a.Gov_Notice__c) : 0) + 1
            );
        }
        Map<Id, ContentDocument> docs = new Map<Id, ContentDocument>(
            [SELECT Id, Title, FileExtension, ContentSize FROM ContentDocument WHERE Id IN :docIds]
        );
        Integer maxPerNotice = NXP_Settings.getInteger('Document_Max_Per_Notice', 5);
        Decimal maxBytes = NXP_Settings.getDecimal('Document_Max_MB', 10) * 1024 * 1024;

        List<NXP_Document_Analysis__c> rows = new List<NXP_Document_Analysis__c>();
        for (Id noticeId : docsByNotice.keySet()) {
            for (Id docId : docsByNotice.get(noticeId)) {
                ContentDocument d = docs.get(docId);
                if (d == null || existing.contains(key(noticeId, docId))) {
                    continue;
                }
                Integer count = countByNotice.containsKey(noticeId) ? countByNotice.get(noticeId) : 0;
                NXP_Document_Analysis__c a = new NXP_Document_Analysis__c(
                    Gov_Notice__c = noticeId,
                    Content_Document_Id__c = docId,
                    Analysis_Key__c = key(noticeId, docId),
                    File_Name__c = NXP_Text.truncate(
                        String.isBlank(d.FileExtension) ? d.Title : d.Title + '.' + d.FileExtension,
                        255
                    ),
                    File_Size__c = d.ContentSize,
                    Status__c = 'Pending'
                );
                if (d.FileExtension == null || d.FileExtension.toLowerCase() != 'pdf') {
                    a.Status__c = 'Unsupported';
                    a.Status_Detail__c = 'Only PDF files can be read. Open the file to read it yourself.';
                } else if (d.ContentSize != null && d.ContentSize > maxBytes) {
                    a.Status__c = 'Too Large';
                    a.Status_Detail__c = 'Larger than Document_Max_MB; the model limit is usually 10 MB.';
                } else if (applyLimit && count >= maxPerNotice) {
                    a.Status__c = 'Pending';
                    a.Status_Detail__c =
                        'Not read automatically (more than ' +
                        maxPerNotice +
                        ' files). Click Analyze.';
                }
                countByNotice.put(noticeId, count + 1);
                rows.add(a);
            }
        }
        Database.insert(rows, false);
        List<NXP_Document_Analysis__c> saved = new List<NXP_Document_Analysis__c>();
        for (NXP_Document_Analysis__c a : rows) {
            if (a.Id != null) {
                saved.add(a);
            }
        }
        return saved;
    }

    /** Queues these Pending rows when analysis is on; otherwise they wait. Returns true if queued. */
    public static Boolean start(Set<Id> analysisIds) {
        if (analysisIds == null || analysisIds.isEmpty()) {
            return false;
        }
        NXP_DocumentAnalyzer a = analyzer();
        if (a == null || !a.isEnabled()) {
            return false;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            // In a Queueable that already queued its one child; the Notice Analyst run picks these up.
            return false;
        }
        a.enqueue(analysisIds);
        return true;
    }

    /**
     * Analyze button: reads (or re-reads) one file now. Returns what happens next; throws
     * IllegalArgumentException with a plain message when it cannot.
     */
    public static String requestAnalysis(Id noticeId, Id documentId) {
        register(new Map<Id, Set<Id>>{ noticeId => new Set<Id>{ documentId } }, false);
        List<NXP_Document_Analysis__c> rows = [
            SELECT Id, Status__c, Status_Detail__c
            FROM NXP_Document_Analysis__c
            WHERE Analysis_Key__c = :key(noticeId, documentId)
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new IllegalArgumentException('That file is not attached to this notice.');
        }
        NXP_Document_Analysis__c a = rows[0];
        if (a.Status__c == 'Unsupported' || a.Status__c == 'Too Large') {
            throw new IllegalArgumentException(a.Status_Detail__c);
        }
        if (!isEnabled()) {
            throw new IllegalArgumentException(
                'Document reading is off. An admin turns it on with AI_Enabled and Document_Analysis_Enabled.'
            );
        }
        a.Status__c = 'Pending';
        a.Status_Detail__c = null;
        update a;
        if (!start(new Set<Id>{ a.Id })) {
            return 'Queued; it will be read on the next Notice Analyst run.';
        }
        return 'Reading the document. This usually takes under a minute.';
    }

    /**
     * Notice Id -> number of open document checks: points where a read document disagrees with the
     * notice and nobody has marked them checked yet. Only notices the running user can see.
     */
    public static Map<Id, Integer> openCheckCounts(Set<Id> noticeIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (noticeIds == null || noticeIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult r : [
            SELECT Gov_Notice__c notice, SUM(Check_Count__c) total
            FROM NXP_Document_Analysis__c
            WHERE
                Gov_Notice__c IN :noticeIds
                AND Status__c = 'Complete'
                AND Check_Count__c > 0
                AND Checks_Reviewed__c = NULL
            WITH USER_MODE
            GROUP BY Gov_Notice__c
        ]) {
            Object total = r.get('total');
            counts.put((Id) r.get('notice'), total == null ? 0 : ((Decimal) total).intValue());
        }
        return counts;
    }

    public static Boolean isEnabled() {
        NXP_DocumentAnalyzer a = analyzer();
        return a != null && a.isEnabled();
    }

    public static String key(Id noticeId, Id docId) {
        return String.valueOf(noticeId).left(18) + ':' + String.valueOf(docId).left(18);
    }

    private static NXP_DocumentAnalyzer analyzer() {
        if (analyzerOverride != null) {
            return analyzerOverride;
        }
        Type t = Type.forName('NXP_DocumentAnalysisJob');
        if (t == null) {
            return null;
        }
        Object o = t.newInstance();
        return o instanceof NXP_DocumentAnalyzer ? (NXP_DocumentAnalyzer) o : null;
    }
}
