/**
 * Turns one NXP_Inbound_Email__c into a Gov Notice: reads the e-mail with NXP_EbuyEmailParser,
 * fills gaps with AI when NXP_EbuyAiExtract is installed and AI is on, checks the values, and
 * ingests a "Task Order" notice keyed EBUY:<RFQ number> through NXP_IngestionService (so a later
 * e-mail about the same RFQ updates it). Attachments are linked to the notice. The e-mail ends as
 * Ingested, Needs Review (no RFQ number or no close date) or Failed, with the reason.
 */
public without sharing class NXP_EbuyExtractJob implements Queueable, Database.AllowsCallouts {
    public static final String FEED_NAME = 'EMAIL_GSA_eBuy';
    public static final String KEY_PREFIX = 'EBUY:';
    private static final Integer MAX_AI_FILE_BYTES = 10 * 1024 * 1024;

    @TestVisible
    private static NXP_EbuyAiExtractor extractorOverride;

    private final Id emailId;

    public NXP_EbuyExtractJob(Id emailId) {
        this.emailId = emailId;
    }

    public void execute(QueueableContext context) {
        run(emailId);
    }

    public static void run(Id emailId) {
        NXP_Inbound_Email__c em = [
            SELECT
                Id,
                Subject__c,
                Body__c,
                From_Address__c,
                Received__c,
                RFQ_Number__c,
                Status__c,
                Status_Detail__c,
                Contract_Vehicle__c,
                Contract_Vehicle__r.Vehicle_Code__c
            FROM NXP_Inbound_Email__c
            WHERE Id = :emailId
            WITH SYSTEM_MODE
        ];
        if (em.Status__c == 'Rejected' || em.Status__c == 'Ignored') {
            return;
        }
        List<String> keptNotes = attachmentNotes(em.Status_Detail__c);
        try {
            NXP_EbuyEmailParser.Extracted x = NXP_EbuyEmailParser.parse(em.Subject__c, em.Body__c);
            if (String.isNotBlank(em.RFQ_Number__c)) {
                // Entered by an admin before Reprocess, or kept from an earlier run.
                x.rfqNumber = em.RFQ_Number__c.trim().toUpperCase();
                Integer i = x.notes.indexOf('No RFQ number (RFQ followed by digits) in the subject or body.');
                if (i >= 0) {
                    x.notes.remove(i);
                }
            }
            em.Extraction_Method__c = 'Rules';

            NXP_EbuyAiExtractor ai = extractor();
            if (ai != null && ai.isEnabled()) {
                try {
                    String aiText = ai.extract(em.Id, aiAttachment(em.Id));
                    NXP_EbuyEmailParser.mergeAi(x, aiText);
                    em.Extraction_Method__c = 'AI';
                } catch (Exception e) {
                    x.notes.add('AI extraction failed, so only the rules were used: ' + e.getMessage().left(200));
                }
            }

            em.Extracted_Json__c = NXP_Text.truncate(JSON.serializePretty(x, true), 32768);
            em.Processed__c = Datetime.now();
            if (x.rfqNumber == null) {
                em.Status__c = 'Needs Review';
                em.Status_Detail__c = detail(x.notes, keptNotes, 'Enter the RFQ number and click Reprocess.');
                update em;
                return;
            }
            em.RFQ_Number__c = x.rfqNumber;

            NXP_IngestRecord rec = toRecord(x, em);
            NXP_Feed_Run__c feedRun = NXP_FeedRunService.start(FEED_NAME, 'Email', em.From_Address__c);
            NXP_IngestionService.Result result = NXP_IngestionService.ingest(new List<NXP_IngestRecord>{ rec });
            NXP_FeedRunService.recordPage(feedRun.Id, result, null);
            NXP_FeedRunService.finish(feedRun.Id, result.rejected > 0 ? 'Failed' : 'Succeeded');

            Id noticeId = result.results.isEmpty() ? null : result.results[0].recordId;
            if (noticeId == null) {
                em.Status__c = 'Failed';
                em.Status_Detail__c = detail(
                    result.errors,
                    keptNotes,
                    'The notice could not be saved; see the Feed Console run for ' + FEED_NAME + '.'
                );
                update em;
                return;
            }
            em.Gov_Notice__c = noticeId;
            if (NXP_Settings.getBoolean('Ebuy_Share_Files_With_Notice', true)) {
                linkFiles(em.Id, noticeId);
            }
            em.Status__c = x.responseDue == null ? 'Needs Review' : 'Ingested';
            em.Status_Detail__c = detail(
                x.notes,
                keptNotes,
                x.responseDue == null
                    ? 'Notice ' + rec.externalKey + ' was saved without a close date; add it on the notice.'
                    : 'Notice ' + rec.externalKey + ' ' + result.results[0].status.toLowerCase() + '.'
            );
            update em;
        } catch (Exception e) {
            em.Status__c = 'Failed';
            em.Processed__c = Datetime.now();
            em.Status_Detail__c = detail(new List<String>{ e.getTypeName() + ': ' + e.getMessage() }, keptNotes, null);
            update em;
            NXP_Logger.error('NXP_EbuyExtractJob', 'eBuy e-mail extraction failed', e, em.Id);
            NXP_Logger.flush();
        }
    }

    @TestVisible
    private static NXP_IngestRecord toRecord(NXP_EbuyEmailParser.Extracted x, NXP_Inbound_Email__c em) {
        NXP_IngestRecord rec = new NXP_IngestRecord(NXP_IngestRecord.TYPE_NOTICE, KEY_PREFIX + x.rfqNumber, FEED_NAME);
        rec.sourceId = em.Id;
        rec.put('Title__c', String.isBlank(x.title) ? 'eBuy ' + x.rfqNumber : x.title);
        rec.put('Solicitation_Number__c', x.rfqNumber);
        rec.put('Notice_Type__c', 'Task Order');
        rec.put('Status__c', 'Active');
        rec.put('Market__c', 'Federal');
        rec.put('NAICS_Code__c', x.naics);
        rec.put('Set_Aside__c', x.setAside);
        rec.put('Posted_Date__c', x.issueDate != null ? x.issueDate : em.Received__c.date());
        rec.put('Response_Due__c', x.responseDue);
        rec.put('Notice_URL__c', x.url);
        rec.put('Place_Of_Performance__c', x.placeOfPerformance);
        rec.put('Office__c', x.office);
        // eBuy names agencies its own way; keep the text rather than creating agency records from it.
        rec.put('Agency_Path__c', x.agency);
        rec.put('Description__c', description(x));
        rec.put('Source_Feed__c', FEED_NAME);
        rec.vehicleCode = em.Contract_Vehicle__c == null ? null : em.Contract_Vehicle__r.Vehicle_Code__c;
        if (String.isNotBlank(x.buyerName) || String.isNotBlank(x.buyerEmail)) {
            NXP_IngestRecord.ContactInfo buyer = new NXP_IngestRecord.ContactInfo();
            buyer.fullName = String.isBlank(x.buyerName) ? x.buyerEmail : x.buyerName;
            buyer.email = x.buyerEmail;
            buyer.role = 'Buyer';
            rec.contacts.add(buyer);
        }
        return rec;
    }

    private static String description(NXP_EbuyEmailParser.Extracted x) {
        List<String> parts = new List<String>{ 'Received by e-mail from GSA eBuy (' + x.rfqNumber + ').' };
        if (!x.sins.isEmpty()) {
            parts.add('SINs: ' + String.join(x.sins, ', '));
        }
        if (String.isNotBlank(x.description)) {
            parts.add(x.description);
        }
        if (String.isNotBlank(x.summary)) {
            parts.add('AI summary (check against the RFQ): ' + x.summary);
        }
        if (!x.evaluationFactors.isEmpty()) {
            parts.add('Evaluation factors (AI): ' + String.join(x.evaluationFactors, '; '));
        }
        return NXP_Text.truncate(String.join(parts, '\n\n'), 131072);
    }

    private static NXP_EbuyAiExtractor extractor() {
        if (extractorOverride != null) {
            return extractorOverride;
        }
        Type t = Type.forName('NXP_EbuyAiExtract');
        if (t == null) {
            return null;
        }
        Object o = t.newInstance();
        return o instanceof NXP_EbuyAiExtractor ? (NXP_EbuyAiExtractor) o : null;
    }

    /** The first PDF up to 10 MB, when Ebuy_AI_Read_Attachments is on. */
    private static Id aiAttachment(Id emailId) {
        if (!NXP_Settings.getBoolean('Ebuy_AI_Read_Attachments', false)) {
            return null;
        }
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId, ContentDocument.FileExtension, ContentDocument.ContentSize
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :emailId
            WITH SYSTEM_MODE
        ]) {
            if (
                l.ContentDocument.FileExtension != null &&
                l.ContentDocument.FileExtension.toLowerCase() == 'pdf' &&
                l.ContentDocument.ContentSize <= MAX_AI_FILE_BYTES
            ) {
                return l.ContentDocumentId;
            }
        }
        return null;
    }

    private static void linkFiles(Id emailId, Id noticeId) {
        Set<Id> docs = new Set<Id>();
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :emailId
            WITH SYSTEM_MODE
        ]) {
            docs.add(l.ContentDocumentId);
        }
        if (docs.isEmpty()) {
            return;
        }
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :noticeId AND ContentDocumentId IN :docs
            WITH SYSTEM_MODE
        ]) {
            docs.remove(l.ContentDocumentId);
        }
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Id doc : docs) {
            links.add(new ContentDocumentLink(ContentDocumentId = doc, LinkedEntityId = noticeId, ShareType = 'V'));
        }
        insert links;
    }

    /** Notes the handler wrote about skipped attachments survive a Reprocess. */
    private static List<String> attachmentNotes(String existing) {
        List<String> out = new List<String>();
        if (String.isNotBlank(existing)) {
            for (String line : existing.split('\n')) {
                if (line.startsWith('Attachments not kept:')) {
                    out.add(line);
                }
            }
        }
        return out;
    }

    private static String detail(List<String> notes, List<String> kept, String lead) {
        List<String> lines = new List<String>();
        if (String.isNotBlank(lead)) {
            lines.add(lead);
        }
        lines.addAll(notes);
        lines.addAll(kept);
        return NXP_Text.truncate(String.join(lines, '\n'), 4000);
    }
}
