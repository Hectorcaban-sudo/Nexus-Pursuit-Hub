// Sends the made-up eBuy RFQ e-mail (data/fixtures/ebuy-sample-email.txt) through the eBuy inbox
// handler, as if GSA eBuy had sent it, so the Inbound Emails screen and the notice EBUY:RFQ9990001
// can be tried without real eBuy mail. Dates are set relative to today. Safe to run again: the
// earlier sample e-mail is replaced and the notice is updated. The notice is created in the
// background (NXP_EbuyExtractJob), a few seconds after this script ends.
String messageId = '<sample-ebuy-rfq9990001@nexus-sample.example>';
List<NXP_Inbound_Email__c> previous = [SELECT Id FROM NXP_Inbound_Email__c WHERE Message_Id__c = :messageId];
if (!previous.isEmpty()) {
    Set<Id> docIds = new Set<Id>();
    for (ContentDocumentLink l : [
        SELECT ContentDocumentId
        FROM ContentDocumentLink
        WHERE LinkedEntityId IN :new Map<Id, NXP_Inbound_Email__c>(previous).keySet()
    ]) {
        docIds.add(l.ContentDocumentId);
    }
    delete previous;
    Database.delete(new List<Id>(docIds), false);
}

Date today = Date.today();
String issued = Datetime.newInstance(today.addDays(-1), Time.newInstance(12, 0, 0, 0)).format('MM/dd/yyyy');
String closes = Datetime.newInstance(today.addDays(14), Time.newInstance(12, 0, 0, 0)).format('MM/dd/yyyy');

Messaging.InboundEmail email = new Messaging.InboundEmail();
email.messageId = messageId;
email.fromAddress = 'ebuy-sample@gsa.gov';
email.fromName = 'GSA eBuy (SAMPLE)';
email.toAddresses = new List<String>{ 'ebuy@yourcompany.example' };
email.subject = '[SAMPLE] eBuy RFQ9990001: Help Desk Modernization and Knowledge Base Support';
email.plainTextBody = String.join(
    new List<String>{
        '[SAMPLE DATA] A made-up eBuy notification for testing Nexus Pursuit Hub. It is not a real RFQ.',
        '',
        'You have been invited to submit a quote for the following Request for Quote (RFQ).',
        '',
        'RFQ ID: RFQ9990001',
        'Title: Help Desk Modernization and Knowledge Base Support',
        'Buyer Agency: Veterans Affairs, Department of',
        'Buyer Office: SAMPLE VA Technology Acquisition Center',
        'Category / SIN: 54151S - Information Technology Professional Services',
        'NAICS: 541513',
        'Set-Aside: None',
        'Issue Date: ' + issued,
        'Close Date: ' + closes + ' 02:00 PM ET',
        'Place of Performance: Remote',
        'Buyer: Sample Buyer',
        'Buyer Email: sample.buyer@va.example',
        '',
        'Description:',
        'Tier 1 and tier 2 help desk support, migration of the current knowledge base to the agency ITSM',
        'tool, and monthly service-level reporting. See the attached statement of work.',
        '',
        'View the RFQ and submit your quote: https://www.ebuy.gsa.gov/ebuy/seller/prepare-quote/RFQ9990001'
    },
    '\n'
);
// A small PDF statement of work, so the Document Reader has something to read.
String sowText =
    '<h2>[SAMPLE DATA] Statement of Work - Help Desk Modernization (RFQ9990001)</h2>' +
    '<p>This is a made-up document for testing Nexus Pursuit Hub.</p>' +
    '<p><b>Scope.</b> Tier 1 and tier 2 help desk support 7:00 AM to 7:00 PM Eastern, Monday to Friday; ' +
    'migration of about 1,200 knowledge base articles to the agency ITSM tool within 90 days; monthly service-level reports.</p>' +
    '<p><b>Period of performance.</b> One 12-month base period and two 12-month option periods.</p>' +
    '<p><b>Place of performance.</b> Remote; staff must be in the United States.</p>' +
    '<p><b>Security.</b> All staff need a Public Trust (Tier 2) background investigation before starting.</p>' +
    '<p><b>Evaluation.</b> Technical approach, then past performance, then price. Award to the best value.</p>' +
    '<p><b>Submission.</b> Quotes are due ' + closes + ' 2:00 PM Eastern through eBuy. Technical volume limited to 10 pages. ' +
    'Questions are due five days before the close date.</p>';
Messaging.InboundEmail.BinaryAttachment sow = new Messaging.InboundEmail.BinaryAttachment();
sow.fileName = 'Statement of Work (SAMPLE).pdf';
try {
    sow.body = Blob.toPdf(sowText);
} catch (Exception e) {
    sow.fileName = 'Statement of Work (SAMPLE).txt';
    sow.body = Blob.valueOf(sowText.stripHtmlTags());
}
email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ sow };

Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
envelope.fromAddress = email.fromAddress;
envelope.toAddress = 'nxp_ebuy_inbox@sample.salesforce.example';

// Recorded as Rejected if the Ebuy_Allowed_Senders setting no longer includes gsa.gov.
Id emailId = NXP_EbuyEmailHandler.record(email, envelope);
System.debug('Sample eBuy e-mail recorded: ' + emailId + '. Notice EBUY:RFQ9990001 follows in a few seconds.');
