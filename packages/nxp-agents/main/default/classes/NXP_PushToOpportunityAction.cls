/**
 * Agent action (Push subagent): pushes a notice to Opportunity. Refuses without the token from
 * NXP Preview Push, so the preview-and-confirm step cannot be skipped. In Agentforce Builder,
 * also turn on "Require user confirmation" for this action.
 */
public with sharing class NXP_PushToOpportunityAction {
    public class Request {
        @InvocableVariable(label='Gov Notice record Id' required=true)
        public Id noticeId;
        @InvocableVariable(label='Preview token' description='From NXP Preview Push for this notice' required=true)
        public String previewToken;
    }

    public class Response {
        @InvocableVariable(label='Status' description='Success, Linked Existing or Failed')
        public String status;
        @InvocableVariable(label='Opportunity record Id')
        public Id recordId;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='NXP Push To Opportunity'
        description='Creates or links the Opportunity record for a notice. Only after Preview Push and an explicit yes.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            NXP_PushService.PushResult result = NXP_PushService.pushWithToken(r.noticeId, r.previewToken, null);
            Response res = new Response();
            res.status = result.status;
            res.recordId = result.targetId;
            res.message = result.message;
            out.add(res);
        }
        return out;
    }
}
