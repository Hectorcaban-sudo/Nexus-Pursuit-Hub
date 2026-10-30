/**
 * Data for the admin Inbound Emails screen (nxpEmailLog): every e-mail the eBuy inbox received,
 * what was read from it, the notice it became, and Reprocess / Ignore. Nexus admins only; the
 * Inbound Email object is private and only NXP_Admin grants access to it.
 */
public with sharing class NXP_EmailLogController {
    private static final List<String> STATUSES = new List<String>{
        'Received',
        'Ingested',
        'Needs Review',
        'Rejected',
        'Failed',
        'Ignored'
    };

    public class EmailRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Datetime received;
        @AuraEnabled
        public String fromAddress;
        @AuraEnabled
        public String fromName;
        @AuraEnabled
        public String subject;
        @AuraEnabled
        public String rfqNumber;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String statusDetail;
        @AuraEnabled
        public String method;
        @AuraEnabled
        public Integer attachments;
        @AuraEnabled
        public Id vehicleId;
        @AuraEnabled
        public String vehicleName;
        @AuraEnabled
        public Id noticeId;
        @AuraEnabled
        public String noticeKey;
        @AuraEnabled
        public String noticeTitle;
    }

    public class EmailFile {
        @AuraEnabled
        public Id documentId;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String extension;
        @AuraEnabled
        public Integer size;
    }

    public class EmailDetail {
        @AuraEnabled
        public EmailRow row;
        @AuraEnabled
        public String toAddresses;
        @AuraEnabled
        public String body;
        @AuraEnabled
        public String extractedJson;
        @AuraEnabled
        public Datetime processed;
        @AuraEnabled
        public List<EmailFile> files = new List<EmailFile>();
    }

    public class StatusCount {
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer count = 0;
        public StatusCount(String status) {
            this.status = status;
        }
    }

    public class EmailLog {
        @AuraEnabled
        public List<EmailRow> rows = new List<EmailRow>();
        /** Last 30 days, by status. */
        @AuraEnabled
        public List<StatusCount> counts = new List<StatusCount>();
        @AuraEnabled
        public Integer last30 = 0;
        @AuraEnabled
        public String allowedSenders;
        @AuraEnabled
        public Boolean aiEnabled = false;
    }

    @AuraEnabled
    public static EmailLog getEmails(String status, String search, Integer rowLimit) {
        requireAdmin();
        try {
            EmailLog log = new EmailLog();
            List<String> clauses = new List<String>();
            Map<String, Object> binds = new Map<String, Object>();
            if (String.isNotBlank(status)) {
                clauses.add('Status__c = :status');
                binds.put('status', status);
            }
            if (String.isNotBlank(search)) {
                clauses.add('(Subject__c LIKE :q OR From_Address__c LIKE :q OR RFQ_Number__c LIKE :q OR Name LIKE :q)');
                binds.put('q', '%' + search.trim() + '%');
            }
            binds.put('lim', rowLimit == null || rowLimit < 1 || rowLimit > 500 ? 100 : rowLimit);
            String soql =
                'SELECT ' +
                ROW_FIELDS +
                ' FROM NXP_Inbound_Email__c' +
                (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ')) +
                ' ORDER BY Received__c DESC NULLS LAST, Name DESC LIMIT :lim';
            List<NXP_Inbound_Email__c> emails = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
            for (NXP_Inbound_Email__c em : emails) {
                log.rows.add(toRow(em));
            }

            Map<String, StatusCount> byStatus = new Map<String, StatusCount>();
            for (String s : STATUSES) {
                byStatus.put(s, new StatusCount(s));
            }
            Datetime since = Datetime.now().addDays(-30);
            for (AggregateResult r : [
                SELECT Status__c st, COUNT(Id) n
                FROM NXP_Inbound_Email__c
                WHERE Received__c >= :since
                WITH USER_MODE
                GROUP BY Status__c
            ]) {
                String s = (String) r.get('st');
                if (byStatus.containsKey(s)) {
                    byStatus.get(s).count = (Integer) r.get('n');
                    log.last30 += (Integer) r.get('n');
                }
            }
            log.counts = byStatus.values();
            log.allowedSenders = NXP_Settings.getString('Ebuy_Allowed_Senders', 'gsa.gov');
            log.aiEnabled = NXP_Settings.getBoolean('AI_Enabled', false);
            return log;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static EmailDetail getEmail(Id emailId) {
        requireAdmin();
        try {
            List<NXP_Inbound_Email__c> found = Database.queryWithBinds(
                'SELECT ' +
                    ROW_FIELDS +
                    ', To_Addresses__c, Body__c, Extracted_Json__c, Processed__c FROM NXP_Inbound_Email__c WHERE Id = :emailId',
                new Map<String, Object>{ 'emailId' => emailId },
                AccessLevel.USER_MODE
            );
            if (found.isEmpty()) {
                throw new AuraHandledException('That e-mail no longer exists.');
            }
            NXP_Inbound_Email__c em = found[0];
            EmailDetail d = new EmailDetail();
            d.row = toRow(em);
            d.toAddresses = em.To_Addresses__c;
            d.body = em.Body__c;
            d.extractedJson = em.Extracted_Json__c;
            d.processed = em.Processed__c;
            for (ContentDocumentLink l : [
                SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.FileExtension,
                    ContentDocument.ContentSize
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :emailId
                WITH USER_MODE
            ]) {
                EmailFile f = new EmailFile();
                f.documentId = l.ContentDocumentId;
                f.title = l.ContentDocument.Title;
                f.extension = l.ContentDocument.FileExtension;
                f.size = l.ContentDocument.ContentSize;
                d.files.add(f);
            }
            return d;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Runs extraction again, optionally with an RFQ number typed by the admin. */
    @AuraEnabled
    public static String reprocess(Id emailId, String rfqNumber) {
        requireAdmin();
        try {
            NXP_Inbound_Email__c em = [
                SELECT Id, Status__c, RFQ_Number__c
                FROM NXP_Inbound_Email__c
                WHERE Id = :emailId
                WITH USER_MODE
            ];
            if (em.Status__c == 'Rejected') {
                return 'Rejected e-mails have no attachments to work from. Add the sender to Ebuy_Allowed_Senders and send the e-mail again.';
            }
            if (String.isNotBlank(rfqNumber)) {
                String digits = rfqNumber.trim().toUpperCase().removeStart('RFQ').trim();
                if (!Pattern.matches('\\d{5,9}', digits)) {
                    throw new AuraHandledException(
                        'An RFQ number is RFQ followed by 5 to 9 digits, for example RFQ1234567.'
                    );
                }
                em.RFQ_Number__c = 'RFQ' + digits;
            }
            em.Status__c = 'Received';
            Database.update(em, AccessLevel.USER_MODE);
            System.enqueueJob(new NXP_EbuyExtractJob(em.Id));
            return 'Reprocessing. The status updates in a few seconds.';
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static void ignore(Id emailId) {
        requireAdmin();
        try {
            NXP_Inbound_Email__c em = new NXP_Inbound_Email__c(Id = emailId, Status__c = 'Ignored');
            Database.update(em, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------------------- helpers

    private static final String ROW_FIELDS =
        'Id, Name, Received__c, From_Address__c, From_Name__c, Subject__c, RFQ_Number__c, Status__c, ' +
        'Status_Detail__c, Extraction_Method__c, Attachment_Count__c, Contract_Vehicle__c, Contract_Vehicle__r.Name, ' +
        'Gov_Notice__c, Gov_Notice__r.Notice_Id__c, Gov_Notice__r.Title__c';

    private static EmailRow toRow(NXP_Inbound_Email__c em) {
        EmailRow r = new EmailRow();
        r.id = em.Id;
        r.name = em.Name;
        r.received = em.Received__c;
        r.fromAddress = em.From_Address__c;
        r.fromName = em.From_Name__c;
        r.subject = em.Subject__c;
        r.rfqNumber = em.RFQ_Number__c;
        r.status = em.Status__c;
        r.statusDetail = em.Status_Detail__c;
        r.method = em.Extraction_Method__c;
        r.attachments = em.Attachment_Count__c == null ? 0 : em.Attachment_Count__c.intValue();
        r.vehicleId = em.Contract_Vehicle__c;
        r.vehicleName = em.Contract_Vehicle__c == null ? null : em.Contract_Vehicle__r.Name;
        r.noticeId = em.Gov_Notice__c;
        if (em.Gov_Notice__c != null) {
            r.noticeKey = em.Gov_Notice__r.Notice_Id__c;
            r.noticeTitle = em.Gov_Notice__r.Title__c;
        }
        return r;
    }

    private static void requireAdmin() {
        if (!FeatureManagement.checkPermission('NXP_Admin_Access')) {
            throw new AuraHandledException('Only Nexus admins can see inbound e-mail.');
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
