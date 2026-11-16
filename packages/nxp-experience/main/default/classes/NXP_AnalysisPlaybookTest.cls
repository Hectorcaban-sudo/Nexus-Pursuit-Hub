@IsTest
private class NXP_AnalysisPlaybookTest {
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
            Agency_Code__c = 'PB-CBP'
        );
        insert agency;
        NXP_Gov_Vendor__c a = new NXP_Gov_Vendor__c(Name = 'Vendor A', UEI__c = 'PBTESTA00001');
        NXP_Gov_Vendor__c b = new NXP_Gov_Vendor__c(Name = 'Vendor B', UEI__c = 'PBTESTB00001');
        insert new List<NXP_Gov_Vendor__c>{ a, b };
        NXP_Award_Summary__c predecessor = new NXP_Award_Summary__c(
            Name = 'ZTA support',
            PIID__c = 'PB-PIID-1',
            Agency__c = agency.Id,
            Vendor__c = a.Id,
            NAICS_Code__c = '541512',
            Obligated_Amount__c = 9000000,
            Period_Start__c = Date.today().addYears(-2),
            Period_End__c = Date.today().addMonths(4)
        );
        insert new List<NXP_Award_Summary__c>{
            predecessor,
            new NXP_Award_Summary__c(
                Name = 'Other',
                PIID__c = 'PB-PIID-2',
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
        insert new NXP_Gov_Notice__c(
            Notice_Id__c = 'PB-1',
            Title__c = 'Zero Trust Architecture Engineering Support',
            Notice_Type__c = 'Solicitation',
            Status__c = 'Active',
            Agency__c = agency.Id,
            Agency_Path__c = agency.Full_Path__c,
            NAICS_Code__c = '541512',
            Response_Due__c = Datetime.now().addDays(21),
            Predecessor_Award__c = predecessor.Id,
            Incumbent__c = a.Id
        );
    }

    private static Id noticeId() {
        return [SELECT Id FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'PB-1'].Id;
    }

    private static NXP_AnalysisPlaybookService.Definition competitors() {
        NXP_AnalysisPlaybookService.Definition d = new NXP_AnalysisPlaybookService.Definition();
        d.name = 'Executive competitive brief';
        d.category = 'Capture';
        d.description = 'Competitors and how we beat them.';
        NXP_AnalysisPlaybookService.Step s1 = new NXP_AnalysisPlaybookService.Step();
        s1.title = 'Pick the competitors';
        s1.text = 'List the incumbent and the vendors with the most awards here.';
        NXP_AnalysisPlaybookService.Step s2 = new NXP_AnalysisPlaybookService.Step();
        s2.title = 'How we beat them';
        s2.text = 'For each, one way we win and one risk.';
        d.steps = new List<NXP_AnalysisPlaybookService.Step>{ s1, s2 };
        d.sections = new List<String>{ 'Competitors', 'How we win' };
        d.sources = new List<String>{ 'Notice', 'Incumbent', 'Award history' };
        d.askVerdict = true;
        return d;
    }

    @IsTest
    static void editorsSaveDraftThenPublishVersions() {
        NXP_AnalysisPlaybookService.canEditOverride = true;
        NXP_AnalysisPlaybookService.Definition d = NXP_AnalysisPlaybookService.save(competitors(), false, null);
        System.assertEquals('Draft', d.status);
        System.assertEquals(0, d.version);
        System.assert(d.key.startsWith('executive-competitive-brief-'), d.key);
        System.assertEquals(2, d.steps.size());
        System.assertEquals('How we win', d.sections[1]);
        System.assert(NXP_AnalysisPlaybookService.publishedKinds().isEmpty(), 'Drafts are not offered on notices');

        d.description = 'Edited.';
        d = (NXP_AnalysisPlaybookService.Definition) NXP_AnalysisPlaybookController.savePlaybook(
            JSON.serialize(d),
            true,
            'Ready for gate reviews'
        );
        System.assertEquals('Published', d.status);
        System.assertEquals(1, d.version);
        System.assertEquals('Ready for gate reviews', d.changeNote);
        System.assertNotEquals(null, d.publishedOn);

        d = NXP_AnalysisPlaybookService.save(d, true, null);
        System.assertEquals(2, d.version);
        try {
            NXP_AnalysisPlaybookService.save(d, false, null);
            System.assert(false, 'A published playbook changes only by publishing');
        } catch (NXP_AnalysisPlaybookService.PlaybookException e) {
            System.assert(e.getMessage().contains('unpublish'), e.getMessage());
        }

        List<NXP_NoticeAnalysisService.Kind> kinds = NXP_NoticeController.getAnalysisKinds();
        System.assertEquals(7, kinds.size(), 'Six Nexus analyses and the published playbook');
        System.assert(kinds[6].org);
        System.assertEquals('pb:' + d.key, kinds[6].key);
        System.assertEquals('Capture', kinds[0].category, 'Nexus analyses carry their card details');

        NXP_AnalysisPlaybookController.Library lib = NXP_AnalysisPlaybookController.getLibrary();
        System.assert(lib.canEdit);
        System.assertEquals(1, lib.playbooks.size());
        System.assertEquals(6, lib.defaults.size());
        System.assertEquals(12, lib.maxSteps);
        System.assertNotEquals(null, NXP_AnalysisPlaybookController.getVersions(d.id));

        NXP_AnalysisPlaybookController.setStatus(d.id, 'Retired');
        System.assert(NXP_AnalysisPlaybookService.publishedKinds().isEmpty());
    }

    @IsTest
    static void runningAPlaybookUsesOnlyItsFactsAndCountsUse() {
        NXP_AnalysisPlaybookService.canEditOverride = true;
        NXP_AnalysisPlaybookService.Definition d = NXP_AnalysisPlaybookService.save(competitors(), true, null);
        FakeAnalyzer ai = new FakeAnalyzer();
        ai.answer =
            '{"verdict": "Lean bid", "confidence": "medium", "summary": "Two competitors.", "sections": [' +
            '{"title": "Competitors", "items": [{"text": "Vendor A holds the predecessor", "sources": ["Incumbent"]},' +
            '{"text": "We match the NAICS", "sources": ["Company Profile"]}]}]}';
        NXP_NoticeAnalysisService.analyzerOverride = ai;

        NXP_AnalysisPlaybookService.canEditOverride = false;
        NXP_NoticeAnalysisService.Analysis a = NXP_NoticeController.analyzeNotice(noticeId(), 'pb:' + d.key);
        System.assert(a.aiUsed);
        System.assertEquals('Lean bid', a.verdict);
        System.assert(a.label.contains('(v1)'), a.label);
        System.assert(!a.sections[0].items[0].assumption);
        System.assert(a.sections[0].items[1].assumption, 'Company Profile was not one of its facts');
        System.assert(ai.lastFacts.contains('[Incumbent]'), ai.lastFacts);
        System.assert(ai.lastFacts.contains('[Award history]'), ai.lastFacts);
        System.assert(!ai.lastFacts.contains('[Company Profile]'), 'Only the chosen sources are sent');
        System.assert(ai.lastQuestion.contains('1. Pick the competitors: List the incumbent'), ai.lastQuestion);
        System.assert(ai.lastQuestion.contains('Return these sections, in this order: "Competitors", "How we win"'));
        System.assert(ai.lastQuestion.contains('"verdict" to exactly one of'));
        System.assert(ai.lastQuestion.contains('No strategies.'));
        System.assertEquals(1, [SELECT Times_Used__c FROM NXP_Analysis_Playbook__c].Times_Used__c);

        Id docId = NXP_NoticeController.saveAnalysis(noticeId(), JSON.serialize(a));
        System.assert(
            [SELECT PathOnClient FROM ContentVersion WHERE ContentDocumentId = :docId]
                .PathOnClient.startsWith('nexus-pb-'),
            'File name has no colon'
        );

        // Not published (retired): not runnable by a BD user.
        NXP_AnalysisPlaybookService.canEditOverride = true;
        NXP_AnalysisPlaybookService.setStatus(d.id, 'Retired');
        NXP_AnalysisPlaybookService.canEditOverride = false;
        try {
            NXP_NoticeController.analyzeNotice(noticeId(), 'pb:' + d.key);
            System.assert(false, 'expected not available');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testRunWithPriceAndVendorFactsWhenAiIsOff() {
        NXP_AnalysisPlaybookService.canEditOverride = true;
        FakeAnalyzer ai = new FakeAnalyzer();
        ai.enabled = false;
        NXP_NoticeAnalysisService.analyzerOverride = ai;
        NXP_AnalysisPlaybookService.Definition d = competitors();
        d.sources = new List<String>{ 'Price-to-Win', 'Vendor profiles' };
        NXP_NoticeAnalysisService.Analysis a = NXP_AnalysisPlaybookController.testPlaybook(
            noticeId(),
            JSON.serialize(d)
        );
        System.assert(!a.aiUsed);
        System.assert(a.note.contains('Test run'), a.note);
        Set<String> sources = new Set<String>();
        for (NXP_NoticeAnalysisService.Fact f : a.facts) {
            sources.add(f.source);
        }
        System.assert(sources.contains('Price-to-Win'), sources);
        System.assert(sources.contains('Vendor profile: Vendor A'), sources);
        System.assert(sources.contains('Vendor profile: Vendor B'), sources);
        System.assert(!sources.contains('Notice'), 'Notice was not chosen');
        System.assertEquals(0, [SELECT COUNT() FROM NXP_Analysis_Playbook__c], 'A test run saves nothing');
    }

    @IsTest
    static void copiesAndRules() {
        NXP_AnalysisPlaybookService.canEditOverride = true;
        NXP_AnalysisPlaybookService.Definition brief = NXP_AnalysisPlaybookController.copyPlaybook('brief');
        System.assertEquals('Draft', brief.status);
        System.assert(brief.name.startsWith('Bid / no-bid brief'), brief.name);
        System.assert(brief.askVerdict && brief.askStrategies);
        System.assert(brief.steps[0].text.contains('Recommend whether to bid'));
        NXP_AnalysisPlaybookService.Definition again = NXP_AnalysisPlaybookController.copyPlaybook(brief.id);
        System.assert(again.name.endsWith('(copy)'), again.name);
        System.assertNotEquals(brief.key, again.key);

        NXP_AnalysisPlaybookService.Definition bad = competitors();
        bad.name = ' ';
        assertRefused(bad, 'name');
        bad = competitors();
        bad.steps = new List<NXP_AnalysisPlaybookService.Step>();
        assertRefused(bad, 'at least one step');
        bad = competitors();
        bad.sources = new List<String>{ 'Horoscope' };
        assertRefused(bad, 'Unknown fact source');
        bad = competitors();
        for (Integer i = 0; i < 12; i++) {
            bad.steps.add(bad.steps[0]);
        }
        assertRefused(bad, 'at most 12');

        NXP_AnalysisPlaybookService.canEditOverride = false;
        assertRefused(competitors(), 'Power Users');
        System.assertEquals(0, NXP_AnalysisPlaybookService.library().size(), 'BD users see published only');
        System.assertEquals('Documents', NXP_AnalysisPlaybookService.groupOf('Document: SOW.pdf'));
        System.assertEquals('Notice', NXP_AnalysisPlaybookService.groupOf('Notice description'));
    }

    private static void assertRefused(NXP_AnalysisPlaybookService.Definition d, String expected) {
        try {
            NXP_AnalysisPlaybookService.save(d, false, null);
            System.assert(false, 'expected a refusal containing: ' + expected);
        } catch (NXP_AnalysisPlaybookService.PlaybookException e) {
            System.assert(e.getMessage().contains(expected), e.getMessage());
        }
    }
}
