@IsTest
private class NXP_PlaybookServiceTest {
    private static NXP_Playbook__mdt rule(String dev, Integer order, String types, String steps) {
        return new NXP_Playbook__mdt(
            DeveloperName = dev,
            MasterLabel = dev.replace('_', ' '),
            Active__c = true,
            Order__c = order,
            Notice_Types__c = types,
            Steps__c = steps
        );
    }

    private static NXP_Gov_Notice__c notice(String noticeType, Integer daysLeft) {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Notice_Id__c = 'PB-' + noticeType + daysLeft,
            Title__c = 'Thermal cameras',
            Notice_Type__c = noticeType,
            Status__c = 'Active',
            Source_Feed__c = 'SAM_Opportunities',
            Posted_Date__c = Date.today().addDays(-5),
            Response_Due__c = Datetime.now().addDays(daysLeft)
        );
        insert n;
        return [
            SELECT
                Id,
                Notice_Type__c,
                Source__c,
                Source_Feed__c,
                Set_Aside__c,
                Fit_Score__c,
                Contract_Vehicle__c,
                Posted_Date__c,
                Response_Due__c,
                CreatedDate
            FROM NXP_Gov_Notice__c
            WHERE Id = :n.Id
        ];
    }

    @IsTest
    static void parsesStepsAndDueRules() {
        List<NXP_PlaybookService.StepDef> d = NXP_PlaybookService.parseSteps(
            'Read the questions\nSend a capability statement | 10\n\nStart pricing | +2\n  | 4'
        );
        System.assertEquals(3, d.size(), 'Blank lines and lines without text are skipped');
        System.assertEquals(null, d[0].offset);
        System.assertEquals(10, d[1].offset);
        System.assert(!d[1].afterPosted);
        System.assertEquals(2, d[2].offset);
        System.assert(d[2].afterPosted);
    }

    @IsTest
    static void firstMatchingRuleByConditions() {
        NXP_Playbook__mdt early = rule('Early', 10, 'Sources Sought, RFI', 'Answer');
        NXP_Playbook__mdt ebuy = rule('Ebuy', 5, null, 'Price it');
        ebuy.Sources__c = 'GSA eBuy';
        ebuy.Vehicle_Held__c = 'Yes';
        NXP_Playbook__mdt aside = rule('Aside', 20, 'Solicitation', 'Check eligibility');
        aside.Set_Aside__c = 'Set-aside only';
        NXP_Playbook__mdt highFit = rule('High', 30, 'Solicitation', 'Push it');
        highFit.Min_Fit__c = 70;
        List<NXP_Playbook__mdt> rules = new List<NXP_Playbook__mdt>{ ebuy, early, aside, highFit };

        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(Notice_Type__c = 'RFI', Source__c = 'SAM.gov');
        System.assertEquals('Early', NXP_PlaybookService.match(n, false, rules).DeveloperName);

        n = new NXP_Gov_Notice__c(Notice_Type__c = 'Solicitation', Source__c = 'GSA eBuy');
        System.assertEquals('Ebuy', NXP_PlaybookService.match(n, true, rules).DeveloperName);
        System.assertEquals(null, NXP_PlaybookService.match(n, false, rules), 'eBuy rule needs a vehicle we hold');

        n = new NXP_Gov_Notice__c(Notice_Type__c = 'Solicitation', Set_Aside__c = '8(a) Set-Aside', Fit_Score__c = 80);
        System.assertEquals('Aside', NXP_PlaybookService.match(n, false, rules).DeveloperName);
        n.Set_Aside__c = 'Full and Open Competition';
        System.assertEquals('High', NXP_PlaybookService.match(n, false, rules).DeveloperName);
        n.Fit_Score__c = 40;
        System.assertEquals(null, NXP_PlaybookService.match(n, false, rules));

        System.assert(!NXP_PlaybookService.isSetAside('None'));
        System.assert(NXP_PlaybookService.isSetAside('Total Small Business'));
    }

    @IsTest
    static void planWithDueDatesTicksAndPushText() {
        NXP_PlaybookService.rulesOverride = new List<NXP_Playbook__mdt>{
            rule('Sources_Sought_RFI', 10, 'Sources Sought', 'Read the questions\nSend a statement | 10\nDecide | 30')
        };
        NXP_Gov_Notice__c n = notice('Sources Sought', 25);
        NXP_PlaybookService.Plan p = NXP_PlaybookService.planFor(n);
        System.assertEquals('Sources_Sought_RFI', p.playbook);
        System.assertEquals(3, p.steps.size());
        System.assertEquals(null, p.steps[0].due);
        System.assertEquals(n.Response_Due__c.date().addDays(-10), p.steps[1].due);
        System.assertEquals(n.Posted_Date__c, p.steps[2].due, 'Never due before the notice was posted');
        System.assert(p.steps[2].overdue, 'Its date is in the past');
        System.assert(p.overdue);
        System.assertEquals(1, p.nextStep.stepNumber);
        System.assert(p.reasons.contains('Notice type: Sources Sought'));

        p = NXP_PlaybookService.setDone(n.Id, 1, true);
        System.assertEquals(1, p.doneCount);
        System.assertEquals(UserInfo.getName(), p.steps[0].doneBy);
        System.assertEquals(2, p.nextStep.stepNumber);
        p = NXP_PlaybookService.setDone(n.Id, 1, true);
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Playbook_Step__c], 'One row per step');

        String text = NXP_PlaybookService.pushText(n);
        System.assert(text.startsWith('Nexus playbook: Sources Sought RFI'), text);
        System.assert(text.contains('[x] Read the questions'), text);
        System.assert(text.contains('[ ] Send a statement (due '), text);

        p = NXP_PlaybookService.setDone(n.Id, 1, false);
        System.assertEquals(0, p.doneCount);
        try {
            NXP_PlaybookService.setDone(n.Id, 9, true);
            System.assert(false, 'expected a refusal');
        } catch (NXP_PlaybookService.PlaybookException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void noPlanWhenNoRuleFits() {
        NXP_PlaybookService.rulesOverride = new List<NXP_Playbook__mdt>{ rule('Early', 10, 'RFI', 'Answer') };
        NXP_Gov_Notice__c n = notice('Solicitation', 10);
        System.assertEquals(null, NXP_PlaybookService.planFor(n));
        System.assertEquals(null, NXP_PlaybookService.pushText(n));
        System.assert(NXP_PlaybookService.plansFor(new List<NXP_Gov_Notice__c>()).isEmpty());
    }

    @IsTest
    static void shippedRulesAreValid() {
        List<NXP_Playbook__mdt> rules = NXP_PlaybookService.rules();
        for (NXP_Playbook__mdt r : rules) {
            System.assert(!NXP_PlaybookService.parseSteps(r.Steps__c).isEmpty(), r.DeveloperName + ' has no steps');
        }
    }
}
