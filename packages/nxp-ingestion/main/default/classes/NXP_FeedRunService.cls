/**
 * Creates and updates NXP_Feed_Run__c rows: one per feed run or REST call. Counts accumulate
 * page by page; the checkpoint lets a failed run resume from the last good page.
 */
public without sharing class NXP_FeedRunService {
    public static final String CH_PIPELINE = 'Standard Pipeline';
    public static final String CH_BATCH = 'Scheduled Batch';
    public static final String CH_REST = 'Apex REST';
    public static final String CH_MANUAL = 'Manual';

    public static NXP_Feed_Run__c start(String feedName, String channel, String caller) {
        NXP_Feed_Run__c run = new NXP_Feed_Run__c(
            Feed_Name__c = NXP_Text.truncate(feedName, 80),
            Channel__c = channel,
            Status__c = 'Running',
            Started__c = Datetime.now(),
            Caller__c = NXP_Text.truncate(String.isBlank(caller) ? UserInfo.getUserName() : caller, 120),
            Records_Read__c = 0,
            Records_Created__c = 0,
            Records_Updated__c = 0,
            Records_Rejected__c = 0
        );
        insert as system run;
        return run;
    }

    /** Adds one page's counts and stores where the next page starts. */
    public static void recordPage(Id runId, NXP_IngestionService.Result result, Map<String, Object> nextCheckpoint) {
        NXP_Feed_Run__c run = load(runId);
        run.Records_Read__c = nz(run.Records_Read__c) + result.read;
        run.Records_Created__c = nz(run.Records_Created__c) + result.created;
        run.Records_Updated__c = nz(run.Records_Updated__c) + result.updated;
        run.Records_Rejected__c = nz(run.Records_Rejected__c) + result.rejected;
        run.Checkpoint__c = nextCheckpoint == null
            ? run.Checkpoint__c
            : NXP_Text.truncate(JSON.serialize(nextCheckpoint), 32768);
        if (!result.errors.isEmpty()) {
            run.Error_Log__c = NXP_Text.truncate(
                (run.Error_Log__c == null ? '' : run.Error_Log__c + '\n') + String.join(result.errors, '\n'),
                131072
            );
        }
        update as system run;
    }

    public static void finish(Id runId, String status) {
        NXP_Feed_Run__c run = load(runId);
        if (status == 'Succeeded' && nz(run.Records_Rejected__c) > 0) {
            status = 'Partial';
        }
        run.Status__c = status;
        run.Finished__c = Datetime.now();
        update as system run;
    }

    public static void fail(Id runId, String message) {
        NXP_Feed_Run__c run = load(runId);
        run.Status__c = 'Failed';
        run.Finished__c = Datetime.now();
        run.Error_Log__c = NXP_Text.truncate(
            (run.Error_Log__c == null ? '' : run.Error_Log__c + '\n') + message,
            131072
        );
        update as system run;
    }

    /** Start time of the last run that finished without failing, used for incremental windows. */
    public static Datetime lastSuccess(String feedName) {
        List<NXP_Feed_Run__c> runs = [
            SELECT Started__c
            FROM NXP_Feed_Run__c
            WHERE Feed_Name__c = :feedName AND Status__c IN ('Succeeded', 'Partial')
            WITH SYSTEM_MODE
            ORDER BY Started__c DESC
            LIMIT 1
        ];
        return runs.isEmpty() ? null : runs[0].Started__c;
    }

    public static Datetime lastStart(String feedName) {
        List<NXP_Feed_Run__c> runs = [
            SELECT Started__c
            FROM NXP_Feed_Run__c
            WHERE Feed_Name__c = :feedName
            WITH SYSTEM_MODE
            ORDER BY Started__c DESC
            LIMIT 1
        ];
        return runs.isEmpty() ? null : runs[0].Started__c;
    }

    /** A run counts as active for up to six hours; after that it is treated as abandoned. */
    public static Boolean isRunning(String feedName) {
        Datetime cutoff = Datetime.now().addHours(-6);
        return ![
                SELECT Id
                FROM NXP_Feed_Run__c
                WHERE Feed_Name__c = :feedName AND Status__c IN ('Queued', 'Running') AND Started__c > :cutoff
                WITH SYSTEM_MODE
                LIMIT 1
            ]
            .isEmpty();
    }

    public static Map<String, Object> checkpointOf(Id runId) {
        NXP_Feed_Run__c run = load(runId);
        return String.isBlank(run.Checkpoint__c)
            ? null
            : (Map<String, Object>) JSON.deserializeUntyped(run.Checkpoint__c);
    }

    private static NXP_Feed_Run__c load(Id runId) {
        return [
            SELECT
                Id,
                Records_Read__c,
                Records_Created__c,
                Records_Updated__c,
                Records_Rejected__c,
                Checkpoint__c,
                Error_Log__c
            FROM NXP_Feed_Run__c
            WHERE Id = :runId
            WITH SYSTEM_MODE
        ];
    }

    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }
}
