@IsTest
private class NXP_PriceToWinTest {
    @TestSetup
    static void data() {
        NXP_Gov_Agency__c dhs = new NXP_Gov_Agency__c(
            Name = 'Homeland Security, Department of',
            Agency_Code__c = 'T-DHS',
            Full_Path__c = 'Homeland Security, Department of'
        );
        insert dhs;
        NXP_Gov_Agency__c cbp = new NXP_Gov_Agency__c(
            Name = 'U.S. Customs and Border Protection',
            Agency_Code__c = 'T-CBP',
            Full_Path__c = 'Homeland Security, Department of › U.S. Customs and Border Protection',
            Parent_Agency__c = dhs.Id
        );
        NXP_Gov_Agency__c fema = new NXP_Gov_Agency__c(
            Name = 'Federal Emergency Management Agency',
            Agency_Code__c = 'T-FEMA',
            Full_Path__c = 'Homeland Security, Department of › Federal Emergency Management Agency',
            Parent_Agency__c = dhs.Id
        );
        NXP_Gov_Agency__c va = new NXP_Gov_Agency__c(
            Name = 'Veterans Affairs, Department of',
            Agency_Code__c = 'T-VA',
            Full_Path__c = 'Veterans Affairs, Department of'
        );
        insert new List<NXP_Gov_Agency__c>{ cbp, fema, va };
        NXP_Gov_Vendor__c a = new NXP_Gov_Vendor__c(Name = 'Vendor A', UEI__c = 'PTWTESTA0001');
        NXP_Gov_Vendor__c b = new NXP_Gov_Vendor__c(Name = 'Vendor B', UEI__c = 'PTWTESTB0001');
        NXP_Gov_Vendor__c c = new NXP_Gov_Vendor__c(Name = 'Vendor C', UEI__c = 'PTWTESTC0001');
        insert new List<NXP_Gov_Vendor__c>{ a, b, c };

        Date t = Date.today();
        NXP_Award_Summary__c predecessor = award(
            'Zero trust engineering',
            'PTW-Y',
            cbp,
            a,
            '541512',
            t.addDays(-720),
            t.addDays(120),
            9000000
        );
        insert new List<NXP_Award_Summary__c>{
            predecessor,
            // CBP + 541512: per year 4.0M, 2.4M, 3.0M, 1.0M, 5.56M and the predecessor's 4.5M.
            award('Zero trust architecture', 'PTW-X', cbp, a, '541512', t.addDays(-1460), t.addDays(-730), 8000000),
            award('Network operations', 'PTW-Z', cbp, b, '541512', t.addDays(-1300), t.addDays(-400), 6000000),
            award('Network operations follow-on', 'PTW-W', cbp, c, '541512', t.addDays(-370), t.addDays(700), 3000000),
            award('Help desk', 'PTW-V', cbp, b, '541512', t.addDays(-200), t.addDays(1600), 1000000),
            award('Cloud migration', 'PTW-U', cbp, c, '541512', t.addDays(-1000), t.addDays(800), 15000000),
            // Elsewhere: FEMA (same department), VA (other department), CBP in another NAICS, and too old.
            award('FEMA cyber support', 'PTW-F', fema, b, '541512', t.addDays(-300), t.addDays(400), 2000000),
            award('VA zero trust', 'PTW-VA', va, c, '541512', t.addDays(-500), t.addDays(400), 7000000),
            award('CBP engineering', 'PTW-ENG', cbp, a, '541330', t.addDays(-400), t.addDays(400), 4000000),
            award('Old work', 'PTW-OLD', cbp, a, '541512', t.addYears(-7), t.addYears(-6), 9000000)
        };
        insert new NXP_Gov_Notice__c(
            Notice_Id__c = 'PTW-NOTICE-1',
            Title__c = 'Zero Trust Architecture Engineering Support',
            Notice_Type__c = 'Solicitation',
            Status__c = 'Active',
            Agency__c = cbp.Id,
            NAICS_Code__c = '541512',
            Predecessor_Award__c = predecessor.Id
        );
    }

    private static NXP_Award_Summary__c award(
        String name,
        String piid,
        NXP_Gov_Agency__c agency,
        NXP_Gov_Vendor__c vendor,
        String naics,
        Date startDate,
        Date endDate,
        Decimal obligated
    ) {
        return new NXP_Award_Summary__c(
            Name = name,
            PIID__c = piid,
            Agency__c = agency.Id,
            Vendor__c = vendor.Id,
            NAICS_Code__c = naics,
            Period_Start__c = startDate,
            Period_End__c = endDate,
            Obligated_Amount__c = obligated
        );
    }

    private static Id noticeId() {
        return [SELECT Id FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'PTW-NOTICE-1'].Id;
    }

    private static void pinSettings() {
        NXP_Settings.setForTest('Price_Check_Enabled', 'true');
        NXP_Settings.setForTest('Price_Check_Min_Awards', '5');
        NXP_Settings.setForTest('Price_Check_Lookback_Years', '5');
        NXP_Settings.setForTest('Price_Check_Default_Scope', 'agency');
    }

