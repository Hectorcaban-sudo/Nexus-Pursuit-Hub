/**
 * Agent action (Notice Briefing): explains a notice's fit score rule by rule.
 */
public with sharing class NXP_ExplainFitScoreAction {
    public class Request {
        @InvocableVariable(label='Gov Notice record Id' required=true)
        public Id noticeId;
    }

    public class Response {
        @InvocableVariable(label='Explanation')
        public String explanation;
    }

    @InvocableMethod(
        label='NXP Explain Fit Score'
        description='Explains how the fit score of a notice was calculated.'
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
