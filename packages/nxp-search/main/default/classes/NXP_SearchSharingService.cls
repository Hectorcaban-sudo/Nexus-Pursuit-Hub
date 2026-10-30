/**
 * Applies a saved search's Visibility with Apex-managed sharing (the object is Private):
 *   Private      - owner only
 *   Team         - read access for the public group named in Team_Group__c
 *   Org Template - read access for All Internal Users (others can clone it)
 */
public without sharing class NXP_SearchSharingService {
    public static void apply(List<NXP_Saved_Search__c> searches) {
        Set<Id> ids = new Map<Id, NXP_Saved_Search__c>(searches).keySet();
        delete [
            SELECT Id
            FROM NXP_Saved_Search__Share
            WHERE ParentId IN :ids AND RowCause = :Schema.NXP_Saved_Search__Share.RowCause.Manual
        ];

        Set<String> groupNames = new Set<String>();
        for (NXP_Saved_Search__c s : searches) {
            if (s.Visibility__c == 'Team' && String.isNotBlank(s.Team_Group__c)) {
                groupNames.add(s.Team_Group__c);
            }
        }
        Map<String, Id> groups = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Regular' AND DeveloperName IN :groupNames]) {
            groups.put(g.DeveloperName, g.Id);
        }
        Id everyone;
        for (Group g : [SELECT Id FROM Group WHERE Type = 'Organization' LIMIT 1]) {
            everyone = g.Id;
        }

        List<NXP_Saved_Search__Share> shares = new List<NXP_Saved_Search__Share>();
        for (NXP_Saved_Search__c s : searches) {
            Id target = s.Visibility__c == 'Team'
                ? groups.get(s.Team_Group__c)
                : s.Visibility__c == 'Org Template' ? everyone : null;
            if (target != null) {
                shares.add(
                    new NXP_Saved_Search__Share(
                        ParentId = s.Id,
                        UserOrGroupId = target,
                        AccessLevel = 'Read',
                        RowCause = Schema.NXP_Saved_Search__Share.RowCause.Manual
                    )
                );
            }
        }
        Database.insert(shares, false);
    }

    /** Template Id -> how many searches were copied from it, counting everyone's (a number only). */
    public static Map<Id, Integer> copyCounts(Set<Id> templateIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (templateIds == null || templateIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult r : [
            SELECT Template__c t, COUNT(Id) c
            FROM NXP_Saved_Search__c
            WHERE Template__c IN :templateIds
            GROUP BY Template__c
        ]) {
            counts.put((Id) r.get('t'), (Integer) r.get('c'));
        }
        return counts;
    }
}
