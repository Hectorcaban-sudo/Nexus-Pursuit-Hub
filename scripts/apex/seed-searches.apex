// Creates four SAMPLE saved searches for the running user, then publishes a "New" change event for
// every SAMPLE notice so the real matching path runs (event -> NXP_GovNoticeChangedTrigger ->
// NXP_SearchMatchService -> Search Matches + alerts). Safe to run again: searches are created once
// and matches are de-duplicated by Match Key.
// "SAMPLE - eBuy RFQs on our vehicles" has auto-push on (fit 60 or more): the sample eBuy RFQ
// (seed-ebuy-email.apex) is pushed to the push target (Opportunity by default) when it arrives.
// Run after the seed notices are loaded (scripts/load-sample-data.ps1 or .sh does both).
Map<String, Map<String, Object>> samples = new Map<String, Map<String, Object>>{
    'SAMPLE - DHS cyber, small business' => new Map<String, Object>{
        'criteria' => '{"agencies":["Homeland Security"],"naics":["5415*"],"setAsides":["Small Business"]}',
        'frequency' => 'Real Time',
        'channels' => 'Salesforce'
    },
    'SAMPLE - Army 8(a)' => new Map<String, Object>{
        'criteria' => '{"agencies":["Army"],"setAsides":["8(a)"]}',
        'frequency' => 'Daily',
        'channels' => 'Email;Salesforce'
    },
    'SAMPLE - Zero trust keywords' => new Map<String, Object>{
        'criteria' => '{"keywords":"\\"zero trust\\" OR segmentation"}',
        'frequency' => 'Weekly',
        'channels' => 'Email'
    },
    'SAMPLE - eBuy RFQs on our vehicles' => new Map<String, Object>{
        'criteria' => '{"noticeTypes":["Task Order"],"vehicles":["GSA-MAS-IT","OASIS+"]}',
        'frequency' => 'Real Time',
        'channels' => 'Salesforce',
        'autoPush' => 'Fit Threshold',
        'autoPushMinFit' => 60
    }
};

Set<String> existing = new Set<String>();
for (NXP_Saved_Search__c s : [
    SELECT Name
    FROM NXP_Saved_Search__c
    WHERE Name IN :samples.keySet() AND OwnerId = :UserInfo.getUserId()
]) {
    existing.add(s.Name);
}

List<NXP_Saved_Search__c> toInsert = new List<NXP_Saved_Search__c>();
for (String name : samples.keySet()) {
    if (existing.contains(name)) {
        continue;
    }
    Map<String, Object> cfg = samples.get(name);
    toInsert.add(
        new NXP_Saved_Search__c(
            Name = name,
            Criteria_JSON__c = (String) cfg.get('criteria'),
            Alert_Frequency__c = (String) cfg.get('frequency'),
            Channels__c = (String) cfg.get('channels'),
            Visibility__c = 'Private',
            Alert_On_Changes__c = true,
            Auto_Push__c = cfg.containsKey('autoPush') ? (String) cfg.get('autoPush') : 'Off',
            Auto_Push_Min_Fit__c = (Integer) cfg.get('autoPushMinFit'),
            Active__c = true,
            Description__c = '[SAMPLE DATA] Created by scripts/apex/seed-searches.apex'
        )
    );
}
insert toInsert;
System.debug('Saved searches created: ' + toInsert.size() + ' (already there: ' + existing.size() + ')');

List<NXP_Gov_Notice_Changed__e> events = new List<NXP_Gov_Notice_Changed__e>();
for (NXP_Gov_Notice__c n : [SELECT Id FROM NXP_Gov_Notice__c WHERE Notice_Id__c LIKE 'SAMPLE-%']) {
    events.add(
        new NXP_Gov_Notice_Changed__e(
            Notice_Record_Id__c = n.Id,
            Change_Type__c = 'New',
            Is_New__c = true,
            Source_Feed__c = 'SAMPLE'
        )
    );
}
EventBus.publish(events);
System.debug('Change events published for ' + events.size() + ' SAMPLE notices. Matching runs in the background.');
