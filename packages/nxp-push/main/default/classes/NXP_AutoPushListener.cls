/**
 * Match listener (registered in NXP_Setting Match_Listeners) that auto-pushes new matches for
 * saved searches with Auto-Push on: "All Matches", or "Fit Threshold" at or above
 * Auto_Push_Min_Fit__c. The push runs in a Queueable as the search owner.
 */
public without sharing class NXP_AutoPushListener implements NXP_MatchListener {
    public void onMatches(List<NXP_Search_Match__c> matches) {
        Set<Id> searchIds = new Set<Id>();
        Set<Id> noticeIds = new Set<Id>();
        for (NXP_Search_Match__c m : matches) {
            if (m.Change_Type__c == 'New') {
                searchIds.add(m.Saved_Search__c);
                noticeIds.add(m.Gov_Notice__c);
            }
        }
        if (searchIds.isEmpty()) {
            return;
        }
        Map<Id, NXP_Saved_Search__c> searches = new Map<Id, NXP_Saved_Search__c>(
            [
                SELECT Id, OwnerId, Auto_Push__c, Auto_Push_Min_Fit__c
                FROM NXP_Saved_Search__c
                WHERE Id IN :searchIds AND Auto_Push__c IN ('Fit Threshold', 'All Matches') AND Active__c = TRUE
            ]
        );
        if (searches.isEmpty()) {
            return;
        }
        Map<Id, NXP_Gov_Notice__c> notices = new Map<Id, NXP_Gov_Notice__c>(
            [SELECT Id, Fit_Score__c, Pushed__c FROM NXP_Gov_Notice__c WHERE Id IN :noticeIds]
        );
        Map<Id, Set<Id>> byOwner = new Map<Id, Set<Id>>();
        for (NXP_Search_Match__c m : matches) {
            NXP_Saved_Search__c s = searches.get(m.Saved_Search__c);
            NXP_Gov_Notice__c n = notices.get(m.Gov_Notice__c);
            if (s == null || n == null || n.Pushed__c || m.Change_Type__c != 'New') {
                continue;
            }
            if (
                s.Auto_Push__c == 'Fit Threshold' &&
                (n.Fit_Score__c == null ||
                s.Auto_Push_Min_Fit__c == null ||
                n.Fit_Score__c < s.Auto_Push_Min_Fit__c)
            ) {
                continue;
            }
            if (!byOwner.containsKey(s.OwnerId)) {
                byOwner.put(s.OwnerId, new Set<Id>());
            }
            byOwner.get(s.OwnerId).add(n.Id);
        }
        if (!byOwner.isEmpty()) {
            System.enqueueJob(new NXP_AutoPushJob(byOwner));
        }
    }
}
