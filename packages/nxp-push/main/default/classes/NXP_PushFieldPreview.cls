/**
 * One row of the push preview: target field, the value that will be sent, and how it stays in sync.
 */
public inherited sharing class NXP_PushFieldPreview {
    @AuraEnabled
    public String field;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public Boolean required;
    @AuraEnabled
    public String sync;

    public NXP_PushFieldPreview(String field, String label, String value, Boolean required, String sync) {
        this.field = field;
        this.label = label;
        this.value = value;
        this.required = required;
        this.sync = sync;
    }
}
