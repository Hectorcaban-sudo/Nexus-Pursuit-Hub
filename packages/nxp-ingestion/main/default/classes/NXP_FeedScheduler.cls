/**
 * Starts feed runs on the right channel and decides which feeds are due.
 * Also the Schedulable entry point: schedule once with NXP_FeedScheduler.scheduleHourly().
 */
public without sharing class NXP_FeedScheduler implements Schedulable {
    public static final String JOB_NAME = 'NXP Feed Scheduler';

    public void execute(SchedulableContext context) {
        runDueFeeds();
    }

    /** Schedules the dispatcher at minute 5 of every hour. */
    public static Id scheduleHourly() {
        return System.schedule(JOB_NAME, '0 5 * * * ?', new NXP_FeedScheduler());
    }

    public static List<String> runDueFeeds() {
        List<String> started = new List<String>();
        for (NXP_Feed_Config__mdt config : NXP_Feed_Config__mdt.getAll().values()) {
            if (!config.Active__c || !isDue(config) || NXP_FeedRunService.isRunning(config.DeveloperName)) {
                continue;
            }
            try {
                start(config);
                started.add(config.DeveloperName);
            } catch (Exception e) {
                NXP_Logger.error('NXP_FeedScheduler', 'Could not start ' + config.DeveloperName, e, null);
            }
        }
        NXP_Logger.flush();
        return started;
    }

    /** Starts one feed now, whatever its schedule. Returns the Feed Run Id. */
    public static Id runNow(String feedName) {
        NXP_Feed_Config__mdt config = NXP_ConnectorSupport.config(feedName);
        if (NXP_FeedRunService.isRunning(feedName)) {
            throw new IllegalArgumentException(feedName + ' is already running.');
        }
        return start(config);
    }

    private static Id start(NXP_Feed_Config__mdt config) {
        if (config.Channel__c == NXP_FeedRunService.CH_BATCH) {
            NXP_Feed_Run__c run = NXP_FeedRunService.start(config.DeveloperName, NXP_FeedRunService.CH_BATCH, null);
            Database.executeBatch(new NXP_FeedFetchBatch(config.DeveloperName, run.Id), 1);
            return run.Id;
        }
        NXP_Feed_Run__c run = NXP_FeedRunService.start(config.DeveloperName, NXP_FeedRunService.CH_PIPELINE, null);
        System.enqueueJob(new NXP_FeedFetchJob(config.DeveloperName, run.Id, 0));
        return run.Id;
    }

    @TestVisible
    private static Boolean isDue(NXP_Feed_Config__mdt config) {
        Datetime last = NXP_FeedRunService.lastStart(config.DeveloperName);
        Integer interval = config.Interval_Minutes__c == null ? 60 : config.Interval_Minutes__c.intValue();
        // Five minutes of slack so an hourly feed is not skipped by a run that started a little late.
        return last == null || last.addMinutes(interval - 5) <= Datetime.now();
    }

    /** Follow-up work after a feed finishes: fetch SAM.gov description text for new notices. */
    public static void afterRun(String feedName) {
        if (feedName.startsWith('SAM_') && feedName != 'SAM_Entity' && !Test.isRunningTest()) {
            try {
                Database.executeBatch(new NXP_NoticeEnrichBatch(), 20);
            } catch (Exception e) {
                NXP_Logger.warn('NXP_FeedScheduler', 'Could not start NXP_NoticeEnrichBatch: ' + e.getMessage());
            }
            try {
                NXP_SamFileJob.startIfNeeded();
            } catch (Exception e) {
                NXP_Logger.warn('NXP_FeedScheduler', 'Could not start NXP_SamFileJob: ' + e.getMessage());
            }
        }
    }
}
