/**
 * Data for the Contract Vehicles tab (nxpVehiclePortfolio): the vehicles we hold with the open
 * notices released on them, expiry and task-order inbox status, and open notices that require a
 * vehicle we don't hold. Admins can record that we hold (or no longer hold) a vehicle.
 * Reads run in user mode; the company profile (configuration) is read in system mode.
 */
public with sharing class NXP_VehicleController {
    @TestVisible
    private static final Integer NOTICES_PER_VEHICLE = 5;
    private static final Integer EXPIRING_DAYS = 365;

    public class VehicleNotice {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String noticeKey;
        @AuraEnabled
        public String noticeType;
        @AuraEnabled
        public String agency;
        @AuraEnabled
        public Datetime responseDue;
        @AuraEnabled
        public Decimal fitScore;
        @AuraEnabled
        public Boolean pushed = false;
        @AuraEnabled
        public Boolean following = false;
    }

    public class VehicleCard {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String code;
        @AuraEnabled
        public Boolean held = false;
        /** true when held only because the code is listed on the Company Profile */
        @AuraEnabled
        public Boolean heldByProfile = false;
        @AuraEnabled
        public Decimal ceiling;
        @AuraEnabled
        public Date expiryDate;
        @AuraEnabled
        public Integer daysLeft;
        @AuraEnabled
        public String inboxAddress;
        @AuraEnabled
        public Integer open = 0;
        @AuraEnabled
        public Integer dueIn30 = 0;
        @AuraEnabled
        public Integer pushed = 0;
        @AuraEnabled
        public Integer taskOrders30 = 0;
        @AuraEnabled
        public Datetime lastTaskOrder;
        @AuraEnabled
        public List<VehicleNotice> notices = new List<VehicleNotice>();
    }

    public class Portfolio {
        @AuraEnabled
        public List<VehicleCard> held = new List<VehicleCard>();
        /** vehicles we don't hold that have open notices */
        @AuraEnabled
        public List<VehicleCard> notHeld = new List<VehicleCard>();
        @AuraEnabled
        public Integer openOnHeld = 0;
        @AuraEnabled
        public Integer dueIn30 = 0;
        @AuraEnabled
        public Integer expiringSoon = 0;
        @AuraEnabled
        public Integer blockedNotices = 0;
        @AuraEnabled
        public Integer inboxesSet = 0;
        @AuraEnabled
        public Integer taskOrders30 = 0;
        @AuraEnabled
        public Datetime lastTaskOrder;
        @AuraEnabled
        public Integer otherVehicles = 0;
        @AuraEnabled
        public Boolean vehicleRuleActive = false;
        @AuraEnabled
        public Boolean canManage = false;
    }

    @TestVisible
    private static Boolean vehicleRuleOverride;

    @AuraEnabled
    public static Portfolio getVehiclePortfolio() {
        try {
            Portfolio p = new Portfolio();
            p.canManage = FeatureManagement.checkPermission('NXP_Admin_Access');
            p.vehicleRuleActive = vehicleRuleActive();
            NXP_Company_Profile__c profile = activeProfile();

            Map<Id, VehicleCard> cards = new Map<Id, VehicleCard>();
            for (NXP_Contract_Vehicle__c v : [
                SELECT Id, Name, Vehicle_Code__c, We_Hold__c, Ceiling__c, Expiry_Date__c, Inbox_Address__c
                FROM NXP_Contract_Vehicle__c
                WITH USER_MODE
                ORDER BY Expiry_Date__c ASC NULLS LAST, Name
                LIMIT 500
            ]) {
                cards.put(v.Id, toCard(v, profile));
            }
            if (cards.isEmpty()) {
                return p;
            }
            addOpenNotices(cards);
            addTaskOrders(cards);

            for (VehicleCard c : cards.values()) {
                if (c.held) {
                    p.held.add(c);
                    p.openOnHeld += c.open;
                    p.dueIn30 += c.dueIn30;
                    p.taskOrders30 += c.taskOrders30;
                    if (c.daysLeft != null && c.daysLeft <= EXPIRING_DAYS) {
                        p.expiringSoon++;
                    }
                    if (String.isNotBlank(c.inboxAddress)) {
                        p.inboxesSet++;
                    }
                    if (c.lastTaskOrder != null && (p.lastTaskOrder == null || c.lastTaskOrder > p.lastTaskOrder)) {
                        p.lastTaskOrder = c.lastTaskOrder;
                    }
                } else if (c.open > 0) {
                    p.notHeld.add(c);
                    p.blockedNotices += c.open;
                } else {
                    p.otherVehicles++;
                }
            }
            return p;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * Records that we hold (or no longer hold) a vehicle and re-scores its open notices.
     * Nexus admins only. Returns a message for the toast.
     */
    @AuraEnabled
    public static String setHeld(Id vehicleId, Boolean held) {
        if (!FeatureManagement.checkPermission('NXP_Admin_Access')) {
            throw new AuraHandledException('Only Nexus admins can change which vehicles we hold.');
        }
        try {
            NXP_Contract_Vehicle__c v = [
                SELECT Id, Name, Vehicle_Code__c, We_Hold__c
                FROM NXP_Contract_Vehicle__c
                WHERE Id = :vehicleId
                WITH USER_MODE
            ];
            v.We_Hold__c = held == true;
            Database.update(v, AccessLevel.USER_MODE);

            List<NXP_Gov_Notice__c> notices = Database.queryWithBinds(
                'SELECT ' +
                    NXP_GovNoticeSelector.FIELDS +
                    ' FROM NXP_Gov_Notice__c WHERE Contract_Vehicle__c = :vehicleId AND Status__c = \'Active\' LIMIT 2000',
                new Map<String, Object>{ 'vehicleId' => vehicleId },
                AccessLevel.SYSTEM_MODE
            );
            if (!notices.isEmpty()) {
                new NXP_FitScoreService().score(notices);
                NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
                try {
                    Database.update(notices, AccessLevel.SYSTEM_MODE);
                } finally {
                    NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
                }
            }

            String rescored = notices.isEmpty() ? '' : ' ' + notices.size() + ' open notice(s) re-scored.';
            if (held != true && NXP_FitScoreService.isHeld(v, activeProfile())) {
                return v.Name +
                    ' is still counted as held because ' +
                    v.Vehicle_Code__c +
                    ' is listed in the Company Profile\'s Vehicles We Hold.' +
                    rescored;
            }
            return (held == true ? v.Name + ' marked as held.' : v.Name + ' marked as not held.') + rescored;
        } catch (Exception e) {
            NXP_Logger.error('NXP_VehicleController', 'Changing a held vehicle failed', e, vehicleId);
            NXP_Logger.flush();
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------------------- helpers

    private static VehicleCard toCard(NXP_Contract_Vehicle__c v, NXP_Company_Profile__c profile) {
        VehicleCard c = new VehicleCard();
        c.id = v.Id;
        c.name = v.Name;
        c.code = v.Vehicle_Code__c;
        c.held = NXP_FitScoreService.isHeld(v, profile);
        c.heldByProfile = c.held && v.We_Hold__c != true;
        c.ceiling = v.Ceiling__c;
        c.expiryDate = v.Expiry_Date__c;
        c.daysLeft = v.Expiry_Date__c == null ? null : Date.today().daysBetween(v.Expiry_Date__c);
        c.inboxAddress = v.Inbox_Address__c;
        return c;
    }

    private static void addOpenNotices(Map<Id, VehicleCard> cards) {
        Set<Id> vehicleIds = cards.keySet();
        Datetime now = Datetime.now();
        Datetime in30 = now.addDays(30);
        List<NXP_Gov_Notice__c> notices = [
            SELECT
                Id,
                Name,
                Title__c,
                Notice_Id__c,
                Notice_Type__c,
                Agency_Path__c,
                Response_Due__c,
                Fit_Score__c,
                Pushed__c,
                Contract_Vehicle__c
            FROM NXP_Gov_Notice__c
            WHERE
                Status__c = 'Active'
                AND (Response_Due__c >= :now
                OR Response_Due__c = NULL)
                AND Contract_Vehicle__c IN :vehicleIds
            WITH USER_MODE
            ORDER BY Response_Due__c ASC NULLS LAST
            LIMIT 2000
        ];
        Set<Id> shown = new Set<Id>();
        for (NXP_Gov_Notice__c n : notices) {
            VehicleCard c = cards.get(n.Contract_Vehicle__c);
            c.open++;
            if (n.Response_Due__c != null && n.Response_Due__c <= in30) {
                c.dueIn30++;
            }
            if (n.Pushed__c == true) {
                c.pushed++;
            }
            if (c.notices.size() < NOTICES_PER_VEHICLE) {
                c.notices.add(toNotice(n));
                shown.add(n.Id);
            }
        }
        Set<Id> following = NXP_WatchService.watchedByMe(shown);
        for (VehicleCard c : cards.values()) {
            for (VehicleNotice vn : c.notices) {
                vn.following = following.contains(vn.id);
            }
        }
    }

    private static void addTaskOrders(Map<Id, VehicleCard> cards) {
        Set<Id> vehicleIds = cards.keySet();
        Datetime since = Datetime.now().addDays(-30);
        for (AggregateResult r : [
            SELECT Contract_Vehicle__c vehicle, COUNT(Id) received, MAX(CreatedDate) latest
            FROM NXP_Gov_Notice__c
            WHERE Notice_Type__c = 'Task Order' AND Contract_Vehicle__c IN :vehicleIds AND CreatedDate >= :since
            WITH USER_MODE
            GROUP BY Contract_Vehicle__c
        ]) {
            VehicleCard c = cards.get((Id) r.get('vehicle'));
            c.taskOrders30 = (Integer) r.get('received');
            c.lastTaskOrder = (Datetime) r.get('latest');
        }
    }

    private static VehicleNotice toNotice(NXP_Gov_Notice__c n) {
        VehicleNotice vn = new VehicleNotice();
        vn.id = n.Id;
        vn.title = n.Title__c == null ? n.Name : n.Title__c;
        vn.noticeKey = n.Notice_Id__c;
        vn.noticeType = n.Notice_Type__c;
        vn.agency = n.Agency_Path__c;
        vn.responseDue = n.Response_Due__c;
        vn.fitScore = n.Fit_Score__c;
        vn.pushed = n.Pushed__c == true;
        return vn;
    }

    private static NXP_Company_Profile__c activeProfile() {
        List<NXP_Company_Profile__c> profiles = [
            SELECT Id, Vehicle_Codes__c
            FROM NXP_Company_Profile__c
            WHERE Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return profiles.isEmpty() ? null : profiles[0];
    }

    private static Boolean vehicleRuleActive() {
        if (vehicleRuleOverride != null) {
            return vehicleRuleOverride;
        }
        for (NXP_Fit_Rule__mdt rule : NXP_Fit_Rule__mdt.getAll().values()) {
            if (rule.Rule_Type__c == 'Vehicle' && rule.Active__c && rule.Weight__c != null && rule.Weight__c > 0) {
                return true;
            }
        }
        return false;
    }

    private static Exception handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return e;
        }
        AuraHandledException a = new AuraHandledException(e.getMessage());
        a.setMessage(e.getMessage());
        return a;
    }
}
