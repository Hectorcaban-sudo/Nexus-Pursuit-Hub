// Schedules every Nexus Pursuit Hub background job. Safe to run again: existing jobs are replaced.
// Run as a user with the NXP_Admin permission set (jobs run as the scheduling user).
Set<String> names = new Set<String>{ 'NXP Feed Scheduler', 'NXP Daily Digest', 'NXP Weekly Digest', 'NXP Notice Analyst', 'NXP Push Retry' };
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name IN :names]) {
    System.abortJob(ct.Id);
}
NXP_FeedScheduler.scheduleHourly();                                    // feeds, at minute 5 of every hour
NXP_DigestBatch.scheduleDefaults();                                    // daily 06:30, weekly Monday 06:30
NXP_NoticeAnalystJob.scheduleDefaults();                               // AI summaries at :15 and :45 (only when AI_Enabled)
System.schedule('NXP Push Retry', '0 20 * * * ?', new NXP_PushRetryJob()); // failed auto-pushes, hourly
System.debug('Nexus Pursuit Hub jobs scheduled.');
