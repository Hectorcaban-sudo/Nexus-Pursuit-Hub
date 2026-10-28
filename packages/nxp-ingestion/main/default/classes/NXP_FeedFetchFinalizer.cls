/**
 * Marks a feed run Failed when a NXP_FeedFetchJob throws (callout error, limit, bad data).
 */
public without sharing class NXP_FeedFetchFinalizer implements Finalizer {
    private final Id runId;

    public NXP_FeedFetchFinalizer(Id runId) {
        this.runId = runId;
    }

    public void execute(FinalizerContext context) {
        if (context.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            Exception ex = context.getException();
            NXP_FeedRunService.fail(runId, ex == null ? 'Job failed' : ex.getTypeName() + ': ' + ex.getMessage());
            NXP_Logger.error('NXP_FeedFetchJob', 'Feed run ' + runId + ' failed', ex, runId);
            NXP_Logger.flush();
        }
    }
}
