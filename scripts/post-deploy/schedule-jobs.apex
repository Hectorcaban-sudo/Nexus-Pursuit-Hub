// Schedules every Nexus Pursuit Hub background job. Safe to run again: existing jobs are replaced.
// Run as a user with the NXP_Admin permission set (jobs run as the scheduling user).
// Every NXP job name starts with 'NXP ' (including older names), so stop them all first.
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'NXP %']) {
    System.abortJob(ct.Id);
}
NXP_FeedScheduler.scheduleHourly();                                    // feeds, at minute 5 of every hour
NXP_DigestBatch.scheduleDefaults();                                    // daily 06:30, weekly Monday 06:30
NXP_NoticeAnalystJob.scheduleDefaults();                               // AI summaries at :15 and :45, two jobs (only when AI_Enabled)
System.schedule('NXP Push Retry', '0 20 * * * ?', new NXP_PushRetryJob()); // failed auto-pushes, hourly
System.debug('Nexus Pursuit Hub jobs scheduled.');
