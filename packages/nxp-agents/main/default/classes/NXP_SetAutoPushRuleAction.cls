/**
 * Agent action (Push subagent): turns auto-push on or off for one of the user's saved searches.
 * Power Users only. In Agentforce Builder, turn on "Require user confirmation" for this action.
 */
public with sharing class NXP_SetAutoPushRuleAction {
    public class Request {
        @InvocableVariable(label='Saved search Id' required=true)
        public Id searchId;
        @InvocableVariable(label='Mode' description='Off, Fit Threshold or All Matches' required=true)
        public String mode;
        @InvocableVariable(label='Minimum fit score' description='Required for Fit Threshold')
        public Decimal minFit;
    }

    public class Response {
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='NXP Set Auto-Push Rule'
        description='Sets auto-push on a saved search the user owns. Power Users only; confirm with the user first.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            if (!FeatureManagement.checkPermission('NXP_Power_User')) {
                res.message = 'Auto-push needs the NXP Power User permission. Ask your Nexus Pursuit Hub admin.';
            } else if (r.mode != 'Off' && r.mode != 'Fit Threshold' && r.mode != 'All Matches') {
                res.message = 'Mode must be Off, Fit Threshold or All Matches.';
            } else if (r.mode == 'Fit Threshold' && r.minFit == null) {
                res.message = 'Give a minimum fit score for Fit Threshold.';
            } else {
                NXP_Saved_Search__c s = [
                    SELECT Id, Name, OwnerId
                    FROM NXP_Saved_Search__c
                    WHERE Id = :r.searchId
                    WITH USER_MODE
                ];
                if (s.OwnerId != UserInfo.getUserId()) {
                    res.message = 'You can only change auto-push on searches you own.';
                } else {
                    update as user new NXP_Saved_Search__c(
                        Id = s.Id,
                        Auto_Push__c = r.mode,
                        Auto_Push_Min_Fit__c = r.minFit
                    );
                    res.message =
                        'Auto-push on "' +
                        s.Name +
                        '" is now ' +
                        r.mode +
                        (r.mode == 'Fit Threshold' ? ' (fit ' + r.minFit + ' or higher).' : '.');
                }
            }
            out.add(res);
        }
        return out;
    }
}
