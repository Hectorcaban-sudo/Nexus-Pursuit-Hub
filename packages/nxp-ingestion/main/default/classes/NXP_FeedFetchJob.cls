/**
 * Standard pipeline: a Queueable chain that fetches one page per job and enqueues the next.
 * A Finalizer marks the run Failed if a job throws, so the next scheduled run resumes from the
 * stored checkpoint.
 */
public without sharing class NXP_FeedFetchJob implements Queueable, Database.AllowsCallouts {
    private final String feedName;
    private final Id runId;
    private final Integer pagesDone;

    public NXP_FeedFetchJob(String feedName, Id runId, Integer pagesDone) {
        this.feedName = feedName;
        this.runId = runId;
        this.pagesDone = pagesDone == null ? 0 : pagesDone;
    }

    public void execute(QueueableContext context) {
        System.attachFinalizer(new NXP_FeedFetchFinalizer(runId));
        NXP_Feed_Config__mdt config = NXP_ConnectorSupport.config(feedName);
        NXP_FeedConnector connector = NXP_ConnectorSupport.connectorFor(config);

        Map<String, Object> checkpoint = NXP_FeedRunService.checkpointOf(runId);
        if (checkpoint == null) {
            checkpoint = connector.initialCheckpoint(NXP_FeedRunService.lastSuccess(feedName));
        }
        NXP_FeedPage page = connector.fetchPage(checkpoint);
        NXP_IngestionService.Result result = NXP_IngestionService.ingest(page.records);
        NXP_FeedRunService.recordPage(runId, result, page.nextCheckpoint);

        Integer maxPages = NXP_Settings.getInteger('Queue_Max_Pages', 50);
        if (page.hasMore && pagesDone + 1 < maxPages && !Test.isRunningTest()) {
            System.enqueueJob(new NXP_FeedFetchJob(feedName, runId, pagesDone + 1));
        } else {
            NXP_FeedRunService.finish(runId, 'Succeeded');
            NXP_FeedScheduler.afterRun(feedName);
        }
        NXP_Logger.flush();
    }
}
