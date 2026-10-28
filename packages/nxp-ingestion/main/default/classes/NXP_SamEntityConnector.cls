/**
 * SAM.gov Entity Management API v3. Refreshes Gov Vendors whose data is older than the
 * feed's lookback, one UEI per callout (page size <= 50 keeps each transaction under the
 * 100-callout limit). A run refreshes at most 500 vendors to respect SAM.gov daily rate limits
 * and the checkpoint size. lookup() serves on-demand refreshes from a button or agent action.
 */
public inherited sharing class NXP_SamEntityConnector implements NXP_FeedConnector {
    private NXP_Feed_Config__mdt config;

    public void init(NXP_Feed_Config__mdt config) {
        this.config = config;
    }

    public Map<String, Object> initialCheckpoint(Datetime lastSuccess) {
        Integer lookback = config.Lookback_Days__c == null ? 30 : config.Lookback_Days__c.intValue();
        Datetime stale = Datetime.now().addDays(-lookback);
        List<String> ueis = new List<String>();
        for (NXP_Gov_Vendor__c v : [
            SELECT UEI__c
            FROM NXP_Gov_Vendor__c
            WHERE UEI__c != NULL AND (Last_Synced__c = NULL OR Last_Synced__c < :stale)
            ORDER BY Last_Synced__c ASC NULLS FIRST
            LIMIT 500
        ]) {
            ueis.add(v.UEI__c);
        }
        return new Map<String, Object>{ 'ueis' => ueis, 'index' => 0 };
    }

    public NXP_FeedPage fetchPage(Map<String, Object> checkpoint) {
        List<Object> ueis = NXP_Json.toList(checkpoint.get('ueis'));
        Integer index = Integer.valueOf(checkpoint.get('index'));
        Integer pageSize = Math.min(config.Page_Size__c == null ? 50 : config.Page_Size__c.intValue(), 90);
        NXP_FeedPage page = new NXP_FeedPage();
        Integer stop = Math.min(index + pageSize, ueis.size());
        for (Integer i = index; i < stop; i++) {
            NXP_IngestRecord rec = fetchOne(
                config.Named_Credential__c,
                config.Endpoint_Path__c,
                String.valueOf(ueis[i]),
                config.DeveloperName
            );
            if (rec != null) {
                page.records.add(rec);
            }
        }
        page.totalRecords = ueis.size();
        page.hasMore = stop < ueis.size();
        page.nextCheckpoint = new Map<String, Object>{ 'ueis' => ueis, 'index' => stop };
        return page;
    }

    /** Single UEI lookup using the SAM_Entity feed settings. */
    public static NXP_IngestRecord lookup(String uei) {
        NXP_Feed_Config__mdt cfg = NXP_ConnectorSupport.config('SAM_Entity');
        return fetchOne(cfg.Named_Credential__c, cfg.Endpoint_Path__c, uei, cfg.DeveloperName);
    }

    private static NXP_IngestRecord fetchOne(String nc, String path, String uei, String feedName) {
        HttpResponse res = new NXP_HttpClient()
            .get(
                nc,
                path,
                new Map<String, String>{ 'ueiSAM' => uei, 'includeSections' => 'entityRegistration,coreData' }
            );
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object entity = NXP_Json.getPath(body, 'entityData[0]');
        if (entity == null) {
            return null;
        }
        NXP_IngestRecord rec = new NXP_IngestRecord(NXP_IngestRecord.TYPE_VENDOR, uei, feedName);
        rec.put('UEI__c', uei);
        rec.put('Name', NXP_Text.truncate(NXP_Json.getString(entity, 'entityRegistration.legalBusinessName'), 80));
        rec.put('CAGE_Code__c', NXP_Json.getString(entity, 'entityRegistration.cageCode'));
        rec.put('City__c', NXP_Json.getString(entity, 'coreData.physicalAddress.city'));
        rec.put('State__c', NXP_Json.getString(entity, 'coreData.physicalAddress.stateOrProvinceCode'));
        List<String> types = new List<String>();
        for (Object t : NXP_Json.toList(NXP_Json.getPath(entity, 'coreData.businessTypes.sbaBusinessTypeList'))) {
            String d = NXP_Json.getString(t, 'sbaBusinessTypeDesc');
            if (String.isNotBlank(d)) {
                types.add(d);
            }
        }
        rec.put('Socio_Economic__c', NXP_Text.truncate(String.join(types, '; '), 255));
        rec.put('Business_Size__c', types.isEmpty() ? 'Unknown' : 'Small');
        rec.put('Last_Synced__c', Datetime.now());
        return rec;
    }
}
