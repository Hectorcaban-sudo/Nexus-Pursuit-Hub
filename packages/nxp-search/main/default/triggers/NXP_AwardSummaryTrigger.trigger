/**
 * New award summaries: alert users who watch the vendor that won them (NXP_WatchService).
 * Bypass with the NXP_Setting record Bypass_NXP_AwardSummaryTrigger = true.
 */
trigger NXP_AwardSummaryTrigger on NXP_Award_Summary__c(after insert) {
    if (!NXP_Settings.isBypassed('NXP_AwardSummaryTrigger')) {
        NXP_WatchService.awardsCreated(Trigger.new);
    }
}
