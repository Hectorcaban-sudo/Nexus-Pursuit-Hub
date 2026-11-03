// Fills the Source picklist (SAM.gov, GSA eBuy, Partner API, Other) on notices loaded before it existed.
// New and updated notices get it automatically. Up to 9,000 notices per run: run it again until it
// says 0 updated.
List<NXP_Gov_Notice__c> updates = new List<NXP_Gov_Notice__c>();
for (NXP_Gov_Notice__c n : [
    SELECT Id, Source_Feed__c
    FROM NXP_Gov_Notice__c
    WHERE Source__c = NULL AND Source_Feed__c != NULL
    LIMIT 9000
]) {
    updates.add(new NXP_Gov_Notice__c(Id = n.Id, Source__c = NXP_GovNoticeTriggerHandler.sourceFor(n.Source_Feed__c)));
}
NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
Database.update(updates, false);
NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
Integer left = [SELECT COUNT() FROM NXP_Gov_Notice__c WHERE Source__c = NULL AND Source_Feed__c != NULL];
System.debug(LoggingLevel.ERROR, 'Source backfill: ' + updates.size() + ' updated, ' + left + ' left. Run again if more than 0 left.');
