/**
 * Apex REST ingestion API for contract-vehicle task orders (for example, a mail relay that
 * parses vehicle portal emails). Records default to notice type "Task Order" and are linked
 * to the Contract Vehicle named by vehicleCode.
 * POST /services/apexrest/nxp/v1/task-orders
 */
@RestResource(urlMapping='/nxp/v1/task-orders')
global with sharing class NXP_TaskOrderIngestResource {
    @HttpPost
    global static void ingest() {
        NXP_RestIngestSupport.handle(true);
    }
}
