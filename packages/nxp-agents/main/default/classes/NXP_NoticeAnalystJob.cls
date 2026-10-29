/**
 * Background "agents" for Government Cloud, run as prompt templates from batch Apex:
 *   SUMMARIES - Notice Analyst: AI summary for notices that matched a saved search
 *               (AI_Summary_Status__c = Pending, set by NXP_SearchMatchService)
 *   CHANGES   - Amendment Watch: plain-English impact summary for new Notice Versions
 * Schedule once with NXP_NoticeAnalystJob.scheduleDefaults(); each run does summaries, then changes.
 */
public without sharing class NXP_NoticeAnalystJob implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    public static final String SUMMARIES = 'SUMMARIES';
    public static final String CHANGES = 'CHANGES';

    private final String mode;

    public NXP_NoticeAnalystJob() {
        this(SUMMARIES);
    }

    public NXP_NoticeAnalystJob(String mode) {
        this.mode = mode == CHANGES ? CHANGES : SUMMARIES;
    }

    /** Runs at :15 and :45 every hour. Apex cron takes one minute value per job, so this is two jobs. */
    public static List<Id> scheduleDefaults() {
        return new List<Id>{
            System.schedule('NXP Notice Analyst :15', '0 15 * * * ?', new NXP_NoticeAnalystJob()),
            System.schedule('NXP Notice Analyst :45', '0 45 * * * ?', new NXP_NoticeAnalystJob())
        };
    }

    public void execute(SchedulableContext context) {
        if (NXP_AiService.isEnabled()) {
            Database.executeBatch(new NXP_NoticeAnalystJob(SUMMARIES), 5);
        }
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (mode == CHANGES) {
            return Database.getQueryLocator(
                [
                    SELECT Id, AI_Change_Summary__c
                    FROM NXP_Notice_Version__c
                    WHERE Version_Number__c > 1 AND CreatedDate = LAST_N_DAYS:7
                    ORDER BY CreatedDate DESC
                    LIMIT 2000
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM NXP_Gov_Notice__c
                WHERE AI_Summary_Status__c = 'Pending'
                ORDER BY LastModifiedDate DESC
                LIMIT 2000
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (mode == CHANGES) {
            summarizeChanges((List<NXP_Notice_Version__c>) scope);
        } else {
            summarizeNotices((List<NXP_Gov_Notice__c>) scope);
        }
        NXP_Logger.flush();
    }

    public void finish(Database.BatchableContext context) {
        if (mode == SUMMARIES && !Test.isRunningTest()) {
            Database.executeBatch(new NXP_NoticeAnalystJob(CHANGES), 5);
        }
    }

    private static void summarizeNotices(List<NXP_Gov_Notice__c> scope) {
        String template = NXP_Settings.getString('AI_Summary_Template', 'NXP_Solicitation_Summary');
        List<NXP_Gov_Notice__c> updates = new List<NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : scope) {
            try {
                String text = NXP_AiService.generate(template, new Map<String, Object>{ 'Input:Notice' => n.Id });
                updates.add(
                    new NXP_Gov_Notice__c(
                        Id = n.Id,
                        AI_Summary__c = NXP_Text.truncate(text, 32768),
                        AI_Summary_Status__c = 'Complete'
                    )
                );
            } catch (Exception e) {
                updates.add(new NXP_Gov_Notice__c(Id = n.Id, AI_Summary_Status__c = 'Failed'));
                NXP_Logger.warn('NXP_NoticeAnalystJob', 'Summary failed for ' + n.Id + ': ' + e.getMessage());
            }
        }
        NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
    }

    private static void summarizeChanges(List<NXP_Notice_Version__c> scope) {
        String template = NXP_Settings.getString('AI_Change_Template', 'NXP_Amendment_Impact');
        List<NXP_Notice_Version__c> updates = new List<NXP_Notice_Version__c>();
        for (NXP_Notice_Version__c v : scope) {
            // Long text fields can't be filtered in SOQL, so versions already summarized are skipped here.
            if (String.isNotBlank(v.AI_Change_Summary__c)) {
                continue;
            }
            try {
                String text = NXP_AiService.generate(template, new Map<String, Object>{ 'Input:Version' => v.Id });
                updates.add(
                    new NXP_Notice_Version__c(Id = v.Id, AI_Change_Summary__c = NXP_Text.truncate(text, 32768))
                );
            } catch (Exception e) {
                NXP_Logger.warn('NXP_NoticeAnalystJob', 'Change summary failed for ' + v.Id + ': ' + e.getMessage());
            }
        }
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    }
}
