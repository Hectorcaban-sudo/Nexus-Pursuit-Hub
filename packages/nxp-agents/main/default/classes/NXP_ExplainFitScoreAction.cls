/**
 * Agent action (Notice Briefing): explains a notice's fit score rule by rule.
 */
public with sharing class NXP_ExplainFitScoreAction {
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
            label='Explanation'
            description='The score and the points each rule added, starting with the notice ID. Show it as given; do not recalculate or round.'
        )
        public String explanation;
    }

    @InvocableMethod(
        label='NXP Explain Fit Score'
        description='Use when the user asks why a notice has its fit score, or what is helping or hurting the score.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        NXP_GovNoticeSelector selector = new NXP_GovNoticeSelector(AccessLevel.USER_MODE);
        for (Request r : requests) {
            Response res = new Response();
            NXP_Gov_Notice__c n = selector.byId(r.noticeId);
            res.explanation = n == null
                ? 'Notice not found or not visible to you.'
                : '[' + n.Notice_Id__c + '] ' + NXP_FitScoreService.explain(n);
            out.add(res);
        }
        return out;
    }
}
