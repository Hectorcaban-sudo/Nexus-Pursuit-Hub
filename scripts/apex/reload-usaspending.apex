// Reloads USAspending awards from a start date, so older awards get NAICS and PSC (added for
// Price-to-Win). Awards are updated by PIID; nothing is duplicated. Change YEARS if you compare
// more than 5 years (setting Price_Check_Lookback_Years). Runs as a batch, one page per transaction;
// watch it on the Feed Console. Run: sf apex run --file scripts/apex/reload-usaspending.apex --target-org <alias>
Integer YEARS = 5;
String feed = 'USAspending_Awards';
NXP_Feed_Run__c run = NXP_FeedRunService.start(feed, NXP_FeedRunService.CH_BATCH, 'reload-usaspending');
NXP_FeedRunService.recordPage(
    run.Id,
    new NXP_IngestionService.Result(),
    new Map<String, Object>{
        'from' => String.valueOf(Date.today().addYears(-YEARS)),
        'to' => String.valueOf(Date.today()),
        'page' => 1
    }
);
Database.executeBatch(new NXP_FeedFetchBatch(feed, run.Id), 1);
System.debug('USAspending reload started: ' + run.Id);
