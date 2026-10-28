trigger NXP_GovNoticeTrigger on NXP_Gov_Notice__c(before insert, before update) {
    new NXP_GovNoticeTriggerHandler().run();
}
