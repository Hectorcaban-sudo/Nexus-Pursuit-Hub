/**
 * Agent action: saves a search after the user has seen the preview and said yes.
 * Requires the preview token from NXP Preview Search for exactly these criteria.
 */
public with sharing class NXP_SaveSearchAction {
    public class Request {
        @InvocableVariable(
            label='Search name'
            description='Short name for the search. Use the name the user gave. If they gave none, suggest one based on the summary and confirm it with them.'
            required=true
        )
        public String name;
        @InvocableVariable(
            label='Criteria JSON'
            description='The same Criteria JSON that was passed to NXP Preview Search, unchanged.'
            required=true
        )
        public String criteriaJson;
        @InvocableVariable(
            label='Alert frequency'
            description='Real Time, Daily, Weekly or None. Use the user\'s choice; if they did not choose, leave it empty for Daily.'
        )
        public String frequency;
        @InvocableVariable(
            label='Preview token'
            description='The Preview token output of NXP Preview Search for these same criteria, from this conversation. Never make one up.'
            required=true
        )
        public String previewToken;
    }

    public class Response {
        @InvocableVariable(
            label='Saved search Id'
            description='Id of the new saved search. Do not show it. Keep it in case the user then asks to turn on auto-push for this search.'
        )
        public Id searchId;
        @InvocableVariable(
            label='Message'
            description='What happened, including the reason if the save was refused. Tell the user.'
        )
        public String message;
    }

    @InvocableMethod(
        label='NXP Save Search'
        description='Use only after NXP Preview Search has been shown and the user has said yes to saving. Saves the previewed search as the user\'s own.'
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
