/**
 * Retries failed auto-pushes (Push Log status Retry Pending) up to Push_Max_Attempts.
 * Schedule hourly: System.schedule('NXP Push Retry', '0 20 * * * ?', new NXP_PushRetryJob());
 */
public without sharing class NXP_PushRetryJob implements Schedulable, Queueable {
    public void execute(SchedulableContext context) {
        System.enqueueJob(new NXP_PushRetryJob());
    }

    public void execute(QueueableContext context) {
        Integer maxAttempts = NXP_Settings.getInteger('Push_Max_Attempts', 3);
        List<NXP_Push_Log__c> pending = [
            SELECT Id, Gov_Notice__c, Pushed_By__c, Attempts__c
            FROM NXP_Push_Log__c
            WHERE Status__c = 'Retry Pending' AND Attempts__c < :maxAttempts
            ORDER BY CreatedDate
            LIMIT 200
        ];
        Map<Id, List<Id>> byOwner = new Map<Id, List<Id>>();
        for (NXP_Push_Log__c l : pending) {
            Id owner = l.Pushed_By__c == null ? UserInfo.getUserId() : l.Pushed_By__c;
            if (!byOwner.containsKey(owner)) {
                byOwner.put(owner, new List<Id>());
            }
            byOwner.get(owner).add(l.Gov_Notice__c);
            // The retry writes its own log row; this one is closed out.
            l.Status__c = 'Failed';
            l.Attempts__c = l.Attempts__c == null ? 1 : l.Attempts__c + 1;
        }
        update as system pending;
        for (Id owner : byOwner.keySet()) {
            NXP_PushService.push(byOwner.get(owner), owner, NXP_PushService.MODE_AUTO, true);
        }
    }
}
