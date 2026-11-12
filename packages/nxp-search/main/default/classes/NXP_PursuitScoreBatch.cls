/** Writes Likely to Pursue on open notices with the active model: all of them, or only those not scored yet. */
public with sharing class NXP_PursuitScoreBatch implements Database.Batchable<SObject> {
    private final Boolean onlyNew;

    public NXP_PursuitScoreBatch(Boolean onlyNew) {
        this.onlyNew = onlyNew == true;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String q =
            'SELECT ' +
            NXP_PursuitModel.NOTICE_FIELDS +
            ' FROM NXP_Gov_Notice__c WHERE Status__c = \'Active\'' +
            (onlyNew ? ' AND Pursuit_Scored__c = NULL' : '');
        return Database.getQueryLocator(q, AccessLevel.SYSTEM_MODE);
    }

    public void execute(Database.BatchableContext bc, List<NXP_Gov_Notice__c> scope) {
        NXP_PursuitModel model = NXP_PursuitModel.active();
        if (model != null) {
            NXP_PursuitModel.apply(model, scope);
        }
    }

    public void finish(Database.BatchableContext bc) {
        return;
    }
}
