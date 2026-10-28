/**
 * Calls a Prompt Builder template through the standard "generatePromptResponse" invocable action,
 * so the code compiles and deploys in orgs where Einstein generative AI is not yet enabled.
 * Every call passes through the Einstein Trust Layer. Switch on with NXP_Setting AI_Enabled = true.
 */
public without sharing class NXP_AiService {
    public class AiUnavailableException extends Exception {
    }

    @TestVisible
    private static Map<String, String> responsesForTest;

    public static Boolean isEnabled() {
        return NXP_Settings.getBoolean('AI_Enabled', false) || responsesForTest != null;
    }

    /**
     * @param templateName prompt template API name, e.g. NXP_Solicitation_Summary
     * @param inputs       template input name (e.g. 'Input:Notice') -> value (record Id or text)
     */
    public static String generate(String templateName, Map<String, Object> inputs) {
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
