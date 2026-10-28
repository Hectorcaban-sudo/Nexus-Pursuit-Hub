/**
 * Generic JSON forecast connector (Acquisition Gateway or an agency forecast API).
 * Field names are mapped with NXP_Feed_Mapping__mdt, so a different forecast source needs
 * new mapping rows, not code. Options in Extra_Parameters__c:
 *   _list=path.to.array   where the records are in the response (default: root array or "results")
 *   _agency=path          field holding the buyer name path (default: agency)
 *   _page=name            page parameter name (default: page)
 * Any other key=value pairs are sent as query parameters.
 */
public inherited sharing class NXP_ForecastConnector implements NXP_FeedConnector {
    private NXP_Feed_Config__mdt config;
    private Map<String, String> options;

    public void init(NXP_Feed_Config__mdt config) {
        this.config = config;
        this.options = NXP_ConnectorSupport.parseParams(config.Extra_Parameters__c);
    }

    public Map<String, Object> initialCheckpoint(Datetime lastSuccess) {
        return new Map<String, Object>{ 'page' => 1 };
    }

    public NXP_FeedPage fetchPage(Map<String, Object> checkpoint) {
        Integer pageNumber = checkpoint.get('page') == null ? 1 : Integer.valueOf(checkpoint.get('page'));
        Integer pageSize = config.Page_Size__c == null ? 100 : config.Page_Size__c.intValue();
        Map<String, String> params = new Map<String, String>();
        for (String key : options.keySet()) {
            if (!key.startsWith('_')) {
                params.put(key, options.get(key));
            }
        }
        params.put(options.containsKey('_page') ? options.get('_page') : 'page', String.valueOf(pageNumber));
        params.put('limit', String.valueOf(pageSize));

        HttpResponse res = new NXP_HttpClient().get(config.Named_Credential__c, config.Endpoint_Path__c, params);
        Object body = JSON.deserializeUntyped(res.getBody());
        List<Object> items = body instanceof List<Object>
            ? (List<Object>) body
            : NXP_Json.toList(NXP_Json.getPath(body, options.containsKey('_list') ? options.get('_list') : 'results'));

        NXP_FeedPage page = new NXP_FeedPage();
        String agencyPath = options.containsKey('_agency') ? options.get('_agency') : 'agency';
        for (Object item : items) {
            NXP_IngestRecord rec = new NXP_IngestRecord(NXP_IngestRecord.TYPE_FORECAST, null, config.DeveloperName);
            NXP_FeedMapper.apply(config.DeveloperName, item, rec);
            rec.externalKey = (String) rec.values.get('Forecast_Id__c');
            rec.put('Source_Feed__c', config.DeveloperName);
            rec.agencyPathNames = NXP_Json.getString(item, agencyPath);
            if (String.isNotBlank(rec.externalKey)) {
                page.records.add(rec);
            }
        }
        page.hasMore = items.size() >= pageSize;
        page.nextCheckpoint = new Map<String, Object>{ 'page' => pageNumber + 1 };
        return page;
    }
}
