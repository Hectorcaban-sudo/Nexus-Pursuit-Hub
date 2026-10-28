/**
 * Agent action (Search Builder subagent): turns the user's words into draft search criteria.
 * Uses the NXP_Search_Criteria_Draft prompt template when AI is enabled; otherwise the
 * deterministic NXP_CriteriaDraftService. Nothing is saved.
 */
public with sharing class NXP_DraftSearchCriteriaAction {
    public class Request {
        @InvocableVariable(
            label='Request text'
            description='What the user wants to be alerted about, in their words'
            required=true
        )
        public String text;
    }

    public class Response {
        @InvocableVariable(label='Criteria JSON' description='Draft criteria to pass to Preview Search')
        public String criteriaJson;
        @InvocableVariable(label='Alert frequency' description='Real Time, Daily or Weekly when the user said so')
        public String frequency;
        @InvocableVariable(label='Summary' description='Readable summary of the criteria to show the user')
        public String summary;
    }

    @InvocableMethod(
        label='NXP Draft Search Criteria'
        description='Turns a plain-English request into draft saved-search criteria. Does not save anything.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            NXP_CriteriaDraftService.Draft d = NXP_CriteriaDraftService.draft(r.text);
            Response res = new Response();
            res.criteriaJson = d.criteriaJson;
            res.frequency = d.frequency;
            res.summary = d.summary;
            if (NXP_AiService.isEnabled()) {
                try {
                    String ai = NXP_AiService.generate(
                        'NXP_Search_Criteria_Draft',
                        new Map<String, Object>{ 'Input:Request' => r.text }
                    );
                    // The template returns JSON, sometimes wrapped in a ```json fence.
                    String body = ai.contains('```')
                        ? ai.substringAfter('```').removeStartIgnoreCase('json').substringBefore('```')
                        : ai;
                    NXP_SearchCriteria c = NXP_SearchCriteria.parse(body.trim());
                    c.validate();
                    res.criteriaJson = c.toJson();
                    res.summary = c.describe() + (d.frequency == null ? '' : '; alerts: ' + d.frequency);
                } catch (Exception e) {
                    // Keep the deterministic draft.
                }
            }
            out.add(res);
        }
        return out;
    }
}
