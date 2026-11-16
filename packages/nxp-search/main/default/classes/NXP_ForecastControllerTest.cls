@IsTest
private class NXP_ForecastControllerTest {
    @TestSetup
    static void data() {
        NXP_Gov_Agency__c army = new NXP_Gov_Agency__c(
            Name = 'Dept of the Army',
            Agency_Code__c = 'FC-ARMY',
            Full_Path__c = 'Dept of the Army'
        );
        insert army;
        NXP_Gov_Vendor__c r = new NXP_Gov_Vendor__c(Name = 'Vendor R', UEI__c = 'FCTESTR00001');
        NXP_Gov_Vendor__c s = new NXP_Gov_Vendor__c(Name = 'Vendor S', UEI__c = 'FCTESTS00001');
        insert new List<NXP_Gov_Vendor__c>{ r, s };
        Date solicitation = Date.today().addDays(134);
        insert new List<NXP_Award_Summary__c>{
            new NXP_Award_Summary__c(
                Name = 'Tactical cloud operations',
                PIID__c = 'FC-PIID-1',
                Agency__c = army.Id,
                Vendor__c = r.Id,
                NAICS_Code__c = '541519',
                Obligated_Amount__c = 9000000,
                Period_Start__c = Date.today().addYears(-3),
                Period_End__c = solicitation.addDays(20)
            ),
            new NXP_Award_Summary__c(
                Name = 'Help desk',
                PIID__c = 'FC-PIID-2',
                Agency__c = army.Id,
                Vendor__c = s.Id,
                NAICS_Code__c = '541519',
                Obligated_Amount__c = 2000000,
                Period_Start__c = Date.today().addYears(-2),
                Period_End__c = solicitation.addMonths(10)
            ),
            new NXP_Award_Summary__c(
                Name = 'Tactical cloud, other NAICS',
                PIID__c = 'FC-PIID-3',
                Agency__c = army.Id,
                Vendor__c = s.Id,
                NAICS_Code__c = '541330',
                Obligated_Amount__c = 1000000,
                Period_Start__c = Date.today().addYears(-1),
                Period_End__c = solicitation
            )
        };
        insert new List<NXP_Gov_Forecast__c>{
            new NXP_Gov_Forecast__c(
                Name = 'Tactical Cloud Operations Support',
                Forecast_Id__c = 'FC-1',
                Agency__c = army.Id,
                NAICS_Code__c = '541519',
                Set_Aside__c = '8(a) Set-Aside (FAR 19.8)',
                Estimated_Value__c = 15000000,
                Estimated_Solicitation_Date__c = solicitation,
                Fiscal_Year__c = 'FY2027'
            ),
            new NXP_Gov_Forecast__c(
                Name = 'Enterprise Cloud Migration',
                Forecast_Id__c = 'FC-2',
                Agency__c = army.Id,
                NAICS_Code__c = '541519',
                Estimated_Solicitation_Date__c = solicitation.addMonths(3)
            )
        };
        insert new NXP_Gov_Notice__c(
            Notice_Id__c = 'FC-NOTICE-1',
            Title__c = 'Tactical Cloud Operations Support (Sources Sought)',
            Notice_Type__c = 'Sources Sought',
            Status__c = 'Active',
            Agency__c = army.Id,
            NAICS_Code__c = '541519',
            Posted_Date__c = Date.today().addDays(-3)
        );
    }

    private static Id forecastId() {
        return [SELECT Id FROM NXP_Gov_Forecast__c WHERE Forecast_Id__c = 'FC-1'].Id;
    }

