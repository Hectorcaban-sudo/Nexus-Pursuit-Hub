@IsTest
private class NXP_UsageServiceTest {
    @IsTest
    static void oneRowPerUserPerWeek() {
        NXP_UsageService.record('Match Inbox');
        NXP_UsageService.record('Forecasts');
        NXP_UsageService.record('Match Inbox');
        NXP_UsageService.record('Something else');
        NXP_Usage__c u = [SELECT User__c, Week__c, Views__c, Screens__c, Last_Screen__c FROM NXP_Usage__c];
        System.assertEquals(UserInfo.getUserId(), u.User__c);
        System.assertEquals(Date.today().toStartOfWeek(), u.Week__c);
        System.assertEquals(3, u.Views__c);
        System.assertEquals('Match Inbox, Forecasts', u.Screens__c);
        System.assertEquals('Match Inbox', u.Last_Screen__c);
    }
}
