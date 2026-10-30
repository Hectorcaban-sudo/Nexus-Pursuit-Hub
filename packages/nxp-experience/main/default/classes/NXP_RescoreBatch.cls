/**
 * Re-scores open notices after a Company Profile or fit rule change (Settings tab › Rescore
 * notices). The batch form of scripts/apex/rescore-notices.apex.
 */
public without sharing class NXP_RescoreBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            'SELECT ' + NXP_GovNoticeSelector.FIELDS + ' FROM NXP_Gov_Notice__c WHERE Status__c = \'Active\''
        );
    }

    public void execute(Database.BatchableContext context, List<NXP_Gov_Notice__c> scope) {
        new NXP_FitScoreService().score(scope);
        NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
        Database.update(scope, false, AccessLevel.SYSTEM_MODE);
        NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
    }

    public void finish(Database.BatchableContext context) {
    }
}
