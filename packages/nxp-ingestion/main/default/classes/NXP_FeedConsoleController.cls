/**
 * Data for the admin Feed Console (nxpFeedConsole LWC).
 */
public with sharing class NXP_FeedConsoleController {
    public class FeedTile {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public Integer intervalMinutes;
        @AuraEnabled
        public NXP_Feed_Run__c lastRun;
        @AuraEnabled
        public String health;
    }

    public class Console {
        @AuraEnabled
        public List<FeedTile> feeds = new List<FeedTile>();
        @AuraEnabled
        public List<NXP_Feed_Run__c> runs = new List<NXP_Feed_Run__c>();
        @AuraEnabled
        public Boolean canRun;
        @AuraEnabled
        public Boolean schedulerActive;
    }

    @AuraEnabled
    public static Console getConsole() {
        Console c = new Console();
        c.canRun = FeatureManagement.checkPermission('NXP_Admin_Access');
        c.schedulerActive = ![SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :NXP_FeedScheduler.JOB_NAME LIMIT 1]
            .isEmpty();
        c.runs = [
            SELECT
                Id,
                Name,
                Feed_Name__c,
                Channel__c,
                Status__c,
                Started__c,
                Finished__c,
                Records_Read__c,
                Records_Created__c,
                Records_Updated__c,
                Records_Rejected__c,
                Caller__c
            FROM NXP_Feed_Run__c
            WITH USER_MODE
            ORDER BY Started__c DESC
            LIMIT 25
        ];
        Map<String, NXP_Feed_Run__c> latest = new Map<String, NXP_Feed_Run__c>();
        for (NXP_Feed_Run__c run : c.runs) {
            if (!latest.containsKey(run.Feed_Name__c)) {
                latest.put(run.Feed_Name__c, run);
            }
        }
        List<NXP_Feed_Config__mdt> configs = NXP_Feed_Config__mdt.getAll().values();
        for (NXP_Feed_Config__mdt cfg : configs) {
            FeedTile t = new FeedTile();
            t.name = cfg.DeveloperName;
            t.label = cfg.MasterLabel;
            t.channel = cfg.Channel__c;
            t.active = cfg.Active__c;
            t.intervalMinutes = cfg.Interval_Minutes__c == null ? null : cfg.Interval_Minutes__c.intValue();
            t.lastRun = latest.get(cfg.DeveloperName);
            t.health = health(t);
            c.feeds.add(t);
        }
        // REST sources have no config record; show them as tiles too.
        for (String feed : latest.keySet()) {
            if (feed.startsWith('REST_')) {
                FeedTile t = new FeedTile();
                t.name = feed;
                t.label = feed.removeStart('REST_') + ' (Apex REST)';
                t.channel = NXP_FeedRunService.CH_REST;
                t.active = true;
                t.lastRun = latest.get(feed);
                t.health = health(t);
                c.feeds.add(t);
            }
        }
        return c;
    }

    @AuraEnabled
    public static Id runNow(String feedName) {
        if (!FeatureManagement.checkPermission('NXP_Admin_Access')) {
            throw new AuraHandledException('You need the NXP Admin Access permission to run feeds.');
        }
        try {
            return NXP_FeedScheduler.runNow(feedName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String getRunErrors(Id runId) {
        List<NXP_Feed_Run__c> runs = [
            SELECT Error_Log__c
            FROM NXP_Feed_Run__c
            WHERE Id = :runId
            WITH USER_MODE
            LIMIT 1
        ];
        return runs.isEmpty() ? null : runs[0].Error_Log__c;
    }

    private static String health(FeedTile t) {
        if (!t.active) {
            return 'Paused';
        }
        if (t.lastRun == null) {
            return 'Never run';
        }
        switch on t.lastRun.Status__c {
            when 'Failed' {
                return 'Failed';
            }
            when 'Partial' {
                return 'Warning';
            }
            when 'Running', 'Queued' {
                return 'Running';
            }
            when else {
                return 'Healthy';
            }
        }
    }
}
