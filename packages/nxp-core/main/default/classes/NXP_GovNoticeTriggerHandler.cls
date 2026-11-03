/**
 * Gov Notice trigger logic: keeps Name in step with Title, sets Source from Source Feed and re-scores
 * fit when scored fields change.
 * Versioning and change events are owned by NXP_IngestionService, not this trigger.
 */
public with sharing class NXP_GovNoticeTriggerHandler extends NXP_TriggerHandler {
    private static final List<SObjectField> SCORED_FIELDS = new List<SObjectField>{
        NXP_Gov_Notice__c.NAICS_Code__c,
        NXP_Gov_Notice__c.PSC_Code__c,
        NXP_Gov_Notice__c.Agency_Path__c,
        NXP_Gov_Notice__c.Office__c,
        NXP_Gov_Notice__c.Set_Aside__c,
        NXP_Gov_Notice__c.Title__c,
        NXP_Gov_Notice__c.Description__c,
        NXP_Gov_Notice__c.Estimated_Value__c,
        NXP_Gov_Notice__c.Contract_Vehicle__c
    };

    protected override String handlerName() {
        return 'NXP_GovNoticeTriggerHandler';
    }

    protected override void beforeInsert(List<SObject> newRecords) {
        List<NXP_Gov_Notice__c> notices = (List<NXP_Gov_Notice__c>) newRecords;
        syncName(notices);
        new NXP_FitScoreService().score(notices);
    }

    protected override void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<NXP_Gov_Notice__c> notices = (List<NXP_Gov_Notice__c>) newRecords;
        syncName(notices);
        List<NXP_Gov_Notice__c> toScore = new List<NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : notices) {
            SObject old = oldMap.get(n.Id);
            for (SObjectField f : SCORED_FIELDS) {
                if (n.get(f) != old.get(f)) {
                    toScore.add(n);
                    break;
                }
            }
        }
        if (!toScore.isEmpty()) {
            new NXP_FitScoreService().score(toScore);
        }
    }

    private static void syncName(List<NXP_Gov_Notice__c> notices) {
        for (NXP_Gov_Notice__c n : notices) {
            String source = sourceFor(n.Source_Feed__c);
            if (source != null) {
                n.Source__c = source;
            }
            if (String.isNotBlank(n.Title__c)) {
                n.Name = n.Title__c.left(80);
            } else if (String.isBlank(n.Name)) {
                n.Name = String.isBlank(n.Notice_Id__c) ? 'Untitled notice' : n.Notice_Id__c.left(80);
            }
        }
    }

    /** The Source picklist value for a Source Feed: SAM.gov, GSA eBuy, Partner API or Other (null when blank). */
    public static String sourceFor(String feed) {
        if (String.isBlank(feed)) {
            return null;
        }
        String f = feed.toLowerCase();
        if (f.startsWith('sam')) {
            return 'SAM.gov';
        }
        if (f.contains('ebuy')) {
            return 'GSA eBuy';
        }
        if (f.startsWith('rest')) {
            return 'Partner API';
        }
        return 'Other';
    }
}
