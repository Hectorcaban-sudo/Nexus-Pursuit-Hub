@IsTest
private class NXP_NoticeAnalysisServiceTest {
    private class FakeAnalyzer implements NXP_NoticeAnalyzer {
        Boolean enabled = true;
        String answer;
        String lastQuestion;
        String lastFacts;
        public Boolean isEnabled() {
            return enabled;
        }
        public String analyze(Id noticeId, String question, String facts) {
            lastQuestion = question;
            lastFacts = facts;
            return answer;
        }
    }

    @TestSetup
    static void data() {
        NXP_Gov_Agency__c agency = new NXP_Gov_Agency__c(
            Name = 'U.S. Customs and Border Protection',
            Full_Path__c = 'Homeland Security > U.S. Customs and Border Protection',
            Agency_Code__c = 'TEST-CBP'
        );
        insert agency;
        NXP_Gov_Vendor__c a = new NXP_Gov_Vendor__c(Name = 'Vendor A', UEI__c = 'UEITESTA0001');
        NXP_Gov_Vendor__c b = new NXP_Gov_Vendor__c(Name = 'Vendor B', UEI__c = 'UEITESTB0001');
        insert new List<NXP_Gov_Vendor__c>{ a, b };
        NXP_Award_Summary__c predecessor = new NXP_Award_Summary__c(
            Name = 'ZTA support',
            PIID__c = '70B0TEST0012',
            Agency__c = agency.Id,
            Vendor__c = a.Id,
            NAICS_Code__c = '541512',
            Obligated_Amount__c = 14200000,
            Period_Start__c = Date.today().addYears(-2),
            Period_End__c = Date.today().addMonths(4)
        );
        insert new List<NXP_Award_Summary__c>{
            predecessor,
            new NXP_Award_Summary__c(
                Name = 'Other',
                PIID__c = '70B0TEST0013',
                Agency__c = agency.Id,
                Vendor__c = b.Id,
                NAICS_Code__c = '541512',
                Obligated_Amount__c = 3000000,
                Period_Start__c = Date.today().addYears(-1),
                Period_End__c = Date.today().addYears(2)
            )
        };
        insert new NXP_Company_Profile__c(
            Name = 'Test profile',
            Active__c = true,
            NAICS_Codes__c = '541512',
            Keywords__c = 'zero trust'
        );
        insert new NXP_Contract_Vehicle__c(Name = 'GSA MAS', Vehicle_Code__c = 'MAS-TEST', We_Hold__c = true);
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'ANALYSIS-1',
            Title__c = 'Zero Trust Architecture Engineering Support',
            Notice_Type__c = 'Solicitation',
            Status__c = 'Active',
            Agency__c = agency.Id,
            Agency_Path__c = agency.Full_Path__c,
            NAICS_Code__c = '541512',
            Response_Due__c = Datetime.now().addDays(21),
            Predecessor_Award__c = predecessor.Id,
            Description__c = 'Engineering support for zero trust architecture.'
        );
        insert n;
        insert new NXP_Document_Analysis__c(
            Gov_Notice__c = n.Id,
            File_Name__c = 'SOW.pdf',
            Status__c = 'Complete',
            Analysis_Key__c = n.Id + ':test',
            Result_Json__c = JSON.serialize(
                new Map<String, Object>{
                    'summary' => 'Zero trust engineering.',
                    'requirements' => new List<Object>{ 'Two CISSP-certified leads', 'Top Secret facility' },
                    'keyDates' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Q&A closes', 'date' => '2026-11-15' }
                    }
                }
            )
        );
    }

    private static Id noticeId() {
        return [SELECT Id FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'ANALYSIS-1'].Id;
    }

    @IsTest
    static void factsComeFromNexusDataWithSources() {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId());
        Map<String, String> bySource = new Map<String, String>();
        for (NXP_NoticeAnalysisService.Fact f : NXP_NoticeAnalysisService.facts(n)) {
            bySource.put(f.source, (bySource.containsKey(f.source) ? bySource.get(f.source) + ' | ' : '') + f.text);
        }
        System.assert(bySource.get('Notice').contains('Zero Trust Architecture'), bySource.get('Notice'));
        System.assert(bySource.get('Incumbent').contains('Vendor A'), bySource.get('Incumbent'));
        System.assert(bySource.get('Award history').contains('Vendor B'), bySource.get('Award history'));
        System.assert(bySource.get('Company Profile').contains('541512'));
        System.assert(bySource.get('Contract vehicles').contains('GSA MAS'));
        System.assert(bySource.get('Document: SOW.pdf').contains('Two CISSP-certified leads'));
        String text = NXP_NoticeAnalysisService.factsText(NXP_NoticeAnalysisService.facts(n));
        System.assert(text.startsWith('[Notice] '), text.left(50));
    }

    @IsTest
    static void briefKeepsOnlyRealSourcesAndMarksAssumptions() {
        FakeAnalyzer ai = new FakeAnalyzer();
        ai.answer =
            'Here you go: {"verdict": "Lean bid", "confidence": "medium", "summary": "Pursue if leads are confirmed.",' +
            '"sections": [{"title": "Reasons to bid", "items": [{"text": "NAICS fits", "sources": ["Company Profile"]},' +
            '{"text": "Customer wants change", "sources": ["Rumour mill"]}]}, {"title": "Empty", "items": []}],' +
            '"strategies": [{"text": "Team with a CBP partner", "pairs": "Weakness + Threat", "impact": "High", "effort": "Medium", "firstStep": "Shortlist 3"}]}';
        NXP_NoticeAnalysisService.analyzerOverride = ai;
        NXP_NoticeAnalysisService.Analysis a = NXP_NoticeAnalysisService.analyze(noticeId(), 'brief');
        System.assert(a.aiUsed);
        System.assertEquals('Lean bid', a.verdict);
        System.assertEquals(1, a.sections.size(), 'Empty sections are dropped');
        System.assertEquals(new List<String>{ 'Company Profile' }, a.sections[0].items[0].sources);
        System.assert(!a.sections[0].items[0].assumption);
        System.assert(a.sections[0].items[1].assumption, 'An unknown source is not a source');
        System.assertEquals(1, a.strategies[0].rank);
        System.assert(ai.lastQuestion.contains('verdict'));
        System.assert(ai.lastFacts.contains('[Incumbent]'));

        String text = NXP_NoticeAnalysisService.toText(a, null);
        System.assert(text.contains('**Lean bid**'), text);
        System.assert(text.contains('- Customer wants change (assumption)'), text);
        System.assert(text.contains('## Facts used'), text);

        Id docId = NXP_NoticeController.saveAnalysis(noticeId(), JSON.serialize(a));
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :docId AND LinkedEntityId = :noticeId()]
        );
        System.assert(NXP_NoticeController.analysisText(noticeId(), JSON.serialize(a)).contains('Zero Trust'));
    }

    @IsTest
    static void textAnswersAndAiOffStillHelp() {
        FakeAnalyzer ai = new FakeAnalyzer();
        ai.answer = 'Vendor A is the incumbent.';
        NXP_NoticeAnalysisService.analyzerOverride = ai;
        NXP_NoticeAnalysisService.Analysis a = NXP_NoticeController.analyzeNotice(noticeId(), 'competitors');
        System.assertEquals('Vendor A is the incumbent.', a.text);
        System.assertNotEquals(null, a.note);

        ai.enabled = false;
        a = NXP_NoticeController.analyzeNotice(noticeId(), 'swot');
        System.assert(!a.aiUsed);
        System.assert(a.note.startsWith('AI is off'));
        System.assert(!a.facts.isEmpty());

        try {
            NXP_NoticeController.analyzeNotice(noticeId(), 'horoscope');
            System.assert(false, 'expected a refusal');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(6, NXP_NoticeController.getAnalysisKinds().size());
        System.assert(NXP_NoticeAnalysisService.isKind('teaming'));
    }
}
