// Removes the sample data so it can be loaded again (scripts/load-sample-data.ps1 -Reset / .sh --reset).
// Deletes: SAMPLE notices and their children, records they were pushed to, SAMPLE saved searches
// (matches go with them), the sample company profile and sample contract vehicles, and the sample
// agencies when nothing else uses them. Real feed data is not touched.
List<NXP_Gov_Notice__c> notices = [
    SELECT Id, Pushed_Record_Id__c
    FROM NXP_Gov_Notice__c
    WHERE Notice_Id__c LIKE 'SAMPLE-%'
];
Set<Id> noticeIds = new Map<Id, NXP_Gov_Notice__c>(notices).keySet();
List<Id> pushedTargets = new List<Id>();
for (NXP_Gov_Notice__c n : notices) {
    if (String.isNotBlank(n.Pushed_Record_Id__c)) {
        pushedTargets.add(Id.valueOf(n.Pushed_Record_Id__c));
    }
}

delete [SELECT Id FROM NXP_Push_Log__c WHERE Gov_Notice__c IN :noticeIds];
delete [SELECT Id FROM NXP_Search_Match__c WHERE Gov_Notice__c IN :noticeIds];
delete [SELECT Id FROM NXP_Follow__c WHERE Gov_Notice__c IN :noticeIds];
delete [SELECT Id FROM NXP_Notice_Version__c WHERE Gov_Notice__c IN :noticeIds];
delete [SELECT Id FROM NXP_Gov_Contact__c WHERE Gov_Notice__c IN :noticeIds];
delete notices;
// Records created by pushing sample notices (Opportunity by default). Errors are ignored so a
// record someone already deleted or changed does not stop the cleanup.
Database.delete(pushedTargets, false);

delete [SELECT Id FROM NXP_Saved_Search__c WHERE Name LIKE 'SAMPLE - %'];
// Results of earlier functional-test runs.
delete [SELECT Id FROM NXP_Log__c WHERE Source__c = 'NXP-SMOKE'];
delete [SELECT Id FROM NXP_Company_Profile__c WHERE Name = 'Our company (sample)'];
delete [SELECT Id FROM NXP_Contract_Vehicle__c WHERE Name LIKE '%(sample)'];

// Sample agencies: only those no remaining notice points to. Children first, then departments.
Set<String> agencyCodes = new Set<String>{ '070.7014', '070.7003', '097.2100', '036.3600' };
Set<String> departmentCodes = new Set<String>{ '070', '097', '036' };
Set<Id> inUse = new Set<Id>();
for (AggregateResult ar : [
    SELECT Agency__c a
    FROM NXP_Gov_Notice__c
    WHERE Agency__r.Agency_Code__c IN :agencyCodes OR Agency__r.Agency_Code__c IN :departmentCodes
    GROUP BY Agency__c
]) {
    inUse.add((Id) ar.get('a'));
}
List<NXP_Gov_Agency__c> agencies = [
    SELECT Id
    FROM NXP_Gov_Agency__c
    WHERE Agency_Code__c IN :agencyCodes AND Id NOT IN :inUse
];
Database.delete(agencies, false);
// Keep a department that still has other (feed-created) agencies under it.
for (AggregateResult ar : [
    SELECT Parent_Agency__c p
    FROM NXP_Gov_Agency__c
    WHERE Parent_Agency__r.Agency_Code__c IN :departmentCodes
    GROUP BY Parent_Agency__c
]) {
    inUse.add((Id) ar.get('p'));
}
List<NXP_Gov_Agency__c> departments = [
    SELECT Id
    FROM NXP_Gov_Agency__c
    WHERE Agency_Code__c IN :departmentCodes AND Id NOT IN :inUse
];
Database.delete(departments, false);

System.debug(
    'Deleted ' + notices.size() + ' SAMPLE notices and ' + pushedTargets.size() + ' pushed records (where possible).'
);
