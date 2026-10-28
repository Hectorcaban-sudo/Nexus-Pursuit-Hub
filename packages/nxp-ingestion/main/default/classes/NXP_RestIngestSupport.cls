/**
 * Shared handling for the Apex REST ingestion endpoints (/nxp/v1/notices, /nxp/v1/task-orders):
 * idempotency, validation, conversion to NXP_IngestRecord, run logging and the JSON response.
 * See docs/integration/rest-ingestion-api.md for the contract.
 */
public without sharing class NXP_RestIngestSupport {
    public class RequestException extends Exception {
    }

    public static void handle(Boolean taskOrders) {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        String idempotencyKey = req.headers.get('Idempotency-Key');
        try {
            if (!FeatureManagement.checkPermission('NXP_Integration_Access') && !Test.isRunningTest()) {
                respond(
                    res,
                    403,
                    new Map<String, Object>{ 'error' => 'The calling user needs the NXP_Integration permission set.' }
                );
                return;
            }
            if (String.isNotBlank(idempotencyKey)) {
                List<NXP_Feed_Run__c> previous = [
                    SELECT Response_Body__c
                    FROM NXP_Feed_Run__c
                    WHERE Idempotency_Key__c = :idempotencyKey
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                if (!previous.isEmpty() && String.isNotBlank(previous[0].Response_Body__c)) {
                    res.statusCode = 200;
                    res.addHeader('Idempotent-Replay', 'true');
                    res.responseBody = Blob.valueOf(previous[0].Response_Body__c);
                    return;
                }
            }
            Map<String, Object> body = parse(req.requestBody);
            String source = (String) body.get('source');
            if (String.isBlank(source) || !Pattern.matches('[A-Za-z0-9_\\-]{1,40}', source)) {
                throw new RequestException('"source" is required: 1-40 letters, digits, _ or -.');
            }
            List<Object> items = NXP_Json.toList(body.get('records'));
            Integer max = NXP_Settings.getInteger('Rest_Max_Records', 200);
            if (items.isEmpty()) {
                throw new RequestException('"records" must be a non-empty array.');
            }
            if (items.size() > max) {
                respond(
                    res,
                    413,
                    new Map<String, Object>{ 'error' => 'Too many records: ' + items.size() + ' (max ' + max + ').' }
                );
                return;
            }

            String feedName = 'REST_' + source;
            NXP_Feed_Run__c run = NXP_FeedRunService.start(
                feedName,
                NXP_FeedRunService.CH_REST,
                UserInfo.getUserName()
            );
            List<NXP_IngestRecord> records = new List<NXP_IngestRecord>();
            for (Object item : items) {
                records.add(toRecord(feedName, source, NXP_Json.toMap(item), taskOrders));
            }
            NXP_IngestionService.Result result = NXP_IngestionService.ingest(records);
            NXP_FeedRunService.recordPage(run.Id, result, null);
            NXP_FeedRunService.finish(run.Id, 'Succeeded');

            List<Object> perRecord = new List<Object>();
            for (NXP_IngestionService.RecordResult r : result.results) {
                perRecord.add(
                    new Map<String, Object>{
                        'sourceId' => r.sourceId,
                        'noticeId' => r.externalKey,
                        'status' => r.status,
                        'recordId' => r.recordId,
                        'message' => r.message
                    }
                );
            }
            Map<String, Object> payload = new Map<String, Object>{
                'runId' => run.Id,
                'received' => result.read,
                'created' => result.created,
                'updated' => result.updated,
                'unchanged' => result.unchanged,
                'rejected' => result.rejected,
                'results' => perRecord
            };
            String responseJson = JSON.serialize(payload);
            update as system new NXP_Feed_Run__c(
                Id = run.Id,
                Idempotency_Key__c = String.isBlank(idempotencyKey) ? null : NXP_Text.truncate(idempotencyKey, 120),
                Response_Body__c = NXP_Text.truncate(responseJson, 131072)
            );
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(responseJson);
        } catch (RequestException e) {
            respond(res, 400, new Map<String, Object>{ 'error' => e.getMessage() });
        } catch (Exception e) {
            NXP_Logger.error('NXP_RestIngestSupport', 'REST ingestion failed', e, null);
            respond(
                res,
                500,
                new Map<String, Object>{ 'error' => 'Unexpected error; see NXP Logs.', 'detail' => e.getMessage() }
            );
        } finally {
            NXP_Logger.flush();
        }
    }

    @TestVisible
    private static NXP_IngestRecord toRecord(String feedName, String source, Map<String, Object> r, Boolean taskOrder) {
        String sourceId = str(r, 'sourceId');
        String noticeId = str(r, 'noticeId');
        String key = String.isNotBlank(noticeId)
            ? noticeId
            : (String.isBlank(sourceId) ? null : source.toUpperCase() + ':' + sourceId);
        NXP_IngestRecord rec = new NXP_IngestRecord(NXP_IngestRecord.TYPE_NOTICE, key, feedName);
        rec.sourceId = sourceId;
        if (String.isBlank(str(r, 'title'))) {
            rec.externalKey = null; // rejected by the service with a clear message
        }
        rec.put('Title__c', str(r, 'title'));
        rec.put('Solicitation_Number__c', str(r, 'solicitationNumber'));
        rec.put(
            'Notice_Type__c',
            taskOrder && String.isBlank(str(r, 'noticeType'))
                ? 'Task Order'
                : NXP_IngestionService.normalizeNoticeType(str(r, 'noticeType'))
        );
        rec.put('Status__c', String.isBlank(str(r, 'status')) ? 'Active' : str(r, 'status'));
        rec.put('Market__c', String.isBlank(str(r, 'market')) ? 'Federal' : str(r, 'market'));
        rec.put('NAICS_Code__c', str(r, 'naics'));
        rec.put('PSC_Code__c', str(r, 'psc'));
        rec.put('Set_Aside__c', str(r, 'setAside'));
        rec.put('Estimated_Value__c', NXP_Json.toDecimal(str(r, 'estimatedValue')));
        rec.put('Posted_Date__c', NXP_Json.toDate(str(r, 'postedDate')));
        rec.put('Response_Due__c', NXP_Json.toDateTime(str(r, 'responseDue')));
        rec.put('Archive_Date__c', NXP_Json.toDate(str(r, 'archiveDate')));
        rec.put('Description__c', str(r, 'description'));
        rec.put('Notice_URL__c', str(r, 'url'));
        rec.put('Place_Of_Performance__c', str(r, 'placeOfPerformance'));
        rec.put('Office__c', str(r, 'office'));
        rec.put('Source_Feed__c', feedName);
        rec.agencyPathNames = str(r, 'agencyPath');
        rec.agencyPathCodes = str(r, 'agencyCodePath');
        rec.vehicleCode = str(r, 'vehicleCode');
        for (Object c : NXP_Json.toList(r.get('contacts'))) {
            NXP_IngestRecord.ContactInfo info = new NXP_IngestRecord.ContactInfo();
            info.fullName = NXP_Json.getString(c, 'name');
            info.email = NXP_Json.getString(c, 'email');
            info.phone = NXP_Json.getString(c, 'phone');
            info.role = NXP_Json.getString(c, 'role');
            rec.contacts.add(info);
        }
        return rec;
    }

    private static Map<String, Object> parse(Blob requestBody) {
        if (requestBody == null || requestBody.size() == 0) {
            throw new RequestException('Request body is empty.');
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(requestBody.toString());
        } catch (Exception e) {
            throw new RequestException('Body is not a JSON object: ' + e.getMessage());
        }
    }

    private static String str(Map<String, Object> r, String key) {
        Object v = r.get(key);
        return v == null ? null : String.valueOf(v).trim();
    }

    private static void respond(RestResponse res, Integer status, Map<String, Object> payload) {
        res.statusCode = status;
        res.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}
