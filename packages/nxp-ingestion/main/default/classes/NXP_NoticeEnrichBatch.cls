/**
 * Replaces the SAM.gov description link stored by the feed with the description text,
 * using an Apex callout per notice (scope 20 keeps each transaction well under the callout limit).
 * Recomputes the content hash so fetching text is never mistaken for an amendment.
 */
public without sharing class NXP_NoticeEnrichBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            'SELECT ' +
                NXP_GovNoticeSelector.FIELDS +
                ' FROM NXP_Gov_Notice__c WHERE Needs_Description__c = TRUE ORDER BY CreatedDate DESC LIMIT 5000'
        );
    }

    public void execute(Database.BatchableContext context, List<NXP_Gov_Notice__c> scope) {
        NXP_Feed_Config__mdt config = NXP_ConnectorSupport.config('SAM_Opportunities');
        List<NXP_Gov_Notice__c> updates = new List<NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : scope) {
            try {
                String link = n.Description__c;
                String path = '/' + link.substringAfter('://').substringAfter('/').substringBefore('?');
                Map<String, String> params = new Map<String, String>();
                for (String pair : link.substringAfter('?').split('&')) {
                    if (pair.contains('=') && !pair.startsWithIgnoreCase('api_key=')) {
                        params.put(
                            pair.substringBefore('='),
                            EncodingUtil.urlDecode(pair.substringAfter('='), 'UTF-8')
                        );
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
}
