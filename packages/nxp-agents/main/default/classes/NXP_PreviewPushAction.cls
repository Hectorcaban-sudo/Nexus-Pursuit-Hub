/**
 * Agent action (Push subagent): shows what a push would create and returns the token that
 * NXP Push To Opportunity requires.
 */
public with sharing class NXP_PreviewPushAction {
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
            label='Preview'
            description='The values that will be sent to Opportunity and whether a matching record already exists. Show it in full before asking for a yes.'
        )
        public String preview;
        @InvocableVariable(
            label='Preview token'
            description='Proof the user saw this preview. Do not show it. Pass it to NXP Push To Opportunity for this same notice.'
        )
        public String previewToken;
        @InvocableVariable(
            label='Existing record Id'
            description='Set when a matching Opportunity already exists. The push will link to it instead of creating a new one; tell the user that.'
        )
        public Id existingRecordId;
    }

    @InvocableMethod(
        label='NXP Preview Push'
        description='Use first whenever the user wants to send a notice to Opportunity. Shows the values that would be sent and whether a matching Opportunity already exists. Sends nothing.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            try {
                NXP_PushService.PushPreview p = NXP_PushService.preview(r.noticeId);
                List<String> lines = new List<String>{ 'Push "' + p.noticeTitle + '" to ' + p.targetObject + ':' };
                for (NXP_PushFieldPreview f : p.fields) {
                    lines.add(
                        '- ' +
                            f.label +
                            ': ' +
                            (String.isBlank(f.value) ? '(blank)' : f.value) +
                            ' [sync: ' +
                            f.sync +
                            ']'
                    );
                }
                if (p.alreadyPushed) {
                    lines.add('Already pushed: record ' + p.existingRecordId + '.');
                } else if (p.existingRecordId != null) {
                    lines.add(
                        'A matching record exists (' +
                            p.existingRecordName +
                            '); pushing will link to it instead of creating a duplicate.'
                    );
                } else {
                    lines.add('No existing record found; a new one will be created.');
                }
                res.preview = String.join(lines, '\n');
                res.previewToken = p.token;
                res.existingRecordId = p.existingRecordId;
            } catch (Exception e) {
                res.preview = 'Cannot preview: ' + e.getMessage();
            }
            out.add(res);
        }
        return out;
    }
}
