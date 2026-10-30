/**
 * Document Reader: reads PDF files attached to Gov Notices with the NXP_Document_Analysis prompt
 * template (Document_Analysis_Template setting) and stores the checked result on the
 * NXP_Document_Analysis__c row. One file per execution, then the job queues itself for the next,
 * so each AI call has the whole callout time budget. Started by NXP_DocumentService when a file is
 * attached or Analyze is clicked, and by the Notice Analyst run for rows still Pending.
 * The model only returns field values (checked by NXP_DocumentAnalysisParser); it cannot act.
 * Background work across users' notices, so without sharing.
 */
public without sharing class NXP_DocumentAnalysisJob implements Queueable, Database.AllowsCallouts, NXP_DocumentAnalyzer {
    private static final Integer SWEEP_SIZE = 20;

    private final List<Id> queue;

    /** Used by NXP_DocumentService (Type.forName) and by the Notice Analyst sweep. */
    public NXP_DocumentAnalysisJob() {
        this.queue = null;
    }

    public NXP_DocumentAnalysisJob(Set<Id> analysisIds) {
        this.queue = analysisIds == null ? null : new List<Id>(analysisIds);
    }

    public Boolean isEnabled() {
        return NXP_AiService.isEnabled() && NXP_Settings.getBoolean('Document_Analysis_Enabled', false);
    }

    public void enqueue(Set<Id> analysisIds) {
        System.enqueueJob(new NXP_DocumentAnalysisJob(analysisIds));
    }

    /** Pending rows that were registered automatically (not the ones waiting for Analyze). */
    public static List<Id> pendingIds() {
        List<Id> ids = new List<Id>();
        for (NXP_Document_Analysis__c a : [
            SELECT Id
            FROM NXP_Document_Analysis__c
            WHERE Status__c = 'Pending' AND Status_Detail__c = NULL
            ORDER BY CreatedDate
            LIMIT :SWEEP_SIZE
        ]) {
            ids.add(a.Id);
        }
        return ids;
    }

    public void execute(QueueableContext context) {
        if (!isEnabled()) {
            return;
        }
        List<Id> todo = queue == null ? pendingIds() : queue;
        if (todo.isEmpty()) {
            return;
        }
        // Tests cannot chain Queueables, so they read every file in one run.
        Integer take = Test.isRunningTest() ? todo.size() : 1;
        for (Integer i = 0; i < take && i < todo.size(); i++) {
            analyze(todo[i]);
        }
        NXP_Logger.flush();
        if (todo.size() > take && !Test.isRunningTest() && !NXP_AiService.limitReached()) {
            List<Id> rest = new List<Id>();
            for (Integer i = take; i < todo.size(); i++) {
                rest.add(todo[i]);
            }
            System.enqueueJob(new NXP_DocumentAnalysisJob(new Set<Id>(rest)));
        }
    }

    @TestVisible
    private static void analyze(Id analysisId) {
        List<NXP_Document_Analysis__c> rows = [
            SELECT Id, Gov_Notice__c, Content_Document_Id__c, Status__c, File_Name__c
            FROM NXP_Document_Analysis__c
            WHERE Id = :analysisId
        ];
        if (rows.isEmpty() || rows[0].Status__c != 'Pending') {
            return;
        }
        NXP_Document_Analysis__c a = rows[0];
        try {
            NXP_Gov_Notice__c notice = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byId(a.Gov_Notice__c);
            String text = NXP_AiService.generate(
                NXP_Settings.getString('Document_Analysis_Template', 'NXP_Document_Analysis'),
                new Map<String, Object>{
                    'Input:Notice' => a.Gov_Notice__c,
                    'Input:Document' => Id.valueOf(a.Content_Document_Id__c)
                }
            );
            Map<String, Object> result = NXP_DocumentAnalysisParser.parse(text, notice);
            a.Result_Json__c = NXP_Text.truncate(JSON.serializePretty(result), 32768);
            a.Status__c = 'Complete';
            a.Status_Detail__c = null;
        } catch (NXP_AiService.AiLimitException e) {
            // Daily limit used up: stays Pending and is picked up by a later sweep.
            NXP_Logger.warn('NXP_DocumentAnalysisJob', e.getMessage());
            return;
        } catch (Exception e) {
            a.Status__c = 'Failed';
            a.Status_Detail__c = NXP_Text.truncate(e.getMessage(), 255);
            NXP_Logger.warn('NXP_DocumentAnalysisJob', 'Could not read ' + a.File_Name__c + ': ' + e.getMessage());
        }
        a.Analyzed__c = Datetime.now();
        update a;
        NXP_AiService.flushUsage();
    }
}
