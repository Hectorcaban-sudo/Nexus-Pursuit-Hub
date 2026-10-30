/**
 * Agent action: counts and lists current matches for draft criteria and returns the preview
 * token that Save Search requires.
 */
public with sharing class NXP_PreviewSearchAction {
    public class Request {
        @InvocableVariable(
            label='Criteria JSON'
            description='The Criteria JSON output of NXP Draft Search Criteria, unchanged. If the user wants a change, run NXP Draft Search Criteria again with the corrected request first.'
            required=true
        )
        public String criteriaJson;
    }

    public class Response {
        @InvocableVariable(label='Match count' description='Number of active notices that match now.')
        public Integer matchCount;
        @InvocableVariable(
            label='Matches last 13 weeks'
            description='Number of notices that would have matched over the last 13 weeks. Tells the user how busy the alert will be.'
        )
        public Integer backtestTotal;
        @InvocableVariable(
            label='Top matches'
            description='Up to five matching notices, one per line, each starting with its notice ID in brackets. Show them as a list and keep the IDs.'
        )
        public String topMatches;
        @InvocableVariable(label='Criteria summary' description='Readable summary of the criteria that were previewed.')
        public String summary;
        @InvocableVariable(
            label='Preview token'
            description='Proof the user saw this preview. Do not show it. Pass it to NXP Save Search. It works only for these criteria and this user, and expires at the end of the day.'
        )
        public String previewToken;
    }

    @InvocableMethod(
        label='NXP Preview Search'
        description='Use after NXP Draft Search Criteria and before any save. Shows how many notices match now, how many matched over the last 13 weeks, and the top five.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            NXP_SearchCriteria c = NXP_SearchCriteria.parse(r.criteriaJson);
            c.validate();
            NXP_SearchController.Preview p = NXP_SearchController.preview(c);
            Response res = new Response();
            res.matchCount = p.count;
            res.backtestTotal = p.backtestTotal;
            res.summary = p.description;
            res.previewToken = p.token;
            List<String> lines = new List<String>();
            for (Integer i = 0; i < Math.min(5, p.top.size()); i++) {
                NXP_Gov_Notice__c n = p.top[i];
                lines.add('[' + n.Notice_Id__c + '] ' + NXP_AlertService.summaryLine(n));
            }
            res.topMatches = lines.isEmpty() ? 'No active notices match right now.' : String.join(lines, '\n');
            out.add(res);
        }
        return out;
    }
}
