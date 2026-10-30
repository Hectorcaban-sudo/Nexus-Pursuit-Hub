/**
 * Agent action (Push subagent): latest push attempts for a notice.
 */
public with sharing class NXP_PushStatusAction {
    public class Request {
        @InvocableVariable(
            label='Gov Notice record Id'
            description='Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id.'
            required=true
        )
        public Id noticeId;
    }

    public class Response {
        @InvocableVariable(
            label='Status'
            description='Up to the five most recent pushes of the notice, newest first: time, how it was pushed, result, record and any error. Or a note that it was never pushed.'
        )
        public String status;
    }

    @InvocableMethod(
        label='NXP Push Status'
        description='Use when the user asks whether a notice was pushed, whether a push failed, or why.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            List<String> lines = new List<String>();
            for (NXP_Push_Log__c l : NXP_PushController.getPushLogs(r.noticeId)) {
                lines.add(
                    l.CreatedDate.format('MMM d h:mm a') +
                        ' · ' +
                        l.Mode__c +
                        ' · ' +
                        l.Status__c +
                        (l.Target_Record_Id__c == null ? '' : ' · record ' + l.Target_Record_Id__c) +
                        (String.isBlank(l.Error__c) ? '' : ' · ' + NXP_Text.truncate(l.Error__c, 200))
                );
                if (lines.size() == 5) {
                    break;
                }
            }
            Response res = new Response();
            res.status = lines.isEmpty() ? 'This notice has not been pushed.' : String.join(lines, '\n');
            out.add(res);
        }
        return out;
    }
}