    @IsTest
    static void rangeFromAgencyAndNaics() {
        pinSettings();
        NXP_PriceToWinService.Result r = NXP_PriceToWinController.getPriceCheck(noticeId(), null);
        System.assertEquals('agency', r.scopeKey);
        System.assertEquals(6, r.count, 'CBP + 541512 within 5 years');
        System.assert(r.enough);
        System.assertEquals(1000000, r.low);
        System.assertEquals(2550000, r.q1);
        System.assertEquals(3500000, r.median);
        System.assertEquals(4375000, r.q3);
        System.assertEquals(5555556, r.high);
        System.assertEquals(6, r.values.size());
        System.assertEquals(1000000, r.values[0]);

        System.assertEquals('PTW-Y', r.predecessor.piid);
        System.assertEquals(4500000, r.predecessor.perYear, '9M over 2 years run so far');
        System.assertEquals(2, r.noticeYears, 'Predecessor runs 840 days');
        System.assertEquals('predecessor', r.noticeYearsSource);

        Map<String, NXP_PriceToWinService.Scope> scopes = new Map<String, NXP_PriceToWinService.Scope>();
        for (NXP_PriceToWinService.Scope s : r.scopes) {
            scopes.put(s.key, s);
        }
        System.assertEquals(6, scopes.get('agency').count);
        System.assertEquals(7, scopes.get('department').count, 'Adds FEMA');
        System.assertEquals(8, scopes.get('naics').count, 'Adds VA');
        System.assertEquals(7, scopes.get('agencyAll').count, 'Adds CBP 541330');
        System.assert(scopes.get('agency').selected);
        System.assertEquals('NAICS + CBP', scopes.get('agency').label);
        System.assertEquals('NAICS + DHS', scopes.get('department').label);

        Integer inRange = 0;
        for (NXP_PriceToWinService.Award a : r.awards) {
            if (a.inRange) {
                inRange++;
            }
        }
        System.assertEquals(2, inRange, '3.0M and 4.0M sit between the quartiles');
        System.assertEquals('PTW-V', r.awards[0].piid, 'Newest first');
    }

    @IsTest
    static void incumbentHoldIsEstimatedFromFollowOns() {
        pinSettings();
        NXP_PriceToWinService.Result r = NXP_PriceToWinService.analyze(noticeId(), 'agency');
        System.assertEquals(2, r.hold.matched, 'X -> Y and Z -> W');
        System.assertEquals(1, r.hold.kept, 'Vendor A kept its work; Vendor B lost to Vendor C');
        System.assertEquals('Vendor A', r.hold.incumbentName);
        System.assertEquals(1, r.hold.incumbentMatched);
        System.assertEquals(1, r.hold.incumbentKept);
        System.assertEquals('PTW-Z', r.hold.examples[0].fromPiid, 'Latest ending first');
        System.assertEquals('Vendor C', r.hold.examples[0].toVendorName);
        System.assert(!r.hold.examples[0].kept);
    }

    @IsTest
    static void widerScopesAndTooFewAwards() {
        pinSettings();
        NXP_PriceToWinService.Result r = NXP_PriceToWinService.analyze(noticeId(), 'department');
        System.assertEquals(7, r.count);
        r = NXP_PriceToWinService.analyze(noticeId(), 'naics');
        System.assertEquals(8, r.count);

        NXP_Settings.setForTest('Price_Check_Min_Awards', '10');
        r = NXP_PriceToWinService.analyze(noticeId(), 'agency');
        System.assert(!r.enough);
        System.assertEquals(null, r.median);
        System.assert(r.note.contains('needs 10'), r.note);
        System.assert(r.estimate.count >= 3, 'The similar-awards estimate still answers');
        System.assertNotEquals(null, r.estimate.perYear);
        System.assert(r.estimate.perYear >= 1000000 && r.estimate.perYear <= 7000000, r.estimate.perYear);
        System.assert(!r.estimate.basis.isEmpty());
        System.assert(r.estimate.basis[0].similarity >= 5, 'CBP + 541512 + title words rank first');

        NXP_Settings.setForTest('Price_Check_Enabled', 'false');
        r = NXP_PriceToWinService.analyze(noticeId(), null);
        System.assert(!r.enabled);
        System.assertEquals(0, r.count);
    }

    @IsTest
    static void helpers() {
        System.assertEquals(25, NXP_PriceToWinService.percentile(new List<Decimal>{ 10, 20, 30, 40, 50 }, 0.375));
        System.assertEquals(null, NXP_PriceToWinService.percentile(new List<Decimal>(), 0.5));
        Set<String> w = NXP_PriceToWinService.words('Zero Trust Architecture Engineering Support Services');
        System.assert(w.contains('architecture') && w.contains('zero') && !w.contains('support'), w);

        NXP_PriceToWinService.Award a = new NXP_PriceToWinService.Award();
        a.periodStart = Date.today().addDays(-100);
        a.periodEnd = Date.today().addDays(900);
        a.obligated = 2000000;
        NXP_PriceToWinService.perYear(a);
        System.assertEquals(1.0, a.years, 'At least one year');
        System.assertEquals(2000000, a.perYear);

        NXP_PriceToWinService.Award c = new NXP_PriceToWinService.Award();
        c.periodStart = Date.today().addYears(-1);
        c.periodEnd = Date.today().addYears(3).addDays(1);
        c.ceiling = 8000000;
        NXP_PriceToWinService.perYear(c);
        System.assertEquals(2000000, c.perYear, 'Ceiling over the full 4 years when nothing is obligated');

        NXP_PriceToWinService.Award future = new NXP_PriceToWinService.Award();
        future.periodStart = Date.today().addDays(10);
        future.obligated = 5;
        NXP_PriceToWinService.perYear(future);
        System.assertEquals(null, future.perYear);
    }

    @IsTest
    static void unknownNoticeIsAClearError() {
        pinSettings();
        NXP_Gov_Notice__c gone = new NXP_Gov_Notice__c(
            Notice_Id__c = 'PTW-GONE',
            Title__c = 'Gone',
            Status__c = 'Active'
        );
        insert gone;
        Id missing = gone.Id;
        delete gone;
        try {
            NXP_PriceToWinController.getPriceCheck(missing, null);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not found'), e.getMessage());
        }
    }
}
