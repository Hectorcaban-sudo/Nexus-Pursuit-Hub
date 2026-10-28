/**
 * USAspending.gov award search (POST /api/v2/search/spending_by_award/) for contract awards in
 * the company profile's NAICS codes. Lands Award Summaries and their vendors (incumbents).
 * Bulk history belongs in Data Cloud via the Ingestion API; this connector keeps a targeted,
 * recent slice in core for incumbents and recompetes.
 */
public inherited sharing class NXP_UsaSpendingConnector implements NXP_FeedConnector {
    private static final List<String> FIELDS = new List<String>{
        'Award ID',
        'Recipient Name',
        'Recipient UEI',
        'Award Amount',
        'Start Date',
        'End Date',
        'Awarding Agency',
        'Awarding Sub Agency',
        'Description',
        'generated_internal_id'
    };

    private NXP_Feed_Config__mdt config;

    public void init(NXP_Feed_Config__mdt config) {
        this.config = config;
    }

    public Map<String, Object> initialCheckpoint(Datetime lastSuccess) {
        Integer lookback = config.Lookback_Days__c == null ? 30 : config.Lookback_Days__c.intValue();
        Date toDate = Date.today();
        Date fromDate = lastSuccess == null ? toDate.addDays(-lookback) : lastSuccess.date().addDays(-7);
        return new Map<String, Object>{
            'from' => String.valueOf(fromDate),
            'to' => String.valueOf(toDate),
            'page' => 1
        };
    }

    public NXP_FeedPage fetchPage(Map<String, Object> checkpoint) {
        Integer pageNumber = Integer.valueOf(checkpoint.get('page'));
        Integer pageSize = config.Page_Size__c == null ? 100 : config.Page_Size__c.intValue();

        Map<String, Object> filters = new Map<String, Object>{
            'award_type_codes' => new List<String>{ 'A', 'B', 'C', 'D' },
            'time_period' => new List<Object>{
                new Map<String, Object>{ 'start_date' => checkpoint.get('from'), 'end_date' => checkpoint.get('to') }
            }
        };
        List<String> naics = profileNaics();
        if (!naics.isEmpty()) {
            filters.put('naics_codes', new Map<String, Object>{ 'require' => naics });
        }
        Map<String, Object> request = new Map<String, Object>{
            'filters' => filters,
            'fields' => FIELDS,
            'page' => pageNumber,
            'limit' => pageSize,
            'sort' => 'Award Amount',
            'order' => 'desc'
        };

        HttpResponse res = new NXP_HttpClient()
            .post(config.Named_Credential__c, config.Endpoint_Path__c, JSON.serialize(request));
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        NXP_FeedPage page = new NXP_FeedPage();
        for (Object item : NXP_Json.toList(body.get('results'))) {
            String piid = NXP_Json.getString(item, 'Award ID');
            if (String.isBlank(piid)) {
                continue;
            }
            NXP_IngestRecord rec = new NXP_IngestRecord(NXP_IngestRecord.TYPE_AWARD, piid, config.DeveloperName);
            String description = NXP_Json.getString(item, 'Description');
            rec.put('PIID__c', piid);
            rec.put('Name', NXP_Text.truncate(String.isBlank(description) ? piid : description, 80));
            rec.put('Description__c', description);
            rec.put('Obligated_Amount__c', NXP_Json.toDecimal(NXP_Json.getString(item, 'Award Amount')));
            rec.put('Period_Start__c', NXP_Json.toDate(NXP_Json.getString(item, 'Start Date')));
            rec.put('Period_End__c', NXP_Json.toDate(NXP_Json.getString(item, 'End Date')));
            rec.put('Source_Feed__c', config.DeveloperName);
            String agency = NXP_Json.getString(item, 'Awarding Agency');
            String subAgency = NXP_Json.getString(item, 'Awarding Sub Agency');
            rec.agencyPathNames = String.isBlank(subAgency) || subAgency == agency
                ? agency
                : agency + ' › ' + subAgency;
            rec.vendorUei = NXP_Json.getString(item, 'Recipient UEI');
            rec.vendorName = NXP_Json.getString(item, 'Recipient Name');
            page.records.add(rec);
        }
        Object hasNext = NXP_Json.getPath(body, 'page_metadata.hasNext');
        page.hasMore = hasNext == true;
        page.nextCheckpoint = new Map<String, Object>(checkpoint);
        page.nextCheckpoint.put('page', pageNumber + 1);
        return page;
    }

    private static List<String> profileNaics() {
        List<String> codes = new List<String>();
        for (NXP_Company_Profile__c p : [
            SELECT NAICS_Codes__c
            FROM NXP_Company_Profile__c
            WHERE Active__c = TRUE
            LIMIT 1
        ]) {
            for (String code : NXP_Text.splitList(p.NAICS_Codes__c)) {
                // USAspending accepts 2- to 6-digit NAICS prefixes; drop our * wildcard.
                codes.add(code.removeEnd('*'));
            }
        }
        return codes;
    }
}
