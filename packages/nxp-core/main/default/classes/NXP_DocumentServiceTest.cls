@IsTest
private class NXP_DocumentServiceTest {
    private class AnalyzerMock implements NXP_DocumentAnalyzer {
        public Boolean active = true;
        public Set<Id> queued = new Set<Id>();
        public Boolean isEnabled() {
            return active;
        }
        public void enqueue(Set<Id> analysisIds) {
            queued.addAll(analysisIds);
        }
    }

    private static NXP_Gov_Notice__c notice() {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'T-DOC-1',
            Title__c = 'Help desk support',
            Status__c = 'Active',
            NAICS_Code__c = '541513',
            Response_Due__c = Datetime.newInstanceGmt(2026, 11, 19, 19, 0, 0)
        );
        insert n;
        return n;
    }

    private static Id attach(Id recordId, String fileName, Blob body) {
        ContentVersion v = new ContentVersion(
            Title = fileName.substringBeforeLast('.'),
            PathOnClient = fileName,
            VersionData = body,
            FirstPublishLocationId = recordId
        );
        insert v;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
    }

    @IsTest
    static void attachingFilesRegistersThemAndStartsPdfs() {
        AnalyzerMock mock = new AnalyzerMock();
        NXP_DocumentService.analyzerOverride = mock;
        NXP_Gov_Notice__c n = notice();

        Id pdf = attach(n.Id, 'Statement of Work.pdf', Blob.valueOf('%PDF-1.4 test'));
        Id docx = attach(n.Id, 'Pricing.xlsx', Blob.valueOf('xlsx'));

        Map<String, NXP_Document_Analysis__c> byFile = new Map<String, NXP_Document_Analysis__c>();
        for (NXP_Document_Analysis__c a : [
            SELECT File_Name__c, Status__c, Status_Detail__c, Content_Document_Id__c
            FROM NXP_Document_Analysis__c
            WHERE Gov_Notice__c = :n.Id
        ]) {
            byFile.put(a.File_Name__c, a);
        }
        System.assertEquals(2, byFile.size());
        System.assertEquals('Pending', byFile.get('Statement of Work.pdf').Status__c);
        System.assertEquals(String.valueOf(pdf), byFile.get('Statement of Work.pdf').Content_Document_Id__c);
        System.assertEquals('Unsupported', byFile.get('Pricing.xlsx').Status__c);
        System.assertEquals(1, mock.queued.size(), 'only the PDF is queued');

        // Registering the same file again adds nothing.
        System.assertNotEquals(null, docx);
        NXP_DocumentService.register(new Map<Id, Set<Id>>{ n.Id => new Set<Id>{ pdf } }, true);
        System.assertEquals(2, [SELECT COUNT() FROM NXP_Document_Analysis__c]);
    }

    @IsTest
    static void limitsAndOffSwitch() {
        AnalyzerMock mock = new AnalyzerMock();
        mock.active = false;
        NXP_DocumentService.analyzerOverride = mock;
        NXP_Settings.setForTest('Document_Max_Per_Notice', '1');
        NXP_Settings.setForTest('Document_Max_MB', '0.00001');
        NXP_Gov_Notice__c n = notice();

        attach(n.Id, 'Big.pdf', Blob.valueOf('%PDF-1.4 ' + 'x'.repeat(100)));
        NXP_Settings.setForTest('Document_Max_MB', '10');
        Id second = attach(n.Id, 'Second.pdf', Blob.valueOf('%PDF-1.4 second'));

        System.assertEquals(
            'Too Large',
            [SELECT Status__c FROM NXP_Document_Analysis__c WHERE File_Name__c = 'Big.pdf'].Status__c
        );
        NXP_Document_Analysis__c s = [
            SELECT Status__c, Status_Detail__c
            FROM NXP_Document_Analysis__c
            WHERE File_Name__c = 'Second.pdf'
        ];
        System.assertEquals('Pending', s.Status__c);
        System.assert(s.Status_Detail__c.contains('Click Analyze'));
        System.assertEquals(0, mock.queued.size(), 'analysis is off');

        try {
            NXP_DocumentService.requestAnalysis(n.Id, second);
            System.assert(false, 'expected an error while off');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('off'));
        }
        mock.active = true;
        System.assert(NXP_DocumentService.requestAnalysis(n.Id, second).startsWith('Reading'));
        System.assertEquals(1, mock.queued.size());
        System.assertEquals(
            null,
            [SELECT Status_Detail__c FROM NXP_Document_Analysis__c WHERE File_Name__c = 'Second.pdf'].Status_Detail__c
        );
    }

    @IsTest
    static void bypassSkipsRegistration() {
        NXP_TriggerHandler.bypass(NXP_DocumentService.HANDLER);
        NXP_Gov_Notice__c n = notice();
        attach(n.Id, 'A.pdf', Blob.valueOf('%PDF-1.4'));
        System.assertEquals(0, [SELECT COUNT() FROM NXP_Document_Analysis__c]);
    }

    @IsTest
    static void parserKeepsKnownFieldsAndComparesWithTheNotice() {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            NAICS_Code__c = '541513',
            Response_Due__c = Datetime.newInstanceGmt(2026, 11, 19, 19, 0, 0)
        );
        Map<String, Object> r = NXP_DocumentAnalysisParser.parse(
            '```json\n{"summary":"Help desk\\nsupport","documentType":"Statement","naics":"541512",' +
                '"requirements":["A","B",{"x":1}],"submission":{"dueDate":"2026-11-12T14:00:00-05:00","pageLimit":"10 pages","questionsDue":"next week"},' +
                '"keyDates":[{"label":"Industry day","date":"2026-11-02"},{"label":"Bad","date":"soon"}],' +
                '"clearance":"Secret","setAside":"Total Small Business","ignored":"x"}\n```',
            n
        );
        System.assertEquals('Help desk support', r.get('summary'));
        System.assertEquals('Other', r.get('documentType'));
        System.assertEquals(2, ((List<Object>) r.get('requirements')).size());
        System.assertEquals(1, ((List<Object>) r.get('keyDates')).size());
        Map<String, Object> s = (Map<String, Object>) r.get('submission');
        System.assertEquals('2026-11-12T14:00:00-05:00', s.get('dueDate'));
        System.assert(!s.containsKey('questionsDue'), 'not a date');
        System.assert(!r.containsKey('ignored'));
        String all = String.join((List<String>) r.get('checks'), ' | ');
        System.assert(all.contains('due 2026-11-12'), all);
        System.assert(all.contains('NAICS 541512'), all);
        System.assert(all.contains('set-aside'), all);
        System.assert(all.contains('Clearance requirement: Secret'), all);
        List<Map<String, Object>> items = (List<Map<String, Object>>) r.get('checkItems');
        System.assertEquals(3, items.size(), 'Clearance is information, not a disagreement');
        System.assertEquals('Response due', items[0].get('field'));
        System.assertEquals('2026-11-19', items[0].get('notice'));
        System.assertEquals('2026-11-12', items[0].get('document'));
        System.assertEquals('NAICS', items[1].get('field'));
        System.assertEquals('Set-aside', items[2].get('field'));

        try {
            NXP_DocumentAnalysisParser.parse('I could not open the file.', n);
            System.assert(false, 'expected an error');
        } catch (NXP_DocumentAnalysisParser.AnalysisException e) {
            System.assert(e.getMessage().contains('JSON'));
        }
        System.assert(
            !NXP_DocumentAnalysisParser.parse('{"naics":"5415","clearance":"None"}', n).containsKey('checks')
        );
    }

    @IsTest
    static void openCheckCountsSkipReviewedAndUnread() {
        NXP_Gov_Notice__c n = notice();
        insert new List<NXP_Document_Analysis__c>{
            new NXP_Document_Analysis__c(
                Gov_Notice__c = n.Id,
                Content_Document_Id__c = '069000000000001',
                Analysis_Key__c = 'k1',
                Status__c = 'Complete',
                Check_Count__c = 2
            ),
            new NXP_Document_Analysis__c(
                Gov_Notice__c = n.Id,
                Content_Document_Id__c = '069000000000002',
                Analysis_Key__c = 'k2',
                Status__c = 'Complete',
                Check_Count__c = 1,
                Checks_Reviewed__c = Datetime.now()
            ),
            new NXP_Document_Analysis__c(
                Gov_Notice__c = n.Id,
                Content_Document_Id__c = '069000000000003',
                Analysis_Key__c = 'k3',
                Status__c = 'Pending'
            )
        };
        System.assertEquals(2, NXP_DocumentService.openCheckCounts(new Set<Id>{ n.Id }).get(n.Id));
        System.assert(NXP_DocumentService.openCheckCounts(new Set<Id>()).isEmpty());
    }
}
