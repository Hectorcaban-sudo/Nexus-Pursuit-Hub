/**
 * Agent action (Push subagent): latest push attempts for a notice.
 */
public with sharing class NXP_PushStatusAction {
    public class Request {
        @InvocableVariable(label='Gov Notice record Id' required=true)
        public Id noticeId;
    }

    public class Response {
        @InvocableVariable(label='Status')
        public String status;
    }

    @InvocableMethod(
        label='NXP Push Status'
        description='Shows whether a notice was pushed to TechnoMile and any errors.'
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
