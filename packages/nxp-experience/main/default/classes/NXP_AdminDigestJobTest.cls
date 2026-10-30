@IsTest
private class NXP_AdminDigestJobTest {
    @IsTest
    static void digestListsProblemsAndWhatWentFine() {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'DIG-1',
            Title__c = 'Help desk',
            Status__c = 'Active'
        );
        insert n;
        insert new List<NXP_Inbound_Email__c>{
            new NXP_Inbound_Email__c(
                Subject__c = 'IT Service Desk',
                RFQ_Number__c = 'RFQ1789012',
                Status__c = 'Rejected',
                Status_Detail__c = 'Sender not on the allowed list',
                Received__c = Datetime.now().addHours(-2)
            ),
            new NXP_Inbound_Email__c(
                Subject__c = 'Fwd: Opportunity',
                Status__c = 'Needs Review',
                Received__c = Datetime.now().addHours(-30)
            ),
            new NXP_Inbound_Email__c(Subject__c = 'OK', Status__c = 'Ingested', Received__c = Datetime.now())
        };
        insert new NXP_Feed_Run__c(
            Feed_Name__c = 'SAM_Opportunities',
            Status__c = 'Failed',
            Started__c = Datetime.now().addHours(-3),
            Error_Log__c = 'HTTP 429 Too Many Requests\nmore'
        );
        insert new NXP_Document_Analysis__c(
            Gov_Notice__c = n.Id,
            Content_Document_Id__c = '069000000000001',
            Analysis_Key__c = 'dig-1',
            File_Name__c = 'SOW.pdf',
            Status__c = 'Failed',
            Status_Detail__c = 'Too large',
            Analyzed__c = Datetime.now()
        );

        NXP_AdminDigestJob.Digest d = NXP_AdminDigestJob.build(Datetime.now().addDays(-1));
        System.assert(d.problems >= 4, 'eBuy x2, feed, document: ' + d.problems);
        String html = NXP_AdminDigestJob.html(d);
        System.assert(html.contains('RFQ1789012'), html);
        System.assert(html.contains('Waiting since'), html);
        System.assert(html.contains('HTTP 429 Too Many Requests'), html);
        System.assert(!html.contains('more</div>'), 'Only the first line of the error');
        System.assert(html.contains('SOW.pdf'), html);
        System.assert(html.contains('1 eBuy e-mail became notices'), html);

        NXP_Settings.setForTest('Admin_Digest_Recipients', 'admin@example.gov');
        Test.startTest();
        System.assertEquals(1, NXP_AdminDigestJob.run());
        Test.stopTest();
    }

    @IsTest
    static void quietDayAndOffSendNothing() {
        NXP_Settings.setForTest('Admin_Digest_Recipients', 'admin@example.gov');
        NXP_AdminDigestJob.Digest d = NXP_AdminDigestJob.build(Datetime.now().addDays(-1));
        Integer problems = d.problems;
        if (problems == 0) {
            System.assertEquals(0, NXP_AdminDigestJob.run(), 'Problems mode: nothing to report');
            System.assert(NXP_AdminDigestJob.html(d).contains('No problems'));
        }
        NXP_Settings.setForTest('Admin_Digest_Mode', 'Daily');
        System.assertEquals(1, NXP_AdminDigestJob.run(), 'Daily mode always sends');
        NXP_Settings.setForTest('Admin_Digest_Mode', 'Off');
        System.assertEquals(0, NXP_AdminDigestJob.run());
    }

    @IsTest
    static void silentEbuyInboxIsReported() {
        insert new NXP_Inbound_Email__c(
            Subject__c = 'Old',
            Status__c = 'Ingested',
            Received__c = Datetime.now().addDays(-5)
        );
        String html = NXP_AdminDigestJob.html(NXP_AdminDigestJob.build(Datetime.now().addDays(-1)));
        System.assert(html.contains('No eBuy e-mail for 3 days'), html);
    }

    @IsTest
    static void schedules() {
        Test.startTest();
        Id jobId = NXP_AdminDigestJob.scheduleDefaults();
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
