/**
 * Replaces the SAM.gov description link stored by the feed with the description text.
 *
 * SAM.gov's search API returns only a link for each description; the text costs one more API call
 * per notice and counts against the key's daily limit. So the default run fetches text only for
 * notices worth reading: those that matched a saved search (AI summary requested) and those at or
 * above the Description_Min_Fit setting. Anyone can fetch one more from the notice page
 * (NXP_NoticeController.loadDescription). Scope 20 keeps each transaction well under the callout limit.
 * Recomputes the content hash so fetching text is never mistaken for an amendment.
 */
public without sharing class NXP_NoticeEnrichBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    private final Set<Id> noticeIds;

    /** Matched notices and notices at or above Description_Min_Fit. */
    public NXP_NoticeEnrichBatch() {
        this(null);
    }

    /** Only these notices (still needing a description). */
    public NXP_NoticeEnrichBatch(Set<Id> noticeIds) {
        this.noticeIds = noticeIds;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Map<String, Object> binds = new Map<String, Object>();
        String filter;
        if (noticeIds == null) {
            filter = ' AND (Fit_Score__c >= :minFit OR AI_Summary_Status__c IN :requested)';
            binds.put('minFit', NXP_Settings.getInteger('Description_Min_Fit', 50));
            binds.put('requested', new List<String>{ 'Pending', 'Complete', 'Failed' });
        } else {
            filter = ' AND Id IN :ids';
            binds.put('ids', noticeIds);
        }
        return Database.getQueryLocatorWithBinds(
            'SELECT ' +
                NXP_GovNoticeSelector.FIELDS +
                ' FROM NXP_Gov_Notice__c WHERE Needs_Description__c = TRUE' +
                filter +
                ' ORDER BY Fit_Score__c DESC NULLS LAST, CreatedDate DESC LIMIT 2000',
            binds,
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<NXP_Gov_Notice__c> scope) {
        List<NXP_Gov_Notice__c> updates = new List<NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : scope) {
            try {
                apply(n);
                updates.add(n);
            } catch (Exception e) {
                // Leave Needs_Description__c set; the next run retries.
                NXP_Logger.warn(
                    'NXP_NoticeEnrichBatch',
                    'Description fetch failed for ' + n.Notice_Id__c + ': ' + e.getMessage()
                );
            }
        }
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        NXP_Logger.flush();
    }

    public void finish(Database.BatchableContext context) {
    }

    /** True when the notice still holds a SAM.gov description link instead of text. */
    public static Boolean needsText(NXP_Gov_Notice__c n) {
        return n.Needs_Description__c == true &&
            String.isNotBlank(n.Description__c) &&
            n.Description__c.startsWithIgnoreCase('http');
    }

    /**
     * Fetches the text behind the notice's description link and sets it on the record in memory
     * (Description__c, Needs_Description__c, Content_Hash__c). Makes one callout; the caller saves.
     * Throws when SAM.gov does not return it.
     */
    public static void apply(NXP_Gov_Notice__c n) {
        NXP_Feed_Config__mdt config = NXP_ConnectorSupport.config('SAM_Opportunities');
        String link = n.Description__c;
        String path = '/' + link.substringAfter('://').substringAfter('/').substringBefore('?');
        Map<String, String> params = new Map<String, String>();
        for (String pair : link.substringAfter('?').split('&')) {
            if (pair.contains('=') && !pair.startsWithIgnoreCase('api_key=')) {
                params.put(pair.substringBefore('='), EncodingUtil.urlDecode(pair.substringAfter('='), 'UTF-8'));
            }
        }
        HttpResponse res = new NXP_HttpClient().get(config.Named_Credential__c, path, params);
        String body = res.getBody();
        String html = body;
        if (body != null && body.trim().startsWith('{')) {
            html = NXP_Json.getString(JSON.deserializeUntyped(body), 'description');
        }
        n.Description__c = NXP_Text.truncate(NXP_ConnectorSupport.htmlToText(html), 131072);
        n.Needs_Description__c = false;
        n.Content_Hash__c = NXP_IngestionService.computeHash(n);
    }
}
