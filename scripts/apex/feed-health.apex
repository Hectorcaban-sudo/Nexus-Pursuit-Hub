// Prints the last run of every feed and any scheduled NXP jobs.
for (NXP_Feed_Run__c r : [SELECT Feed_Name__c, Status__c, Started__c, Records_Read__c, Records_Created__c, Records_Rejected__c
                          FROM NXP_Feed_Run__c ORDER BY Started__c DESC LIMIT 20]) {
    System.debug(r.Feed_Name__c + ' | ' + r.Status__c + ' | ' + r.Started__c + ' | read ' + r.Records_Read__c + ', new ' + r.Records_Created__c + ', rejected ' + r.Records_Rejected__c);
}
for (CronTrigger ct : [SELECT CronJobDetail.Name, NextFireTime, State FROM CronTrigger WHERE CronJobDetail.Name LIKE 'NXP %']) {
    System.debug('Job ' + ct.CronJobDetail.Name + ' next ' + ct.NextFireTime + ' ' + ct.State);
}
