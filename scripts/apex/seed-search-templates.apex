// Creates four org-wide search templates that everyone sees under "Start from a template" on
// My Searches. They are owned by the running user (run as an NXP_Admin user), never alert, match or
// auto-push themselves, and are shared read-only with all internal users. Safe to run again:
// templates are created once by name. Edit or delete them like any saved search.
Map<String, String> templates = new Map<String, String>{
    'High fit, due in 30 days' => '{"minFit":70,"dueWithinDays":30}',
    'eBuy RFQs (task orders by e-mail)' => '{"sources":["EMAIL_GSA_eBuy"],"noticeTypes":["Task Order"]}',
    'Early market research: sources sought and RFIs' => '{"noticeTypes":["Sources Sought","RFI"],"minFit":50}',
    'Small-business set-asides over $1M' => '{"setAsides":["Small Business","8(a)","HUBZone","Service-Disabled","Women-Owned"],"minValue":1000000}'
};

Set<String> existing = new Set<String>();
for (NXP_Saved_Search__c s : [
    SELECT Name
    FROM NXP_Saved_Search__c
    WHERE Name IN :templates.keySet() AND Visibility__c = 'Org Template'
]) {
    existing.add(s.Name);
}

List<NXP_Saved_Search__c> toInsert = new List<NXP_Saved_Search__c>();
for (String name : templates.keySet()) {
    if (existing.contains(name)) {
        continue;
    }
    NXP_SearchCriteria c = NXP_SearchCriteria.parse(templates.get(name));
    c.validate();
    toInsert.add(
        new NXP_Saved_Search__c(
            Name = name,
            Criteria_JSON__c = c.toJson(),
            Description__c = c.describe().left(255),
            Visibility__c = 'Org Template',
            Alert_Frequency__c = 'None',
            Channels__c = 'Salesforce',
            Alert_On_Changes__c = false,
            Auto_Push__c = 'Off',
            Active__c = false
        )
    );
}
insert toInsert;
NXP_SearchSharingService.apply(toInsert);
System.debug('Search templates created: ' + toInsert.size() + ' (already there: ' + existing.size() + ')');
