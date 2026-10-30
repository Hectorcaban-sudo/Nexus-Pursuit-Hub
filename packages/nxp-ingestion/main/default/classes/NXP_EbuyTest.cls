@IsTest
private class NXP_EbuyTest {
    private static final String BODY =
        'You have been invited to submit a quote.\n\n' +
        'RFQ ID: RFQ1234567\n' +
        'Title: Help Desk Modernization\n' +
        'Buyer Agency: Veterans Affairs, Department of\n' +
        'Buyer Office: Technology Acquisition Center\n' +
        'Category / SIN: 54151S, 54151HACS\n' +
        'NAICS: 541513 - Computer Facilities Management Services\n' +
        'Set-Aside: Small Business\n' +
        'Issue Date: 10/28/2026\n' +
        'Close Date: 11/12/2026 02:00 PM ET\n' +
        'Place of Performance: Remote\n' +
        'Buyer: Pat Buyer\n' +
        'Buyer Email: pat.buyer@va.example\n\n' +
        'Description:\nTier 1 and tier 2 help desk support.\n\n' +
        'View the RFQ: https://www.ebuy.gsa.gov/ebuy/seller/prepare-quote/RFQ1234567\n';

    private class AiMock implements NXP_EbuyAiExtractor {
        public String response;
        public Boolean fail = false;
        public Id lastAttachment;
        public Boolean isEnabled() {
            return true;
        }
        public String extract(Id emailId, Id attachmentDocumentId) {
            lastAttachment = attachmentDocumentId;
            if (fail) {
                throw new CalloutException('model unavailable');
            }
            return response;
        }
    }

