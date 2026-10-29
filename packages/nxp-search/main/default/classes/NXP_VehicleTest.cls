@IsTest
private class NXP_VehicleTest {
    @TestSetup
    static void setup() {
        insert new NXP_Company_Profile__c(
            Name = 'Our company',
            Active__c = true,
            NAICS_Codes__c = '5415*',
            Vehicle_Codes__c = 'LISTED-1'
        );
        Date today = Date.today();
        NXP_Contract_Vehicle__c held = new NXP_Contract_Vehicle__c(
            Name = 'Held vehicle',
            Vehicle_Code__c = 'HELD-1',
            We_Hold__c = true,
            Ceiling__c = 60000000000.0,
            Expiry_Date__c = today.addMonths(11),
            Inbox_Address__c = 'held-orders@example.com'
        );
        NXP_Contract_Vehicle__c listed = new NXP_Contract_Vehicle__c(
            Name = 'Listed on profile',
            Vehicle_Code__c = 'LISTED-1',
            Expiry_Date__c = today.addYears(5)
        );
        NXP_Contract_Vehicle__c missing = new NXP_Contract_Vehicle__c(Name = 'Not held', Vehicle_Code__c = 'NOPE-1');
        NXP_Contract_Vehicle__c idle = new NXP_Contract_Vehicle__c(
            Name = 'Not held, nothing open',
            Vehicle_Code__c = 'IDLE-1'
        );
        insert new List<NXP_Contract_Vehicle__c>{ held, listed, missing, idle };

        Datetime now = Datetime.now();
        insert new List<NXP_Gov_Notice__c>{
            new NXP_Gov_Notice__c(
                Notice_Id__c = 'T-V-1',
                Title__c = 'Help desk task order',
                Notice_Type__c = 'Task Order',
                Status__c = 'Active',
                Response_Due__c = now.addDays(10),
                Contract_Vehicle__c = held.Id,
                Pushed__c = true
            ),
            new NXP_Gov_Notice__c(
                Notice_Id__c = 'T-V-2',
                Title__c = 'Dashboard integration',
                Notice_Type__c = 'Solicitation',
                Status__c = 'Active',
                Response_Due__c = now.addDays(45),
                Contract_Vehicle__c = held.Id
            ),
            new NXP_Gov_Notice__c(
                Notice_Id__c = 'T-V-3',
                Title__c = 'Closed one',
                Notice_Type__c = 'Solicitation',
                Status__c = 'Active',
                Response_Due__c = now.addDays(-2),
                Contract_Vehicle__c = held.Id
            ),
            new NXP_Gov_Notice__c(
                Notice_Id__c = 'T-V-4',
                Title__c = 'Network segmentation pilot',
                Notice_Type__c = 'Sources Sought',
                Status__c = 'Active',
                Response_Due__c = now.addDays(20),
                Contract_Vehicle__c = missing.Id
            )
        };

        PermissionSet admin = [SELECT Id FROM PermissionSet WHERE Name = 'NXP_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<PermissionSetAssignment> existing = [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :admin.Id
            ];
            if (existing.isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = admin.Id);
            }
        }
    }

    private static NXP_VehicleController.VehicleCard card(List<NXP_VehicleController.VehicleCard> cards, String code) {
        for (NXP_VehicleController.VehicleCard c : cards) {
            if (c.code == code) {
                return c;
            }
        }
        return null;
    }

    @IsTest
    static void portfolioSplitsHeldAndNotHeld() {
        NXP_VehicleController.vehicleRuleOverride = false;
        NXP_Gov_Notice__c followed = [SELECT Id FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'T-V-2'];
        NXP_WatchService.setWatch(followed.Id, true);

        Test.startTest();
        NXP_VehicleController.Portfolio p = NXP_VehicleController.getVehiclePortfolio();
        Test.stopTest();

        System.assertEquals(2, p.held.size(), 'We Hold ticked, plus the code listed on the profile');
        NXP_VehicleController.VehicleCard held = card(p.held, 'HELD-1');
        System.assertEquals(2, held.open, 'the closed notice is left out');
        System.assertEquals(1, held.dueIn30);
        System.assertEquals(1, held.pushed);
        System.assertEquals(1, held.taskOrders30);
        System.assertNotEquals(null, held.lastTaskOrder);
        System.assertEquals('T-V-1', held.notices[0].noticeKey, 'soonest due first');
        System.assert(held.notices[1].following);
        System.assert(!held.heldByProfile);
        System.assert(card(p.held, 'LISTED-1').heldByProfile);

        System.assertEquals(1, p.notHeld.size(), 'only vehicles we lack that have open notices');
        System.assertEquals('NOPE-1', p.notHeld[0].code);
        System.assertEquals(1, p.blockedNotices);
        System.assertEquals(1, p.otherVehicles);

        System.assertEquals(2, p.openOnHeld);
        System.assertEquals(1, p.expiringSoon);
        System.assertEquals(1, p.inboxesSet);
        System.assertEquals(1, p.taskOrders30);
        System.assert(p.canManage);
        System.assert(!p.vehicleRuleActive);
    }

    @IsTest
    static void markHeldAndNotHeld() {
        NXP_Contract_Vehicle__c missing = [SELECT Id FROM NXP_Contract_Vehicle__c WHERE Vehicle_Code__c = 'NOPE-1'];
        NXP_Contract_Vehicle__c listed = [SELECT Id FROM NXP_Contract_Vehicle__c WHERE Vehicle_Code__c = 'LISTED-1'];

        Test.startTest();
        String heldMessage = NXP_VehicleController.setHeld(missing.Id, true);
        String stillHeld = NXP_VehicleController.setHeld(listed.Id, false);
        Test.stopTest();

        System.assert(heldMessage.contains('marked as held'), heldMessage);
        System.assert(heldMessage.contains('1 open notice'), heldMessage);
        System.assert([SELECT We_Hold__c FROM NXP_Contract_Vehicle__c WHERE Id = :missing.Id].We_Hold__c);
        System.assert(stillHeld.contains('still counted as held'), stillHeld);

        NXP_VehicleController.Portfolio p = NXP_VehicleController.getVehiclePortfolio();
        System.assertEquals(3, p.held.size());
        System.assertEquals(0, p.notHeld.size());
    }

    @IsTest
    static void emptyOrg() {
        delete [SELECT Id FROM NXP_Gov_Notice__c];
        delete [SELECT Id FROM NXP_Contract_Vehicle__c];
        NXP_VehicleController.Portfolio p = NXP_VehicleController.getVehiclePortfolio();
        System.assertEquals(0, p.held.size());
        System.assertEquals(0, p.notHeld.size());
    }
}
