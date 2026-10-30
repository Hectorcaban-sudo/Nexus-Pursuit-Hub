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
Messaging.InboundEmail.TextAttachment sow = new Messaging.InboundEmail.TextAttachment();
sow.fileName = 'Statement of Work (SAMPLE).txt';
sow.body = '[SAMPLE DATA] Statement of work: tier 1 and tier 2 help desk, knowledge base migration, monthly SLA reports.';
email.textAttachments = new List<Messaging.InboundEmail.TextAttachment>{ sow };

Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
envelope.fromAddress = email.fromAddress;
envelope.toAddress = 'nxp_ebuy_inbox@sample.salesforce.example';

// Recorded as Rejected if the Ebuy_Allowed_Senders setting no longer includes gsa.gov.
Id emailId = NXP_EbuyEmailHandler.record(email, envelope);
System.debug('Sample eBuy e-mail recorded: ' + emailId + '. Notice EBUY:RFQ9990001 follows in a few seconds.');
