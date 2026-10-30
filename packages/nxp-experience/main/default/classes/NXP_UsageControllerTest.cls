@IsTest
private class NXP_UsageControllerTest {
    @IsTest
    static void logsAKnownScreen() {
        NXP_UsageController.logView('Vehicle Portfolio');
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Usage__c]);
    }
}
