/**
 * Agent action: counts and lists current matches for draft criteria and returns the preview
 * token that Save Search requires.
 */
public with sharing class NXP_PreviewSearchAction {
    public class Request {
        @InvocableVariable(label='Criteria JSON' required=true)
        public String criteriaJson;
    }

    public class Response {
        @InvocableVariable(label='Match count')
        public Integer matchCount;
        @InvocableVariable(label='Matches last 13 weeks')
        public Integer backtestTotal;
        @InvocableVariable(label='Top matches' description='Up to five matches, one per line, with notice IDs')
        public String topMatches;
        @InvocableVariable(label='Criteria summary')
        public String summary;
        @InvocableVariable(label='Preview token' description='Pass to Save Search after the user confirms')
        public String previewToken;
    }

    @InvocableMethod(
        label='NXP Preview Search'
        description='Shows how many active notices match the criteria now and over the last 13 weeks, and the top five.'
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
