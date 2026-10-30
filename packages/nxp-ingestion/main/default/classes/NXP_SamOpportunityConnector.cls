/**
 * SAM.gov Get Opportunities Public API v2 (GET /opportunities/v2/search).
 * Pages over a posted-date window. SAM.gov's offset is a page index (0, 1, 2...), not a record
 * offset, and limit is the page size (max 1000). The API key is sent as the X-Api-Key header
 * by the NXP_SAM_Gov Named Credential, never stored in code or metadata records.
 */
public inherited sharing class NXP_SamOpportunityConnector implements NXP_FeedConnector {
    private static final Map<String, String> TYPE_MAP = new Map<String, String>{
        'presolicitation' => 'Pre-solicitation',
        'pre-solicitation' => 'Pre-solicitation',
        'sources sought' => 'Sources Sought',
        'solicitation' => 'Solicitation',
        'combined synopsis/solicitation' => 'Combined Synopsis/Solicitation',
        'award notice' => 'Award Notice',
        'special notice' => 'Special Notice',
        'rfi' => 'RFI',
        'request for information' => 'RFI',
        'grant' => 'Grant',
        'task order' => 'Task Order'
    };

    private NXP_Feed_Config__mdt config;

    public void init(NXP_Feed_Config__mdt config) {
        this.config = config;
    }

    public Map<String, Object> initialCheckpoint(Datetime lastSuccess) {
        Integer lookback = config.Lookback_Days__c == null ? 2 : config.Lookback_Days__c.intValue();
        Date toDate = Date.today();
        Date fromDate = lastSuccess == null ? toDate.addDays(-lookback) : lastSuccess.date().addDays(-1);
        // SAM.gov rejects windows longer than one year.
        if (fromDate.daysBetween(toDate) > 364) {
            fromDate = toDate.addDays(-364);
        }
        return new Map<String, Object>{
            'postedFrom' => samDate(fromDate),
            'postedTo' => samDate(toDate),
            'offset' => 0
        };
    }

    public NXP_FeedPage fetchPage(Map<String, Object> checkpoint) {
        Integer pageSize = config.Page_Size__c == null ? 1000 : config.Page_Size__c.intValue();
        // Page index, not a record offset: SAM.gov returns page N as records N*limit to (N+1)*limit - 1.
        Integer offset = checkpoint.get('offset') == null ? 0 : Integer.valueOf(checkpoint.get('offset'));
        Map<String, String> params = NXP_ConnectorSupport.parseParams(config.Extra_Parameters__c);
        params.put('postedFrom', String.valueOf(checkpoint.get('postedFrom')));
        params.put('postedTo', String.valueOf(checkpoint.get('postedTo')));
        params.put('limit', String.valueOf(pageSize));
        params.put('offset', String.valueOf(offset));

        HttpResponse res = new NXP_HttpClient().get(config.Named_Credential__c, config.Endpoint_Path__c, params);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> items = NXP_Json.toList(body.get('opportunitiesData'));

        NXP_FeedPage page = new NXP_FeedPage();
        page.totalRecords = body.get('totalRecords') == null ? 0 : Integer.valueOf(body.get('totalRecords'));
        for (Object item : items) {
            page.records.add(toRecord(config.DeveloperName, item));
        }
        Integer nextOffset = offset + 1;
        page.hasMore = !items.isEmpty() && nextOffset * pageSize < page.totalRecords;
        page.nextCheckpoint = new Map<String, Object>(checkpoint);
        page.nextCheckpoint.put('offset', nextOffset);
        return page;
    }

    /** Public so tests and the REST channel can reuse the same normalization. */
    public static NXP_IngestRecord toRecord(String feedName, Object item) {
        Map<String, Object> raw = NXP_Json.toMap(item);
        NXP_IngestRecord rec = new NXP_IngestRecord(
            NXP_IngestRecord.TYPE_NOTICE,
            NXP_Json.getString(raw, 'noticeId'),
            feedName
        );
        NXP_FeedMapper.apply(feedName, raw, rec);
        rec.put('Notice_Id__c', rec.externalKey);
        rec.put('Notice_Type__c', normalizeType(NXP_Json.getString(raw, 'type')));
        rec.put('Status__c', 'Yes'.equalsIgnoreCase(NXP_Json.getString(raw, 'active')) ? 'Active' : 'Archived');
        rec.put('Market__c', 'Federal');
        rec.put('Source_Feed__c', feedName);
        rec.agencyPathNames = NXP_Json.getString(raw, 'fullParentPathName');
        rec.agencyPathCodes = NXP_Json.getString(raw, 'fullParentPathCode');

        String city = NXP_Json.getString(raw, 'placeOfPerformance.city.name');
        String state = NXP_Json.getString(raw, 'placeOfPerformance.state.code');
        if (String.isNotBlank(city) || String.isNotBlank(state)) {
            rec.put(
                'Place_Of_Performance__c',
                String.join(new List<String>{ city == null ? '' : city, state == null ? '' : state }, ', ')
                    .removeStart(', ')
                    .removeEnd(', ')
            );
        }
        String description = (String) rec.values.get('Description__c');
        rec.put('Needs_Description__c', description != null && description.startsWithIgnoreCase('http'));

        for (Object poc : NXP_Json.toList(raw.get('pointOfContact'))) {
            NXP_IngestRecord.ContactInfo c = new NXP_IngestRecord.ContactInfo();
            c.fullName = NXP_Json.getString(poc, 'fullName');
            c.email = NXP_Json.getString(poc, 'email');
            c.phone = NXP_Json.getString(poc, 'phone');
            c.role = 'primary'.equalsIgnoreCase(NXP_Json.getString(poc, 'type'))
                ? 'Contracting Officer'
                : 'Contract Specialist';
            if (String.isNotBlank(c.fullName) || String.isNotBlank(c.email)) {
                rec.contacts.add(c);
            }
        }
        return rec;
    }

    public static String normalizeType(String sourceType) {
        if (String.isBlank(sourceType)) {
            return 'Other';
        }
        String key = sourceType.trim().toLowerCase();
        return TYPE_MAP.containsKey(key) ? TYPE_MAP.get(key) : 'Other';
    }

    private static String samDate(Date d) {
        return String.valueOf(d.month()).leftPad(2, '0') +
            '/' +
            String.valueOf(d.day()).leftPad(2, '0') +
            '/' +
            d.year();
    }
}
