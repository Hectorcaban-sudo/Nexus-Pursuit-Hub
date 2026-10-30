@IsTest
private class NXP_GovWinCompareTest {
    @IsTest
    static void classifiesEachAlert() {
        NXP_Gov_Notice__c caught = new NXP_Gov_Notice__c(
            Notice_Id__c = 'GW-T-1',
            Solicitation_Number__c = 'SOL-1',
            Title__c = 'A',
            Status__c = 'Active'
        );
        NXP_Gov_Notice__c quiet = new NXP_Gov_Notice__c(
            Notice_Id__c = 'GW-T-2',
            Solicitation_Number__c = 'SOL-2',
            Title__c = 'B',
            Status__c = 'Active'
        );
        insert new List<NXP_Gov_Notice__c>{ caught, quiet };
        NXP_Saved_Search__c s = new NXP_Saved_Search__c(Name = 'S', Criteria_JSON__c = '{}', Active__c = true);
        insert s;
        insert new NXP_Search_Match__c(Saved_Search__c = s.Id, Gov_Notice__c = caught.Id, Match_Key__c = 'k1');

        List<NXP_GovWin_Alert__c> alerts = new List<NXP_GovWin_Alert__c>{
            new NXP_GovWin_Alert__c(GovWin_Id__c = 'G1', Solicitation_Number__c = 'sol-1'),
            new NXP_GovWin_Alert__c(GovWin_Id__c = 'G2', Solicitation_Number__c = 'GW-T-2'),
            new NXP_GovWin_Alert__c(GovWin_Id__c = 'G3', Solicitation_Number__c = 'SOL-9'),
            new NXP_GovWin_Alert__c(GovWin_Id__c = 'G4')
        };
        insert alerts;
        Test.startTest();
        Database.executeBatch(new NXP_GovWinCompareBatch());
        Test.stopTest();

        Map<String, NXP_GovWin_Alert__c> byId = new Map<String, NXP_GovWin_Alert__c>();
        for (NXP_GovWin_Alert__c a : [
            SELECT GovWin_Id__c, Result__c, Gov_Notice__c, Search_Matches__c
            FROM NXP_GovWin_Alert__c
        ]) {
            byId.put(a.GovWin_Id__c, a);
        }
        System.assertEquals(NXP_GovWinCompareBatch.CAUGHT, byId.get('G1').Result__c);
        System.assertEquals(1, byId.get('G1').Search_Matches__c);
        System.assertEquals(NXP_GovWinCompareBatch.NO_SEARCH, byId.get('G2').Result__c, 'matched by notice id');
        System.assertEquals(NXP_GovWinCompareBatch.MISSING, byId.get('G3').Result__c);
        System.assertEquals(NXP_GovWinCompareBatch.MISSING, byId.get('G4').Result__c);
    }
}
