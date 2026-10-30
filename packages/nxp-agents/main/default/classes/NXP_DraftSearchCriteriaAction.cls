/**
 * Agent action (Search Builder subagent): turns the user's words into draft search criteria.
 * Uses the NXP_Search_Criteria_Draft prompt template when AI is enabled; otherwise the
 * deterministic NXP_CriteriaDraftService. Nothing is saved.
 */
public with sharing class NXP_DraftSearchCriteriaAction {
    public class Request {
        @InvocableVariable(
            label='Request text'
            description='The user\'s own words describing what they want alerts about: agencies, NAICS codes, set-asides, keywords, value, due dates and how often. Pass them unchanged; do not summarize.'
            required=true
        )
        public String text;
    }

    public class Response {
        @InvocableVariable(
            label='Criteria JSON'
            description='Machine-readable draft criteria. Do not show it to the user. Pass it unchanged to NXP Preview Search and then to NXP Save Search.'
        )
        public String criteriaJson;
        @InvocableVariable(
            label='Alert frequency'
            description='Real Time, Daily or Weekly when the user asked for one; empty otherwise. Pass it to NXP Save Search.'
        )
        public String frequency;
        @InvocableVariable(
            label='Summary'
            description='Readable summary of the draft criteria. Show it so the user can correct anything before the preview.'
        )
        public String summary;
    }

    @InvocableMethod(
        label='NXP Draft Search Criteria'
        description='Use first whenever the user describes a search or alert they want, or asks to change one. Turns their words into draft criteria. Saves nothing.'
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
