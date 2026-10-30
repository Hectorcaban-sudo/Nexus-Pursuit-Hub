/**
 * Called when a Settings tab save (a custom metadata deployment) finishes: marks its
 * NXP_Setting_Change__c rows Saved or Failed, with the reason.
 */
public without sharing class NXP_SettingsDeployCallback implements Metadata.DeployCallback {
    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        // The save stored the id enqueueDeployment returned, which is the deployment's id.
        String jobId = result != null && String.isNotBlank(result.id)
            ? result.id
            : context == null ? null : context.getCallbackJobId();
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

    @TestVisible
    private static void mark(String jobId, Boolean ok, String detail) {
        if (String.isBlank(jobId)) {
            return;
        }
        // Ids can come back as 15 or 18 characters.
        Set<String> ids = new Set<String>{ jobId, jobId.left(15) };
        String prefix = jobId.left(15) + '%';
        List<NXP_Setting_Change__c> rows = [
            SELECT Id
            FROM NXP_Setting_Change__c
            WHERE (Deploy_Id__c IN :ids OR Deploy_Id__c LIKE :prefix) AND Status__c = 'Pending'
        ];
        for (NXP_Setting_Change__c r : rows) {
            r.Status__c = ok ? 'Saved' : 'Failed';
            r.Detail__c = detail == null ? null : detail.left(32768);
        }
        Database.update(rows, false, AccessLevel.SYSTEM_MODE);
    }
}
