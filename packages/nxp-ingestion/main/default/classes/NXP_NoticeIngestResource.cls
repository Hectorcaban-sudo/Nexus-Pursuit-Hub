/**
 * Apex REST ingestion API for notices pushed in by other systems.
 * POST /services/apexrest/nxp/v1/notices   (contract: docs/integration/rest-ingestion-api.md)
 */
@RestResource(urlMapping='/nxp/v1/notices')
global with sharing class NXP_NoticeIngestResource {
    @HttpPost
    global static void ingest() {
        NXP_RestIngestSupport.handle(false);
    }
}
