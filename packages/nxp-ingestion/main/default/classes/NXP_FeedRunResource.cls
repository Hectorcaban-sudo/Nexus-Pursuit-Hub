/**
 * Status of a feed run or REST ingestion call.
 * GET /services/apexrest/nxp/v1/runs/{runId}
 */
@RestResource(urlMapping='/nxp/v1/runs/*')
global with sharing class NXP_FeedRunResource {
    @HttpGet
    global static void getRun() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        String runId = RestContext.request.requestURI.substringAfterLast('/');
        List<NXP_Feed_Run__c> runs = [
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
                Error_Log__c
            FROM NXP_Feed_Run__c
            WHERE Id = :runId
            WITH USER_MODE
            LIMIT 1
        ];
        if (runs.isEmpty()) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'error' => 'Run not found' }));
            return;
        }
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(runs[0]));
    }
}
