/**
 * Agent action (Opportunity analysis): a bid / no-bid brief, opportunity SWOT, incumbent and
 * competitors, requirement gaps, win themes or teaming partners for one notice. Same analysis as
 * Analyze this notice on the notice page: facts from Nexus data with their sources, plus one AI call.
 */
public with sharing class NXP_AnalyzeNoticeAction {
    public class Request {
        @InvocableVariable(
            label='Gov Notice record Id'
            description='Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id.'
            required=true
        )
        public Id noticeId;
        @InvocableVariable(
            label='Analysis type'
            description='brief (bid or no-bid), swot, competitors (incumbent, likely bidders), gaps (requirements we may not meet), themes (win themes) or teaming. Pick the closest to the question; brief when unsure.'
            required=true
        )
        public String analysisType;
    }

    public class Response {
        @InvocableVariable(
            label='Analysis'
            description='Markdown analysis: each item ends with its sources in [ ] or (assumption). Show it as it is with the tags; say (assumption) items need checking. Add no vendors, dates or amounts that are not in it.'
        )
        public String analysis;
        @InvocableVariable(
            label='Note'
            description='Why there is no AI part (AI off or the daily limit used up), or empty. Tell the user when it is not empty.'
        )
        public String note;
    }

    @InvocableMethod(
        label='NXP Analyze Notice'
        description='Use when the user asks whether to bid, for a SWOT, who the incumbent and competitors are, which requirements we may not meet, win themes or teaming partners for the notice they have open.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            String kind = String.isBlank(r.analysisType) ? 'brief' : r.analysisType.trim().toLowerCase();
            if (!NXP_NoticeAnalysisService.isKind(kind)) {
                kind = 'brief';
            }
            try {
                NXP_NoticeAnalysisService.Analysis a = NXP_NoticeAnalysisService.analyze(r.noticeId, kind);
                res.analysis = NXP_NoticeAnalysisService.toText(
                    a,
                    new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(r.noticeId)
                );
                res.note = a.note;
            } catch (Exception e) {
                res.analysis = 'The analysis could not be written: ' + e.getMessage();
            }
            out.add(res);
        }
        return out;
    }
}