    private static void rules() {
        NXP_FitScoreService.profileOverride = new NXP_Company_Profile__c(
            Name = 'Test',
            Active__c = true,
            NAICS_Codes__c = '541519',
            Set_Asides__c = 'Small Business'
        );
        NXP_FitScoreService.rulesOverride = new List<NXP_Fit_Rule__mdt>{
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'NAICS', Weight__c = 30, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'Set-Aside', Weight__c = 15, Active__c = true),
            new NXP_Fit_Rule__mdt(Rule_Type__c = 'Vehicle', Weight__c = 10, Active__c = true)
        };
    }

    @IsTest
    static void overviewShowsFitStagesCandidatesLeadersAndRelated() {
        rules();
        NXP_ForecastController.Overview o = NXP_ForecastController.getOverview(forecastId());
        System.assertEquals(134, o.daysToSolicitation);
        System.assertEquals(2, o.fit.size(), 'The vehicle rule is left out for forecasts');
        System.assertEquals(67, o.fitScore, '30 of 45 points');
        System.assertEquals(false, o.setAsideOk, 'We are not 8(a)');
        System.assert(o.setAsideNote.contains('team'), o.setAsideNote);

        System.assertEquals(4, o.stages.size());
        System.assertEquals('done', o.stages[0].state);
        System.assertEquals('now', o.stages[1].state, 'No Sources Sought linked yet');
        System.assertEquals('next', o.stages[2].state);

        System.assertEquals(2, o.candidates.size(), 'Same NAICS only');
        System.assertEquals('FC-PIID-1', o.candidates[0].piid, 'Title and timing match best');
        System.assertEquals('High', o.candidates[0].match);

        System.assertEquals(2, o.leaders.size());
        System.assertEquals(1, o.related.size());
        System.assertEquals('Enterprise Cloud Migration', o.related[0].Name);
        System.assert(!o.watching);
        System.assertEquals(0, o.watchers);
    }

    @IsTest
    static void confirmedPredecessorCarriesToALinkedNotice() {
        rules();
        NXP_ForecastController.canCurateOverride = true;
        Id awardId = [SELECT Id FROM NXP_Award_Summary__c WHERE PIID__c = 'FC-PIID-2'].Id;
        NXP_ForecastController.Overview o = NXP_ForecastController.setPredecessor(forecastId(), awardId);
        System.assertEquals('FC-PIID-2', o.candidates[0].piid, 'The confirmed one comes first');
        System.assert(o.candidates[0].confirmed);

        Id noticeId = [SELECT Id FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'FC-NOTICE-1'].Id;
        o = NXP_ForecastController.linkNotice(forecastId(), noticeId);
        NXP_Gov_Notice__c n = [SELECT Forecast__c, Predecessor_Award__c FROM NXP_Gov_Notice__c WHERE Id = :noticeId];
        System.assertEquals(forecastId(), n.Forecast__c);
        System.assertEquals(awardId, n.Predecessor_Award__c);
        System.assertEquals('done', o.stages[1].state, 'The Sources Sought is now linked');
        System.assertEquals('Sources Sought', o.stages[1].label);
        System.assertEquals('now', o.stages[2].state);

        NXP_PriceToWinService.Result p = NXP_PriceToWinController.getForecastPriceCheck(forecastId(), null);
        System.assertEquals(null, p.noticeId);
        System.assertEquals(2, p.count, 'Army + 541519 awards');
    }

    @IsTest
    static void bdUsersCannotChangeLinks() {
        NXP_ForecastController.canCurateOverride = false;
        try {
            NXP_ForecastController.setPredecessor(forecastId(), null);
            System.assert(false, 'expected a refusal');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Power Users'), e.getMessage());
        }
        System.assert(!NXP_ForecastController.getOverview(forecastId()).canCurate);
    }

    @IsTest
    static void errorsAreReadable() {
        NXP_Gov_Forecast__c gone = new NXP_Gov_Forecast__c(Name = 'Gone', Forecast_Id__c = 'FC-GONE');
        insert gone;
        Id missing = gone.Id;
        delete gone;
        try {
            NXP_ForecastController.getOverview(missing);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not found'), e.getMessage());
        }
        System.assert(NXP_ForecastController.words('Tactical Cloud Support').contains('tactical'));
        System.assert(!NXP_ForecastController.words('Tactical Cloud Support').contains('support'));
    }
}
