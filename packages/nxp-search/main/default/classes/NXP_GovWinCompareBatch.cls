/**
 * GovWin parallel run: for each GovWin alert loaded from a GovWin export, finds the Nexus notice with
 * the same solicitation number (or notice id) and whether any saved search matched it, and sets
 * Result__c: Caught by a search, In Nexus no search matched, or Not in Nexus. Feeds the Adoption
 * dashboard's catch rate. Run after each load: scripts/load-govwin-export (.sh / .ps1).
 * Compares across every user's searches, so without sharing.
 */
public without sharing class NXP_GovWinCompareBatch implements Database.Batchable<SObject> {
    public static final String CAUGHT = 'Caught by a search';
    public static final String NO_SEARCH = 'In Nexus, no search matched';
    public static final String MISSING = 'Not in Nexus';

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            [SELECT Id, Solicitation_Number__c FROM NXP_GovWin_Alert__c ORDER BY Alert_Date__c DESC]
        );
    }

    public void execute(Database.BatchableContext context, List<NXP_GovWin_Alert__c> scope) {
        compare(scope);
    }

    public void finish(Database.BatchableContext context) {
    }

    public static void compare(List<NXP_GovWin_Alert__c> alerts) {
        Set<String> keys = new Set<String>();
        for (NXP_GovWin_Alert__c a : alerts) {
            if (String.isNotBlank(a.Solicitation_Number__c)) {
                keys.add(a.Solicitation_Number__c.trim());
            }
        }
        Map<String, Id> noticeByKey = new Map<String, Id>();
        if (!keys.isEmpty()) {
            for (NXP_Gov_Notice__c n : [
                SELECT Id, Solicitation_Number__c, Notice_Id__c
                FROM NXP_Gov_Notice__c
                WHERE Solicitation_Number__c IN :keys OR Notice_Id__c IN :keys
            ]) {
                if (n.Solicitation_Number__c != null) {
                    noticeByKey.put(n.Solicitation_Number__c.toLowerCase(), n.Id);
                }
                if (n.Notice_Id__c != null && !noticeByKey.containsKey(n.Notice_Id__c.toLowerCase())) {
                    noticeByKey.put(n.Notice_Id__c.toLowerCase(), n.Id);
                }
            }
        }
        Map<Id, Integer> matchCount = new Map<Id, Integer>();
        Set<Id> noticeIds = new Set<Id>(noticeByKey.values());
        if (!noticeIds.isEmpty()) {
            for (AggregateResult r : [
                SELECT Gov_Notice__c notice, COUNT(Id) n
                FROM NXP_Search_Match__c
                WHERE Gov_Notice__c IN :noticeIds
                GROUP BY Gov_Notice__c
            ]) {
                matchCount.put((Id) r.get('notice'), (Integer) r.get('n'));
            }
        }
        Datetime now = Datetime.now();
        for (NXP_GovWin_Alert__c a : alerts) {
            Id noticeId = a.Solicitation_Number__c == null
                ? null
                : noticeByKey.get(a.Solicitation_Number__c.trim().toLowerCase());
            Integer matches = noticeId == null || !matchCount.containsKey(noticeId) ? 0 : matchCount.get(noticeId);
            a.Gov_Notice__c = noticeId;
            a.Search_Matches__c = matches;
            a.Result__c = noticeId == null ? MISSING : (matches > 0 ? CAUGHT : NO_SEARCH);
            a.Compared__c = now;
        }
        update alerts;
    }
}
