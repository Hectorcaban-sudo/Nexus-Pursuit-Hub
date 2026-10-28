/**
 * Scheduled Apex batch import channel. Iterates over page slots (scope size 1): each execute()
 * fetches one page with Apex callouts and hands it to the same NXP_IngestionService as the
 * standard pipeline. Database.Stateful carries the checkpoint between transactions, and the
 * Feed Run row stores it so a failed run can resume.
 *
 * Start with: Database.executeBatch(new NXP_FeedFetchBatch('SAM_Backfill', null), 1);
 */
public without sharing class NXP_FeedFetchBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
    private final String feedName;
    private Id runId;
    private Map<String, Object> checkpoint;
    private Boolean done = false;
    private Integer failures = 0;

    public NXP_FeedFetchBatch(String feedName, Id runId) {
        this.feedName = feedName;
        this.runId = runId;
    }

    public Iterable<Integer> start(Database.BatchableContext context) {
        if (runId == null) {
            runId = NXP_FeedRunService.start(feedName, NXP_FeedRunService.CH_BATCH, null).Id;
        }
        checkpoint = NXP_FeedRunService.checkpointOf(runId);
        List<Integer> slots = new List<Integer>();
        Integer maxPages = NXP_Settings.getInteger('Batch_Max_Pages', 200);
        for (Integer i = 0; i < maxPages; i++) {
            slots.add(i);
        }
        return slots;
    }

    public void execute(Database.BatchableContext context, List<Integer> scope) {
        if (done) {
            return;
        }
        try {
            NXP_Feed_Config__mdt config = NXP_ConnectorSupport.config(feedName);
            NXP_FeedConnector connector = NXP_ConnectorSupport.connectorFor(config);
            if (checkpoint == null) {
                checkpoint = connector.initialCheckpoint(NXP_FeedRunService.lastSuccess(feedName));
            }
            NXP_FeedPage page = connector.fetchPage(checkpoint);
            NXP_IngestionService.Result result = NXP_IngestionService.ingest(page.records);
            checkpoint = page.nextCheckpoint;
            NXP_FeedRunService.recordPage(runId, result, checkpoint);
            done = !page.hasMore;
        } catch (Exception e) {
            failures++;
            NXP_Logger.error('NXP_FeedFetchBatch', 'Page failed for ' + feedName, e, runId);
            // Stop after repeated failures; the stored checkpoint lets the next run resume here.
            if (failures >= 3) {
                done = true;
            }
        } finally {
            NXP_Logger.flush();
        }
    }

    public void finish(Database.BatchableContext context) {
        if (failures >= 3) {
            NXP_FeedRunService.fail(runId, 'Stopped after 3 failed pages; see NXP Logs.');
        } else {
            NXP_FeedRunService.finish(runId, 'Succeeded');
            NXP_FeedScheduler.afterRun(feedName);
        }
        NXP_Logger.flush();
    }
}
