@IsTest
private class NXP_PursuitTest {
    private static Map<String, String> f(String dept, String type) {
        return new Map<String, String>{
            'dept' => dept,
            'agency' => '(Department level)',
            'naics' => '5415*',
            'type' => type,
            'setaside' => 'None',
            'source' => 'SAM.gov',
            'vehicle' => 'No vehicle',
            'value' => 'Not published',
            'fit' => '60-74'
        };
    }

    @IsTest
    static void featuresFromANotice() {
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Agency_Path__c = 'Homeland Security › U.S. Customs and Border Protection',
            NAICS_Code__c = '541512',
            Notice_Type__c = 'Solicitation',
            Set_Aside__c = 'Full and Open Competition',
            Source__c = 'SAM.gov',
            Estimated_Value__c = 14000000,
            Fit_Score__c = 78
        );
        Map<String, String> x = NXP_PursuitModel.features(n, true);
        System.assertEquals('Homeland Security', x.get('dept'));
        System.assertEquals('U.S. Customs and Border Protection', x.get('agency'));
        System.assertEquals('5415*', x.get('naics'));
        System.assertEquals('None', x.get('setaside'));
        System.assertEquals('Vehicle we hold', x.get('vehicle'));
        System.assertEquals('$10M-$50M', x.get('value'));
        System.assertEquals('75-100', x.get('fit'));
        System.assertEquals('No vehicle', NXP_PursuitModel.features(new NXP_Gov_Notice__c(), null).get('vehicle'));
    }

    @IsTest
    static void learnsAndExplains() {
        NXP_PursuitModel m = new NXP_PursuitModel();
        for (Integer i = 0; i < 20; i++) {
            m.learn(f('Homeland Security', 'Solicitation'), true);
            m.learn(f('Defense', 'Solicitation'), false);
        }
        m.learn(f('Defense', 'Solicitation'), true);
        NXP_PursuitModel.Score high = m.score(f('Homeland Security', 'Solicitation'));
        NXP_PursuitModel.Score low = m.score(f('Defense', 'Solicitation'));
        System.assert(high.likelihood > 80, high.likelihood);
        System.assert(low.likelihood < 20, low.likelihood);
        System.assertEquals('Department', high.factors[0].label);
        System.assertEquals('up', high.factors[0].direction);
        System.assertEquals(20, high.factors[0].pursued);
        System.assertEquals('down', low.factors[0].direction);
        System.assertEquals(21, low.factors[0].decided);

        // An unseen value counts as no evidence either way.
        NXP_PursuitModel.Score unseen = m.score(f('Energy', 'Solicitation'));
        System.assert(unseen.likelihood > low.likelihood && unseen.likelihood < high.likelihood);

        NXP_PursuitModel copy = NXP_PursuitModel.fromJson(m.toJson());
        System.assertEquals(high.likelihood, copy.score(f('Homeland Security', 'Solicitation')).likelihood);

        System.assert(NXP_PursuitModel.auc(new List<Double>{ 0.9, 0.8 }, new List<Double>{ 0.1 }) == 1);
        System.assert(NXP_PursuitModel.auc(new List<Double>{ 0.5 }, new List<Double>{ 0.5 }) == 0.5);
        System.assertEquals(null, NXP_PursuitModel.auc(new List<Double>(), new List<Double>{ 0.5 }));
    }

    @IsTest
    static void collectsUntilThereAreEnoughDecisions() {
        NXP_PursuitTrainBatch b = new NXP_PursuitTrainBatch();
        for (Integer i = 0; i < 30; i++) {
            b.add(f('Homeland Security', 'Solicitation'), true, Datetime.now().addDays(-i));
        }
        NXP_Pursuit_Model__c row = b.train();
        System.assertEquals('Collecting', row.Status__c);
        System.assert(row.Detail__c.startsWith('Not enough decisions yet: 30 of 200'), row.Detail__c);
    }

    @IsTest
    static void trainsWithAHoldOutCheck() {
        NXP_PursuitTrainBatch b = new NXP_PursuitTrainBatch();
        for (Integer i = 0; i < 120; i++) {
            b.add(f('Homeland Security', 'Solicitation'), true, Datetime.now().addDays(-i));
            b.add(f('Defense', 'Award Notice'), false, Datetime.now().addDays(-i));
        }
        NXP_Pursuit_Model__c row = b.train();
        System.assertEquals('Active', row.Status__c);
        System.assertEquals(240, row.Decisions__c);
        System.assert(row.AUC__c == 1, 'Perfectly separable history ranks perfectly: ' + row.AUC__c);
        System.assert(row.Detail__c.contains('ranked a pushed notice above a dismissed one 100%'), row.Detail__c);
        System.assertNotEquals(null, NXP_PursuitModel.fromJson(row.Model_Json__c));
    }

    @IsTest
    static void batchesLearnFromPushesAndDismissalsAndScoreOpenNotices() {
        NXP_Saved_Search__c s = new NXP_Saved_Search__c(
            Name = 'Pursuit test',
            Criteria_JSON__c = '{"keywords":"zero trust"}',
            Alert_Frequency__c = 'None',
            Active__c = true
        );
        insert s;
        List<NXP_Gov_Notice__c> notices = new List<NXP_Gov_Notice__c>();
        for (Integer i = 0; i < 6; i++) {
            notices.add(
                new NXP_Gov_Notice__c(
                    Notice_Id__c = 'PURSUIT-' + i,
                    Title__c = 'Notice ' + i,
                    Status__c = 'Active',
                    Notice_Type__c = i < 3 ? 'Solicitation' : 'Award Notice',
                    Agency_Path__c = i < 3 ? 'Homeland Security' : 'Defense',
                    Pushed__c = i < 2
                )
            );
        }
        insert notices;
        List<NXP_Search_Match__c> matches = new List<NXP_Search_Match__c>();
        for (Integer i = 3; i < 6; i++) {
            matches.add(
                new NXP_Search_Match__c(
                    Saved_Search__c = s.Id,
                    Gov_Notice__c = notices[i].Id,
                    Match_Key__c = 'pk' + i,
                    Alert_Status__c = 'Sent',
                    User_Action__c = 'Dismissed',
                    Matched_At__c = Datetime.now()
                )
            );
        }
        insert matches;
        NXP_Settings.setForTest('Pursuit_Min_Decisions', '1');

        Test.startTest();
        Database.executeBatch(new NXP_PursuitTrainBatch(), 2000);
        Test.stopTest();
        NXP_Pursuit_Model__c row = [SELECT Status__c, Decisions__c, Pursued__c, Detail__c FROM NXP_Pursuit_Model__c];
        System.assertEquals(5, row.Decisions__c, 'Two pushed and three dismissed; the undecided notice is left out');
        System.assertEquals(2, row.Pursued__c);
        System.assertEquals('Collecting', row.Status__c, 'Fewer than 20 on each side');

        // With an active model, scoring writes the likelihood and its factors.
        NXP_PursuitModel m = new NXP_PursuitModel();
        for (Integer i = 0; i < 25; i++) {
            m.learn(NXP_PursuitModel.features(notices[0], null), true);
            m.learn(NXP_PursuitModel.features(notices[3], null), false);
        }
        insert new NXP_Pursuit_Model__c(Status__c = 'Active', Trained__c = Datetime.now(), Model_Json__c = m.toJson());
        new NXP_PursuitScoreBatch(true)
            .execute(
                null,
                [
                    SELECT
                        Id,
                        Agency_Path__c,
                        NAICS_Code__c,
                        Notice_Type__c,
                        Set_Aside__c,
                        Source__c,
                        Contract_Vehicle__c,
                        Estimated_Value__c,
                        Fit_Score__c,
                        Pushed__c,
                        Posted_Date__c,
                        CreatedDate
                    FROM NXP_Gov_Notice__c
                ]
            );
        NXP_Gov_Notice__c scored = [
            SELECT Pursuit_Likelihood__c, Pursuit_Factors__c, Pursuit_Scored__c
            FROM NXP_Gov_Notice__c
            WHERE Id = :notices[2].Id
        ];
        System.assert(scored.Pursuit_Likelihood__c > 50, scored.Pursuit_Likelihood__c);
        System.assert(scored.Pursuit_Factors__c.contains('Homeland Security'), scored.Pursuit_Factors__c);
        System.assertNotEquals(null, scored.Pursuit_Scored__c);
    }

    @IsTest
    static void hourlyJobOnlyWhenOn() {
        System.assertEquals(null, NXP_PursuitJob.run(2), 'Off by default');
        NXP_Settings.setForTest('Pursuit_Prediction_Enabled', 'true');
        Test.startTest();
        System.assertNotEquals(null, NXP_PursuitJob.run(2), 'Trains at 02:00');
        System.assertEquals(null, NXP_PursuitJob.run(9), 'No model yet: nothing to score');
        Test.stopTest();
        NXP_PursuitJob.scheduleDefaults();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :NXP_PursuitJob.JOB_NAME]);
    }
}
