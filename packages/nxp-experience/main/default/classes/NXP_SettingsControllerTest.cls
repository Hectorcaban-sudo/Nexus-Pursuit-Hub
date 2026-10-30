@IsTest
private class NXP_SettingsControllerTest {
    private static void makeAdmin() {
        PermissionSet admin = [SELECT Id FROM PermissionSet WHERE Name = 'NXP_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            if (
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :admin.Id
                ] == 0
            ) {
                insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = admin.Id);
            }
        }
    }

    private static NXP_SettingsController.Item find(NXP_SettingsController.Model m, String id) {
        for (NXP_SettingsController.Section s : m.sections) {
            for (NXP_SettingsController.Item i : s.items) {
                if (i.id == id) {
                    return i;
                }
            }
        }
        return null;
    }

    private static NXP_SettingsController.Change change(String id, String value) {
        NXP_SettingsController.Change c = new NXP_SettingsController.Change();
        c.id = id;
        c.value = value;
        return c;
    }

    @IsTest
    static void listsSettingsFeedsAndFitRules() {
        makeAdmin();
        NXP_SettingsController.Model m = NXP_SettingsController.getSettings();
        System.assert(m.sections.size() >= 8);
        NXP_SettingsController.Item ai = find(m, 'NXP_Setting.AI_Max_Calls_Per_Day');
        System.assertEquals('Integer', ai.type);
        System.assertEquals('500', ai.defaultValue);
        NXP_SettingsController.Item mode = find(m, 'NXP_Setting.Admin_Digest_Mode');
        System.assertEquals(3, mode.options.size());
        System.assert(find(m, 'NXP_Setting.AI_Enabled').releaseManaged);
        NXP_SettingsController.Item feed = find(m, 'NXP_Feed_Config.SAM_Opportunities.Active__c');
        System.assertNotEquals(null, feed);
        System.assertEquals('Boolean', feed.type);
        System.assert(feed.releaseManaged, 'Feed switches come from env-config');
        System.assertNotEquals(null, find(m, 'NXP_Fit_Rule.NAICS.Weight__c'));
    }

    @IsTest
    static void savesRecordsTheChangeAndBuildsFullRecords() {
        makeAdmin();
        String jobId = NXP_SettingsController.saveSettings(
            new List<NXP_SettingsController.Change>{
                change('NXP_Setting.Admin_Digest_Mode', 'Daily'),
                change('NXP_Feed_Config.SAM_Opportunities.Interval_Minutes__c', '120')
            }
        );
        System.assertEquals('test', jobId);
        List<NXP_Setting_Change__c> rows = [
            SELECT Setting__c, Label__c, New_Value__c, Status__c
            FROM NXP_Setting_Change__c
            ORDER BY Setting__c
        ];
        System.assertEquals(2, rows.size());
        System.assertEquals('Pending', rows[0].Status__c);
        System.assertEquals('Daily', rows[1].New_Value__c);
        System.assert(rows[0].Label__c.startsWith('SAM.gov'), rows[0].Label__c);
        System.assertEquals('Pending', NXP_SettingsController.getSaveStatus('test').get('status'));

        NXP_SettingsDeployCallback.mark('test', true, null);
        System.assertEquals('Saved', NXP_SettingsController.getSaveStatus('test').get('status'));
        System.assertEquals(2, NXP_SettingsController.getSettings().history.size());

        // A deployed record replaces the old one, so every field is sent.
        Metadata.CustomMetadata md = NXP_SettingsController.toMetadata(
            'NXP_Feed_Config.SAM_Opportunities',
            new Map<String, String>{ 'Active__c' => 'true' }
        );
        Map<String, Object> values = new Map<String, Object>();
        for (Metadata.CustomMetadataValue v : md.values) {
            values.put(v.field, v.value);
        }
        System.assertEquals(true, values.get('Active__c'));
        System.assert(values.containsKey('Connector_Class__c'), 'Unchanged fields are kept');
        System.assert(values.containsKey('Endpoint_Path__c'));
    }

    @IsTest
    static void rejectsBadValuesAndFitWeightsThatDontAddUp() {
        makeAdmin();
        List<List<NXP_SettingsController.Change>> bad = new List<List<NXP_SettingsController.Change>>{
            new List<NXP_SettingsController.Change>{ change('NXP_Setting.AI_Max_Calls_Per_Day', '-5') },
            new List<NXP_SettingsController.Change>{ change('NXP_Setting.AI_Enabled', 'maybe') },
            new List<NXP_SettingsController.Change>{ change('NXP_Setting.Admin_Digest_Mode', 'Hourly') },
            new List<NXP_SettingsController.Change>{ change('NXP_Setting.Nope', '1') },
            new List<NXP_SettingsController.Change>{ change('NXP_Fit_Rule.NAICS.Weight__c', '35') }
        };
        for (List<NXP_SettingsController.Change> changes : bad) {
            try {
                NXP_SettingsController.saveSettings(changes);
                System.assert(false, 'expected a refusal for ' + changes[0].id);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM NXP_Setting_Change__c]);
    }

    @IsTest
    static void healthChecksAndJobs() {
        makeAdmin();
        List<NXP_SettingsController.Check> checks = NXP_SettingsController.getHealth();
        Set<String> keys = new Set<String>();
        for (NXP_SettingsController.Check c : checks) {
            keys.add(c.key);
            System.assert(new Set<String>{ 'ok', 'warn', 'fail' }.contains(c.status), c.key + ' ' + c.status);
        }
        System.assert(
            keys.containsAll(new Set<String>{ 'mail', 'bell', 'sam', 'jobs', 'saved', 'files', 'profile', 'ai' })
        );

        Test.startTest();
        Integer jobs = NXP_SettingsController.rescheduleJobs();
        Id batchId = NXP_SettingsController.rescoreNotices();
        Test.stopTest();
        System.assertEquals(NXP_SettingsController.EXPECTED_JOBS.size(), jobs);
        System.assertNotEquals(null, batchId);
    }

    @IsTest
    static void reappliesSettingsAReleasePutBack() {
        makeAdmin();
        System.assertEquals(null, NXP_SettingsController.reapplySettings(), 'Nothing saved yet');
        String current = NXP_Setting__mdt.getInstance('Inbox_Days') == null
            ? '30'
            : NXP_Setting__mdt.getInstance('Inbox_Days').Value__c;
        // Saved here earlier; a release has since put the shipped value back.
        insert new List<NXP_Setting_Change__c>{
            new NXP_Setting_Change__c(
                Setting__c = 'NXP_Setting.Inbox_Days',
                New_Value__c = current == '45' ? '46' : '45',
                Status__c = 'Saved'
            ),
            new NXP_Setting_Change__c(
                Setting__c = 'NXP_Setting.AI_Enabled',
                New_Value__c = 'maybe',
                Status__c = 'Saved'
            )
        };
        List<NXP_SettingsController.Change> drift = NXP_SettingsController.releaseDrift();
        System.assertEquals(1, drift.size(), 'env-config settings are left alone');
        System.assertEquals('NXP_Setting.Inbox_Days', drift[0].id);
        System.assertEquals('test', NXP_SettingsController.reapplySettings());
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Setting_Change__c WHERE Status__c = 'Pending']);
    }

    @IsTest
    static void nonAdminsAreRefused() {
        User u = new User(
            Alias = 'nxpset',
            Email = 'nxp.settings@example.gov',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Settings',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
            .Id,
            TimeZoneSidKey = 'America/New_York',
            Username = 'nxp.settings.' + System.currentTimeMillis() + '@example.gov'
        );
        System.runAs(u) {
            try {
                NXP_SettingsController.getSettings();
                System.assert(false, 'expected a refusal');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }
}
