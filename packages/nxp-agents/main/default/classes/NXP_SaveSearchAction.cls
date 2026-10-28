/**
 * Agent action: saves a search after the user has seen the preview and said yes.
 * Requires the preview token from NXP Preview Search for exactly these criteria.
 */
public with sharing class NXP_SaveSearchAction {
    public class Request {
        @InvocableVariable(label='Search name' required=true)
        public String name;
        @InvocableVariable(label='Criteria JSON' required=true)
        public String criteriaJson;
        @InvocableVariable(label='Alert frequency' description='Real Time, Daily, Weekly or None (default Daily)')
        public String frequency;
        @InvocableVariable(
            label='Preview token'
            description='From NXP Preview Search for the same criteria'
            required=true
        )
        public String previewToken;
    }

    public class Response {
        @InvocableVariable(label='Saved search Id')
        public Id searchId;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='NXP Save Search'
        description='Saves the previewed search. Only call after showing the preview and getting an explicit yes.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            NXP_SearchCriteria c = NXP_SearchCriteria.parse(r.criteriaJson);
            if (!NXP_PreviewToken.verify('search', c.toJson(), r.previewToken)) {
                res.message = 'Not saved: run NXP Preview Search on these exact criteria and confirm with the user first.';
                out.add(res);
                continue;
            }
            try {
                NXP_SearchController.SearchInput input = new NXP_SearchController.SearchInput();
                input.name = r.name;
                input.criteriaJson = r.criteriaJson;
                input.frequency = String.isBlank(r.frequency) ? 'Daily' : r.frequency;
                res.searchId = NXP_SearchController.save(input);
                res.message = 'Saved "' + r.name + '" with ' + input.frequency.toLowerCase() + ' alerts.';
            } catch (Exception e) {
                res.message = 'Not saved: ' + e.getMessage();
            }
            out.add(res);
        }
        return out;
    }
}