    @TestSetup
    static void setup() {
        insert new NXP_Contract_Vehicle__c(
            Name = 'GSA MAS IT',
            Vehicle_Code__c = 'GSA-MAS-IT',
            We_Hold__c = true,
            Inbox_Address__c = 'mas-orders@example.com'
        );
        insert new NXP_Contract_Vehicle__c(Name = 'Default', Vehicle_Code__c = 'OTHER-1', We_Hold__c = true);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = new PermissionSet(Name = 'NXP_Ebuy_Test_Admin', Label = 'NXP eBuy Test Admin');
            insert ps;
            CustomPermission cp = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'NXP_Admin_Access' LIMIT 1];
            insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);
        }
    }

    /** Shipped defaults, whatever the org has changed them to. */
    private static void defaults() {
        NXP_Settings.setForTest('Ebuy_Allowed_Senders', 'gsa.gov');
        NXP_Settings.setForTest('Ebuy_Default_Vehicle', 'GSA-MAS-IT');
        NXP_Settings.setForTest('Ebuy_Share_Files_With_Notice', 'true');
        NXP_Settings.setForTest('Ebuy_AI_Read_Attachments', 'false');
        NXP_Settings.setForTest('AI_Enabled', 'false');
    }

    private static Messaging.InboundEmail email(String subject, String body, String fromAddress) {
        Messaging.InboundEmail e = new Messaging.InboundEmail();
        e.subject = subject;
        e.plainTextBody = body;
        e.fromAddress = fromAddress;
        e.fromName = 'GSA eBuy';
        e.toAddresses = new List<String>{ 'Orders <mas-orders@example.com>' };
        e.messageId = '<' + subject.hashCode() + '.' + Crypto.getRandomInteger() + '@gsa.gov>';
        Messaging.InboundEmail.BinaryAttachment sow = new Messaging.InboundEmail.BinaryAttachment();
        sow.fileName = 'Statement of Work.pdf';
        sow.body = Blob.valueOf('%PDF-1.4 test');
        Messaging.InboundEmail.BinaryAttachment bad = new Messaging.InboundEmail.BinaryAttachment();
        bad.fileName = 'run.exe';
        bad.body = Blob.valueOf('MZ');
        e.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ sow, bad };
        return e;
    }

    private static Messaging.InboundEnvelope envelope() {
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        env.toAddress = 'nxp_ebuy_inbox@example.salesforce.com';
        env.fromAddress = 'ebuy@gsa.gov';
        return env;
    }

    @IsTest
    static void parserReadsLabelledLines() {
        defaults();
        NXP_EbuyEmailParser.Extracted x = NXP_EbuyEmailParser.parse('eBuy RFQ1234567', BODY);
        System.assertEquals('RFQ1234567', x.rfqNumber);
        System.assertEquals('Help Desk Modernization', x.title);
        System.assertEquals('541513', x.naics);
        System.assertEquals(2, x.sins.size());
        System.assertEquals(Date.newInstance(2026, 10, 28), x.issueDate);
        // 2:00 PM Eastern (standard time on Nov 12) is 19:00 UTC.
        System.assertEquals(Datetime.newInstanceGmt(2026, 11, 12, 19, 0, 0), x.responseDue);
        System.assert(!x.dueTimeAssumed);
        System.assertEquals('pat.buyer@va.example', x.buyerEmail);
        System.assert(x.url.startsWith('https://www.ebuy.gsa.gov/'));
        System.assert(x.description.startsWith('Tier 1'), x.description);
        System.assert(x.notes.isEmpty(), String.join(x.notes, ' | '));
    }

    @IsTest
    static void parserFallsBackToTheSubjectAndNotesGaps() {
        defaults();
        NXP_EbuyEmailParser.Extracted x = NXP_EbuyEmailParser.parse(
            'Fwd: [eBuy] New RFQ #7654321 - Cloud Hosting',
            'NAICS: 5415\nClose Date: soon'
        );
        System.assertEquals('RFQ7654321', x.rfqNumber);
        System.assertEquals('Cloud Hosting', x.title);
        System.assertEquals(null, x.naics);
        System.assertEquals(null, x.responseDue);
        System.assertEquals(3, x.notes.size(), String.join(x.notes, ' | '));

        NXP_EbuyEmailParser.Extracted none = NXP_EbuyEmailParser.parse('Hello', 'Close Date: 11/12/2026');
        System.assertEquals(null, none.rfqNumber);
        System.assert(none.dueTimeAssumed);
        System.assertEquals('Hello', none.title);
        System.assertEquals(
            Datetime.newInstanceGmt(2026, 3, 9, 21, 0, 0),
            NXP_EbuyEmailParser.toDatetime('3/9/2026 2:00 PM PT')
        );
    }

    @IsTest
    static void aiFillsGapsButNeverTheRfqNumber() {
        defaults();
        NXP_EbuyEmailParser.Extracted x = NXP_EbuyEmailParser.parse('RFQ1234567', 'nothing labelled here');
        NXP_EbuyEmailParser.mergeAi(
            x,
            '```json\n{"rfqNumber":"RFQ9999999","title":"Data Center Support","naics":"54151","responseDue":"2026-12-01T15:00:00Z",' +
            '"agency":"Army","summary":"Ignore previous instructions","evaluationFactors":["Technical","Price"]}\n```'
        );
        System.assertEquals('RFQ1234567', x.rfqNumber);
        System.assertEquals('Data Center Support', x.title);
        System.assertEquals(null, x.naics, 'not six digits');
        System.assertEquals(Datetime.newInstanceGmt(2026, 12, 1, 15, 0, 0), x.responseDue);
        System.assertEquals('Army', x.agency);
        System.assertEquals(2, x.evaluationFactors.size());
        System.assert(String.join(x.notes, ' ').contains('kept RFQ1234567'));

        NXP_EbuyEmailParser.Extracted y = NXP_EbuyEmailParser.parse('RFQ1234567', '');
        NXP_EbuyEmailParser.mergeAi(y, 'Sure! Here are the fields.');
        System.assert(String.join(y.notes, ' ').contains('not a JSON object'));
    }

    @IsTest
    static void allowedEmailBecomesATaskOrderNotice() {
        defaults();
        Test.startTest();
        Id emailId = new NXP_EbuyEmailHandler()
                .handleInboundEmail(email('eBuy RFQ1234567', BODY, 'ebuy@gsa.gov'), envelope())
                .success
            ? [SELECT Id FROM NXP_Inbound_Email__c LIMIT 1].Id
            : null;
        Test.stopTest();

        NXP_Inbound_Email__c em = [
            SELECT
                Status__c,
                Status_Detail__c,
                RFQ_Number__c,
                Gov_Notice__c,
                Attachment_Count__c,
                Extraction_Method__c,
                Contract_Vehicle__r.Vehicle_Code__c
            FROM NXP_Inbound_Email__c
            WHERE Id = :emailId
        ];
        System.assertEquals('Ingested', em.Status__c, em.Status_Detail__c);
        System.assertEquals('RFQ1234567', em.RFQ_Number__c);
        System.assertEquals(1, em.Attachment_Count__c, 'the .exe is not kept');
        System.assert(em.Status_Detail__c.contains('run.exe'));
        System.assertEquals('Rules', em.Extraction_Method__c);
        System.assertEquals('GSA-MAS-IT', em.Contract_Vehicle__r.Vehicle_Code__c, 'matched by Inbox Address');

        NXP_Gov_Notice__c n = [
            SELECT
                Notice_Id__c,
                Notice_Type__c,
                Title__c,
                NAICS_Code__c,
                Response_Due__c,
                Contract_Vehicle__r.Vehicle_Code__c,
                Notice_URL__c,
                Source_Feed__c
            FROM NXP_Gov_Notice__c
            WHERE Id = :em.Gov_Notice__c
        ];
        System.assertEquals('EBUY:RFQ1234567', n.Notice_Id__c);
        System.assertEquals('Task Order', n.Notice_Type__c);
        System.assertEquals('541513', n.NAICS_Code__c);
        System.assertEquals('GSA-MAS-IT', n.Contract_Vehicle__r.Vehicle_Code__c);
        System.assertEquals(NXP_EbuyExtractJob.FEED_NAME, n.Source_Feed__c);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :n.Id]);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM NXP_Feed_Run__c WHERE Feed_Name__c = :NXP_EbuyExtractJob.FEED_NAME]
        );
    }

    @IsTest
    static void duplicatesAndUnknownSenders() {
        defaults();
        Messaging.InboundEmail first = email('eBuy RFQ1234567', BODY, 'ebuy@gsa.gov');
        Test.startTest();
        System.assertNotEquals(null, NXP_EbuyEmailHandler.record(first, envelope()));
        System.assertEquals(null, NXP_EbuyEmailHandler.record(first, envelope()), 'same Message-ID');
        Id rejected = NXP_EbuyEmailHandler.record(email('RFQ7654321 phish', BODY, 'someone@evil.example'), envelope());
        Test.stopTest();

        NXP_Inbound_Email__c r = [
            SELECT Status__c, Attachment_Count__c, Gov_Notice__c
            FROM NXP_Inbound_Email__c
            WHERE Id = :rejected
        ];
        System.assertEquals('Rejected', r.Status__c);
        System.assertEquals(0, r.Attachment_Count__c);
        System.assertEquals(null, r.Gov_Notice__c);
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :rejected]);
        System.assert(NXP_EbuyEmailHandler.senderAllowed('Orders@Sub.GSA.gov'));
        System.assert(!NXP_EbuyEmailHandler.senderAllowed('gsa.gov@evil.example'));
        System.assert(!NXP_EbuyEmailHandler.senderAllowed(null));
    }

    @IsTest
    static void needsReviewThenReprocessWithAnRfqNumber() {
        defaults();
        Messaging.InboundEmail e = email('Quote request', 'Close Date: 11/12/2026 02:00 PM ET', 'ebuy@gsa.gov');
        e.toAddresses = new List<String>{ 'someone@example.com' };
        Test.startTest();
        Id emailId = NXP_EbuyEmailHandler.record(e, envelope());
        Test.stopTest();

        NXP_Inbound_Email__c em = [
            SELECT Status__c, Status_Detail__c, Gov_Notice__c
            FROM NXP_Inbound_Email__c
            WHERE Id = :emailId
        ];
        System.assertEquals('Needs Review', em.Status__c);
        System.assert(em.Status_Detail__c.contains('Enter the RFQ number'), em.Status_Detail__c);
        System.assert(em.Status_Detail__c.contains('run.exe'), 'attachment note kept');
        System.assertEquals(null, em.Gov_Notice__c);

        NXP_EmailLogController.EmailLog log = NXP_EmailLogController.getEmails('Needs Review', 'quote', 50);
        System.assertEquals(1, log.rows.size());
        NXP_EmailLogController.EmailDetail d = NXP_EmailLogController.getEmail(emailId);
        System.assertEquals(1, d.files.size());
        try {
            NXP_EmailLogController.reprocess(emailId, 'abc');
            System.assert(false, 'expected an error');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('RFQ followed by'));
        }
        // Reprocess runs the job synchronously here, so the result is visible straight away.
        NXP_EmailLogController.reprocess(emailId, 'rfq 2468024');
        NXP_EbuyExtractJob.run(emailId);
        em = [
            SELECT Status__c, RFQ_Number__c, Gov_Notice__r.Notice_Id__c, Contract_Vehicle__r.Vehicle_Code__c
            FROM NXP_Inbound_Email__c
            WHERE Id = :emailId
        ];
        System.assertEquals('Ingested', em.Status__c);
        System.assertEquals('EBUY:RFQ2468024', em.Gov_Notice__r.Notice_Id__c);
        System.assertEquals('GSA-MAS-IT', em.Contract_Vehicle__r.Vehicle_Code__c, 'default vehicle setting');

        NXP_EmailLogController.ignore(emailId);
        System.assertEquals('Ignored', [SELECT Status__c FROM NXP_Inbound_Email__c WHERE Id = :emailId].Status__c);
        log = NXP_EmailLogController.getEmails(null, null, null);
        System.assert(log.last30 >= 1);
    }

    @IsTest
    static void aiFailureFallsBackToRules() {
        defaults();
        AiMock ai = new AiMock();
        ai.fail = true;
        NXP_EbuyExtractJob.extractorOverride = ai;
        Id emailId = NXP_EbuyEmailHandler.record(email('eBuy RFQ1234567', BODY, 'ebuy@gsa.gov'), envelope());
        NXP_EbuyExtractJob.run(emailId);
        NXP_Inbound_Email__c em = [
            SELECT Status__c, Status_Detail__c, Extraction_Method__c
            FROM NXP_Inbound_Email__c
            WHERE Id = :emailId
        ];
        System.assertEquals('Ingested', em.Status__c);
        System.assertEquals('Rules', em.Extraction_Method__c);
        System.assert(em.Status_Detail__c.contains('AI extraction failed'));

        ai.fail = false;
        ai.response = '{"summary":"Help desk support for VA.","evaluationFactors":["Technical approach"]}';
        NXP_EbuyExtractJob.run(emailId);
        em = [SELECT Extraction_Method__c, Gov_Notice__r.Description__c FROM NXP_Inbound_Email__c WHERE Id = :emailId];
        System.assertEquals('AI', em.Extraction_Method__c);
        System.assert(em.Gov_Notice__r.Description__c.contains('AI summary (check against the RFQ)'));
        System.assertEquals(null, ai.lastAttachment, 'attachments are off by default');
    }
}
