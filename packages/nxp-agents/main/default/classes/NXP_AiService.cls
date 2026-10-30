/**
 * Calls a Prompt Builder template through the standard "generatePromptResponse" invocable action,
 * so the code compiles and deploys in orgs where Einstein generative AI is not yet enabled.
 * Every call passes through the Einstein Trust Layer. Switch on with NXP_Setting AI_Enabled = true.
 *
 * Daily limit: at most AI_Max_Calls_Per_Day calls (0 = no limit); after that generate() throws
 * AiLimitException and the background jobs leave their work for the next day. Calls are counted in
 * memory and saved to the NXP_AI_Usage__c custom setting by flushUsage(), which callers run after
 * their last call in the transaction (a save between calls would block the next callout).
 */
public without sharing class NXP_AiService {
    public virtual class AiUnavailableException extends Exception {
    }

    /** The daily AI_Max_Calls_Per_Day limit is used up. */
    public class AiLimitException extends AiUnavailableException {
    }

    @TestVisible
    private static Map<String, String> responsesForTest;

    /** Calls made in this transaction and not yet saved. */
    private static Integer unsavedCalls = 0;
    /** Today's saved count after flushUsage() in this transaction (the cached setting is stale then). */
    private static Integer savedToday;

    public static Integer maxCallsPerDay() {
        return NXP_Settings.getInteger('AI_Max_Calls_Per_Day', 500);
    }

    public static Integer callsToday() {
        Integer saved = savedToday;
        if (saved == null) {
            NXP_AI_Usage__c u = NXP_AI_Usage__c.getOrgDefaults();
            saved = u == null || u.Day__c != Date.today() || u.Calls__c == null ? 0 : u.Calls__c.intValue();
        }
        return saved + unsavedCalls;
    }

    public static Boolean limitReached() {
        Integer cap = maxCallsPerDay();
        return cap != null && cap > 0 && callsToday() >= cap;
    }

    /** Saves the calls made in this transaction to today's count. Run after the last AI call. */
    public static void flushUsage() {
        if (unsavedCalls == 0) {
            return;
        }
        Id org = UserInfo.getOrganizationId();
        List<NXP_AI_Usage__c> rows = [
            SELECT Id, Day__c, Calls__c
            FROM NXP_AI_Usage__c
            WHERE SetupOwnerId = :org
            LIMIT 1
            FOR UPDATE
        ];
        NXP_AI_Usage__c u = rows.isEmpty() ? new NXP_AI_Usage__c(SetupOwnerId = org) : rows[0];
        if (u.Day__c != Date.today() || u.Calls__c == null) {
            u.Day__c = Date.today();
            u.Calls__c = 0;
        }
        u.Calls__c += unsavedCalls;
        upsert u;
        savedToday = u.Calls__c.intValue();
        unsavedCalls = 0;
    }

    public static Boolean isEnabled() {
        return NXP_Settings.getBoolean('AI_Enabled', false) || responsesForTest != null;
    }

    /**
     * @param templateName prompt template API name, e.g. NXP_Solicitation_Summary
     * @param inputs       template input name (e.g. 'Input:Notice') -> value (record Id or text)
     */
    public static String generate(String templateName, Map<String, Object> inputs) {
        if (limitReached()) {
            throw new AiLimitException(
                'The daily AI limit of ' +
                    maxCallsPerDay() +
                    ' calls is used up (NXP_Setting AI_Max_Calls_Per_Day). AI work continues tomorrow.'
            );
        }
        unsavedCalls++;
        if (responsesForTest != null) {
            return responsesForTest.containsKey(templateName) ? responsesForTest.get(templateName) : 'Test response';
        }
        if (!isEnabled()) {
            throw new AiUnavailableException('AI is switched off (NXP_Setting AI_Enabled).');
        }
        Invocable.Action action = Invocable.Action.createCustomAction('generatePromptResponse', templateName);
        for (String key : inputs.keySet()) {
            Object value = inputs.get(key);
            // Record inputs are passed as an sObject carrying the record Id, as Flow does.
            if (value instanceof Id) {
                Id recordId = (Id) value;
                value = recordId.getSObjectType().newSObject(recordId);
            }
            action.setInvocationParameter(key, value);
        }
        List<Invocable.Action.Result> results = action.invoke();
        if (results.isEmpty() || !results[0].isSuccess()) {
            String error = results.isEmpty() ? 'No result' : String.valueOf(results[0].getErrors());
            throw new AiUnavailableException('Prompt template ' + templateName + ' failed: ' + error);
        }
        Object text = results[0].getOutputParameters().get('promptResponse');
        return text == null ? null : String.valueOf(text);
    }
}
