/**
 * Agent action (Push subagent): shows what a push would create and returns the token that
 * NXP Push To TechnoMile requires.
 */
public with sharing class NXP_PreviewPushAction {
    public class Request {
        @InvocableVariable(label='Gov Notice record Id' required=true)
        public Id noticeId;
    }

    public class Response {
        @InvocableVariable(label='Preview' description='Mapped values and duplicate check, to show the user')
        public String preview;
        @InvocableVariable(label='Preview token')
        public String previewToken;
        @InvocableVariable(
            label='Existing record Id'
            description='Set when a matching TechnoMile record already exists'
        )
        public Id existingRecordId;
    }

    @InvocableMethod(
        label='NXP Preview Push'
        description='Shows the values a push to TechnoMile would send and checks for an existing record.'
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
