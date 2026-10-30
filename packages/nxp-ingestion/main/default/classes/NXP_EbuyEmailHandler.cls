/**
 * Inbound e-mail handler for GSA eBuy RFQ notifications (Email Service NXP_Ebuy_Inbox).
 * Records every e-mail as an NXP_Inbound_Email__c, saves its attachments as Files on that record,
 * and queues NXP_EbuyExtractJob to turn it into a Gov Notice. Senders not listed in the
 * Ebuy_Allowed_Senders setting are recorded as Rejected and their attachments are not kept.
 * Runs as the e-mail service's context user; without sharing so the record is always written.
 * Always reports success, so nothing bounces back to GSA or the forwarder.
 */
global without sharing class NXP_EbuyEmailHandler implements Messaging.InboundEmailHandler {
    @TestVisible
    private static final Integer MAX_ATTACHMENTS = 10;
    private static final Set<String> BLOCKED_EXTENSIONS = new Set<String>{
        'exe',
        'bat',
        'cmd',
        'com',
        'js',
        'vbs',
        'ps1',
        'scr',
        'msi',
        'jar',
        'html',
        'htm',
        'svg'
    };

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        result.success = true;
        try {
            record(email, envelope);
        } catch (Exception e) {
            NXP_Logger.error('NXP_EbuyEmailHandler', 'Could not record an inbound e-mail', e, null);
            NXP_Logger.flush();
        }
        return result;
    }

    /** Saves the e-mail and its attachments; returns the record Id (null for a duplicate). */
    public static Id record(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        String messageId = String.isBlank(email.messageId) ? null : email.messageId.trim().left(255);
        if (
            messageId != null &&
            ![SELECT Id FROM NXP_Inbound_Email__c WHERE Message_Id__c = :messageId LIMIT 1].isEmpty()
        ) {
            return null;
        }
        String fromAddress = email.fromAddress == null
            ? (envelope == null ? null : envelope.fromAddress)
            : email.fromAddress;
        List<String> recipients = new List<String>();
        if (email.toAddresses != null) {
            recipients.addAll(email.toAddresses);
        }
        if (email.ccAddresses != null) {
            recipients.addAll(email.ccAddresses);
        }
        String body = String.isNotBlank(email.plainTextBody)
            ? email.plainTextBody
            : (email.htmlBody == null ? '' : email.htmlBody.stripHtmlTags());

        NXP_Inbound_Email__c rec = new NXP_Inbound_Email__c(
            Message_Id__c = messageId,
            From_Address__c = isEmail(fromAddress) ? fromAddress.left(80) : null,
            From_Name__c = NXP_Text.truncate(email.fromName, 255),
            To_Addresses__c = NXP_Text.truncate(String.join(recipients, ', '), 255),
            Subject__c = NXP_Text.truncate(email.subject, 255),
            Received__c = Datetime.now(),
            Body__c = NXP_Text.truncate(body, 131072),
            Status__c = 'Received',
            Attachment_Count__c = 0
        );
        rec.Contract_Vehicle__c = vehicleFor(recipients);

        if (!senderAllowed(fromAddress)) {
            rec.Status__c = 'Rejected';
            rec.Status_Detail__c =
                'Sender ' +
                fromAddress +
                ' is not in the Ebuy_Allowed_Senders setting, so no notice was created and attachments were not kept. ' +
                'If this sender is yours (for example, a colleague forwarding eBuy e-mail), add the address or its domain to the setting and send the e-mail again.';
            rec.Processed__c = Datetime.now();
            insert rec;
            return rec.Id;
        }
        insert rec;

        List<String> skipped = new List<String>();
        List<ContentVersion> files = new List<ContentVersion>();
        if (email.binaryAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment a : email.binaryAttachments) {
                addFile(files, skipped, rec.Id, a.fileName, a.body);
            }
        }
        if (email.textAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment a : email.textAttachments) {
                addFile(files, skipped, rec.Id, a.fileName, a.body == null ? null : Blob.valueOf(a.body));
            }
        }
        if (!files.isEmpty()) {
            insert files;
        }
        rec.Attachment_Count__c = files.size();
        if (!skipped.isEmpty()) {
            rec.Status_Detail__c = 'Attachments not kept: ' + String.join(skipped, ', ') + '.';
        }
        update rec;

        System.enqueueJob(new NXP_EbuyExtractJob(rec.Id));
        return rec.Id;
    }

    /** True when the address, or its domain, is listed in Ebuy_Allowed_Senders (default gsa.gov). */
    @TestVisible
    private static Boolean senderAllowed(String fromAddress) {
        if (!isEmail(fromAddress)) {
            return false;
        }
        String sender = fromAddress.trim().toLowerCase();
        String domain = sender.substringAfter('@');
        for (String entry : NXP_Text.splitList(NXP_Settings.getString('Ebuy_Allowed_Senders', 'gsa.gov'))) {
            String e = entry.trim().toLowerCase().removeStart('@');
            if (String.isBlank(e)) {
                continue;
            }
            if (e.contains('@') ? sender == e : (domain == e || domain.endsWith('.' + e))) {
                return true;
            }
        }
        return false;
    }

    /** The vehicle whose Inbox Address is a recipient; else the Ebuy_Default_Vehicle code. */
    @TestVisible
    private static Id vehicleFor(List<String> recipients) {
        Set<String> addresses = new Set<String>();
        for (String r : recipients) {
            Matcher m = Pattern.compile('[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+').matcher(r);
            while (m.find()) {
                addresses.add(m.group(0).toLowerCase());
            }
        }
        if (!addresses.isEmpty()) {
            for (NXP_Contract_Vehicle__c v : [
                SELECT Id, Inbox_Address__c
                FROM NXP_Contract_Vehicle__c
                WHERE Inbox_Address__c IN :addresses
                LIMIT 1
            ]) {
                return v.Id;
            }
        }
        String code = NXP_Settings.getString('Ebuy_Default_Vehicle', 'GSA-MAS-IT');
        if (String.isBlank(code)) {
            return null;
        }
        List<NXP_Contract_Vehicle__c> fallback = [
            SELECT Id
            FROM NXP_Contract_Vehicle__c
            WHERE Vehicle_Code__c = :code
            LIMIT 1
        ];
        return fallback.isEmpty() ? null : fallback[0].Id;
    }

    private static void addFile(
        List<ContentVersion> files,
        List<String> skipped,
        Id recordId,
        String fileName,
        Blob body
    ) {
        String name = String.isBlank(fileName) ? 'attachment' : fileName.left(255);
        String extension = name.contains('.') ? name.substringAfterLast('.').toLowerCase() : '';
        if (body == null || body.size() == 0) {
            return;
        }
        if (BLOCKED_EXTENSIONS.contains(extension)) {
            skipped.add(name + ' (file type not allowed)');
            return;
        }
        if (files.size() >= MAX_ATTACHMENTS) {
            skipped.add(name + ' (more than ' + MAX_ATTACHMENTS + ' attachments)');
            return;
        }
        files.add(
            new ContentVersion(
                Title = name.contains('.') ? name.substringBeforeLast('.') : name,
                PathOnClient = name,
                VersionData = body,
                FirstPublishLocationId = recordId
            )
        );
    }

    private static Boolean isEmail(String value) {
        return String.isNotBlank(value) && Pattern.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+', value.trim());
    }
}
