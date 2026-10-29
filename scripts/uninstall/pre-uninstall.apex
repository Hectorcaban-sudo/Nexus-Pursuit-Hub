// Run by scripts/uninstall.sh and scripts/uninstall.ps1 before any metadata is removed.
// Scheduled jobs, queued jobs and permission set assignments all block deleting the Apex classes and
// permission sets, so this stops the NXP jobs and removes the NXP permission set assignments.
// Records are not deleted here: they go with their objects in the next step.
Integer scheduled = 0;
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'NXP %']) {
    System.abortJob(ct.Id);
    scheduled++;
}
Integer queued = 0;
for (AsyncApexJob j : [
    SELECT Id
    FROM AsyncApexJob
    WHERE Status IN ('Queued', 'Preparing', 'Holding') AND ApexClass.Name LIKE 'NXP%'
]) {
    System.abortJob(j.Id);
    queued++;
}
List<PermissionSetAssignment> assignments = [
    SELECT Id
    FROM PermissionSetAssignment
    WHERE PermissionSet.Name IN ('NXP_User', 'NXP_Power_User', 'NXP_Admin', 'NXP_Integration')
];
delete assignments;
System.debug(
    'Stopped ' + scheduled + ' scheduled and ' + queued + ' queued jobs; removed ' +
    assignments.size() + ' permission set assignments.'
);
