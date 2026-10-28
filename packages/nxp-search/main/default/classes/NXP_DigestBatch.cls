/**
 * Daily or weekly digest: one email per user, a section per saved search, listing matches whose
 * alert is still Pending. Schedule with NXP_DigestBatch.scheduleDefaults() (06:30 daily, 06:30
 * Monday weekly, in the scheduling user's time zone).
 */
public without sharing class NXP_DigestBatch implements Database.Batchable<SObject>, Schedulable {
    private final String frequency;

    public NXP_DigestBatch(String frequency) {
        this.frequency = frequency == 'Weekly' ? 'Weekly' : 'Daily';
    }

    public static void scheduleDefaults() {
        System.schedule('NXP Daily Digest', '0 30 6 * * ?', new NXP_DigestBatch('Daily'));
        System.schedule('NXP Weekly Digest', '0 30 6 ? * MON', new NXP_DigestBatch('Weekly'));
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new NXP_DigestBatch(frequency), 20);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        String freq = frequency;
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM User
                WHERE
                    IsActive = TRUE
                    AND Id IN (
                        SELECT OwnerId
                        FROM NXP_Saved_Search__c
                        WHERE Active__c = TRUE AND Alert_Frequency__c = :freq
                    )
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<User> users) {
        Set<Id> userIds = new Map<Id, User>(users).keySet();
        String freq = frequency;
        List<NXP_Saved_Search__c> searches = [
            SELECT Id, Name, OwnerId
            FROM NXP_Saved_Search__c
            WHERE OwnerId IN :userIds AND Active__c = TRUE AND Alert_Frequency__c = :freq
            ORDER BY Name
        ];
        Map<Id, NXP_Saved_Search__c> searchById = new Map<Id, NXP_Saved_Search__c>(searches);
        List<NXP_Search_Match__c> matches = [
            SELECT Id, Saved_Search__c, Gov_Notice__c, Change_Type__c
            FROM NXP_Search_Match__c
            WHERE
                Saved_Search__c IN :searchById.keySet()
                AND Alert_Status__c = 'Pending'
                AND User_Action__c != 'Dismissed'
            ORDER BY Matched_At__c DESC
            LIMIT 5000
        ];
        Set<Id> noticeIds = new Set<Id>();
        Map<Id, List<NXP_Search_Match__c>> bySearch = new Map<Id, List<NXP_Search_Match__c>>();
        for (NXP_Search_Match__c m : matches) {
            noticeIds.add(m.Gov_Notice__c);
            if (!bySearch.containsKey(m.Saved_Search__c)) {
                bySearch.put(m.Saved_Search__c, new List<NXP_Search_Match__c>());
            }
            bySearch.get(m.Saved_Search__c).add(m);
        }
        Map<Id, NXP_Gov_Notice__c> notices = new Map<Id, NXP_Gov_Notice__c>(
            new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byIds(noticeIds)
        );

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<NXP_Search_Match__c> sent = new List<NXP_Search_Match__c>();
        List<NXP_Saved_Search__c> stamped = new List<NXP_Saved_Search__c>();
        for (Id userId : userIds) {
            List<NXP_Saved_Search__c> mine = new List<NXP_Saved_Search__c>();
            Integer total = 0;
            for (NXP_Saved_Search__c s : searches) {
                if (s.OwnerId == userId && bySearch.containsKey(s.Id)) {
                    mine.add(s);
                    total += bySearch.get(s.Id).size();
                }
            }
            if (total == 0) {
                continue;
            }
            emails.add(
                NXP_AlertService.email(
                    userId,
                    freq + ' digest · ' + total + ' match(es)',
                    NXP_AlertService.digestHtml(mine, bySearch, notices)
                )
            );
            for (NXP_Saved_Search__c s : mine) {
                stamped.add(new NXP_Saved_Search__c(Id = s.Id, Last_Digest_Sent__c = Datetime.now()));
                for (NXP_Search_Match__c m : bySearch.get(s.Id)) {
                    sent.add(new NXP_Search_Match__c(Id = m.Id, Alert_Status__c = 'Sent'));
                }
            }
        }
        NXP_AlertService.sendEmails(emails);
        Database.update(sent, false, AccessLevel.SYSTEM_MODE);
        Database.update(stamped, false, AccessLevel.SYSTEM_MODE);
        NXP_Logger.flush();
    }

    public void finish(Database.BatchableContext context) {
    }
}
