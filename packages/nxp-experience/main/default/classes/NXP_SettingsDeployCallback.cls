/**
 * Called when a Settings tab save (a custom metadata deployment) finishes: marks its
 * NXP_Setting_Change__c rows Saved or Failed, with the reason. The rows are found by the save key
 * NXP_SettingsController stored on them.
 */
public without sharing class NXP_SettingsDeployCallback implements Metadata.DeployCallback {
    /** The key the save stored on its NXP_Setting_Change__c rows. */
    private final String saveKey;

    public NXP_SettingsDeployCallback(String saveKey) {
        this.saveKey = saveKey;
    }

    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        String jobId = saveKey;
        Boolean ok = result != null && result.status == Metadata.DeployStatus.Succeeded;
        String detail = null;
        if (!ok && result != null) {
            List<String> problems = new List<String>();
            if (result.details != null && result.details.componentFailures != null) {
                for (Metadata.DeployMessage m : result.details.componentFailures) {
                    problems.add(m.fullName + ': ' + m.problem);
                }
            }
            if (String.isNotBlank(result.errorMessage)) {
                problems.add(result.errorMessage);
            }
            detail = problems.isEmpty()
                ? 'The deployment did not succeed (' + result.status + ').'
                : String.join(problems, '\n');
        }
        mark(jobId, ok, detail);
    }

    public static void mark(String jobId, Boolean ok, String detail) {
        if (String.isBlank(jobId)) {
            return;
        }
        List<NXP_Setting_Change__c> rows = [
            SELECT Id
            FROM NXP_Setting_Change__c
            WHERE Deploy_Id__c = :jobId AND Status__c = 'Pending'
        ];
        for (NXP_Setting_Change__c r : rows) {
            r.Status__c = ok ? 'Saved' : 'Failed';
            r.Detail__c = detail == null ? null : detail.left(32768);
        }
        Database.update(rows, false, AccessLevel.SYSTEM_MODE);
    }
}
