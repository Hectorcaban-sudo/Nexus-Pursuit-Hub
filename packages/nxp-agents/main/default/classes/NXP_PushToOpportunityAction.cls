/**
 * Agent action (Push subagent): pushes a notice to Opportunity. Refuses without the token from
 * NXP Preview Push, so the preview-and-confirm step cannot be skipped. In Agentforce Builder,
 * also turn on "Require user confirmation" for this action.
 */
public with sharing class NXP_PushToOpportunityAction {
    public class Request {
        @InvocableVariable(
            label='Gov Notice record Id'
            description='Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no page is open, ask the user to open it. Must be the notice that was previewed. Never guess.'
            required=true
        )
        public Id noticeId;
        @InvocableVariable(
            label='Preview token'
            description='The Preview token output of NXP Preview Push for this same notice, from this conversation. Never make one up.'
            required=true
        )
        public String previewToken;
    }

    public class Response {
        @InvocableVariable(label='Status' description='Success, Linked Existing or Failed.')
        public String status;
        @InvocableVariable(
            label='Opportunity record Id'
            description='Id of the Opportunity created or linked. Offer to open it.'
        )
        public Id recordId;
        @InvocableVariable(
            label='Message'
            description='What happened, including the reason if it failed. Tell the user.'
        )
        public String message;
    }

    @InvocableMethod(
        label='NXP Push To Opportunity'
        description='Use only after NXP Preview Push has been shown for this notice and the user has said yes. Creates the Opportunity, or links the existing one.'
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
