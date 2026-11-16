@IsTest
private class NXP_ForecastImportTest {
    private static String rows(List<Map<String, Object>> rows) {
        return JSON.serialize(rows);
    }

    @IsTest
    static void importsMapsAgenciesAndUpdatesByKey() {
        NXP_ForecastImportController.canImportOverride = true;
        List<Map<String, Object>> data = new List<Map<String, Object>>{
            new Map<String, Object>{
                'forecastId' => 'AG-1001',
                'title' => 'Tactical Cloud Operations Support',
                'agency' => 'Dept. of the Army',
                'subAgency' => 'Army Contracting Command',
                'solicitationDate' => '2027-03-29',
                'value' => 15000000,
                'fiscalYear' => 'FY2027',
                'naics' => '541519 - Other Computer Related Services',
                'setAside' => '8(a)',
                'description' => 'Cloud operations.'
            },
            new Map<String, Object>{ 'title' => 'Help Desk Services', 'agency' => 'Dept. of the Army' },
            new Map<String, Object>{ 'title' => 'No agency here' },
            new Map<String, Object>{ 'title' => 'Bad date', 'agency' => 'GSA', 'solicitationDate' => 'Q2 FY27' }
        };
        NXP_ForecastImportController.ImportResult r = NXP_ForecastImportController.importForecasts(
            'Acquisition Gateway',
            rows(data)
        );
        System.assertEquals(4, r.read);
        System.assertEquals(2, r.created, String.valueOf(r.problems));
        System.assertEquals(2, r.rejected);
        System.assert(r.problems[0].contains('no agency'), r.problems[0]);
        System.assert(r.problems[1].contains('yyyy-mm-dd'), r.problems[1]);

        NXP_Gov_Forecast__c f = [
            SELECT
                Name,
                Agency__c,
                Agency__r.Name,
                NAICS_Code__c,
                Estimated_Solicitation_Date__c,
                Estimated_Value__c,
                Source_Feed__c
            FROM NXP_Gov_Forecast__c
            WHERE Forecast_Id__c = 'AG-1001'
        ];
        System.assertEquals('541519', f.NAICS_Code__c);
        System.assertEquals(Date.newInstance(2027, 3, 29), f.Estimated_Solicitation_Date__c);
        System.assertEquals(15000000, f.Estimated_Value__c);
        System.assertEquals('Acquisition Gateway', f.Source_Feed__c);
        System.assertNotEquals(null, f.Agency__c, 'Agency resolved from the names');
        System.assertEquals('Army Contracting Command', f.Agency__r.Name, 'The deepest level is the agency');

        NXP_Gov_Forecast__c generated = [
            SELECT Forecast_Id__c
            FROM NXP_Gov_Forecast__c
            WHERE Name = 'Help Desk Services'
        ];
        System.assert(generated.Forecast_Id__c.startsWith('ACQUISITIONGATEWAY-'), generated.Forecast_Id__c);

        // Importing the same file again updates by key; no duplicates.
        data[0].put('value', 18000000);
        r = NXP_ForecastImportController.importForecasts('Acquisition Gateway', rows(data));
        System.assertEquals(0, r.created);
        System.assertEquals(2, [SELECT COUNT() FROM NXP_Gov_Forecast__c]);
        System.assertEquals(
            18000000,
            [SELECT Estimated_Value__c FROM NXP_Gov_Forecast__c WHERE Forecast_Id__c = 'AG-1001'].Estimated_Value__c
        );
    }

    @IsTest
    static void adminsOnlyAndBatchLimit() {
        NXP_ForecastImportController.canImportOverride = false;
        try {
            NXP_ForecastImportController.importForecasts('X', '[]');
            System.assert(false, 'expected a refusal');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('admins'), e.getMessage());
        }
        NXP_ForecastImportController.canImportOverride = true;
        List<Map<String, Object>> many = new List<Map<String, Object>>();
        for (Integer i = 0; i < 501; i++) {
            many.add(new Map<String, Object>{ 'title' => 'T' + i, 'agency' => 'GSA' });
        }
        try {
            NXP_ForecastImportController.importForecasts('X', rows(many));
            System.assert(false, 'expected the batch limit');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('500'), e.getMessage());
        }
        System.assertEquals(
            NXP_ForecastImportController.generatedKey('S', 'Army', 'Help desk'),
            NXP_ForecastImportController.generatedKey('S', 'ARMY', 'Help  Desk'),
            'Same source, agency and title give the same key'
        );
    }
}
