// Stops every Nexus Pursuit Hub scheduled job (use before a risky deployment or to pause all feeds).
for (CronTrigger ct : [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'NXP %']) {
    System.abortJob(ct.Id);
    System.debug('Stopped ' + ct.CronJobDetail.Name);
}
