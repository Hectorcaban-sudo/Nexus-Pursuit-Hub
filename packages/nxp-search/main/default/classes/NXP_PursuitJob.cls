/**
 * Hourly (minute 50): when Pursuit_Prediction_Enabled is on, retrains the Likely to Pursue model once a
 * day at 02:50 (it then scores all open notices) and otherwise scores new notices with the active model.
 */
public with sharing class NXP_PursuitJob implements Schedulable {
    public static final String JOB_NAME = 'NXP Pursuit Prediction';

    public void execute(SchedulableContext sc) {
        run(Datetime.now().hour());
    }

    @TestVisible
    private static Id run(Integer hour) {
        if (!NXP_Settings.getBoolean('Pursuit_Prediction_Enabled', false)) {
            return null;
        }
        Boolean hasModel = [SELECT COUNT() FROM NXP_Pursuit_Model__c WHERE Status__c = 'Active' WITH SYSTEM_MODE] > 0;
        if (hour == 2 || !hasModel && hour == 14) {
            return Database.executeBatch(new NXP_PursuitTrainBatch(), 2000);
        }
        return hasModel ? Database.executeBatch(new NXP_PursuitScoreBatch(true), 500) : null;
    }

    public static void scheduleDefaults() {
        System.schedule(JOB_NAME, '0 50 * * * ?', new NXP_PursuitJob());
    }
}
