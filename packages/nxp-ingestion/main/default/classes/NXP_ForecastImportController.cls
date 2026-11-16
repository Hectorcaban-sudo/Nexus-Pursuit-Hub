/**
 * Import forecasts from a spreadsheet (Feed Console → Import forecasts). Agencies publish
 * forecasts as Excel/CSV downloads (GSA Acquisition Gateway forecast tool, DHS, HHS) rather than
 * APIs. The screen reads the CSV in the browser, the admin maps its columns once, and the rows come
 * here already mapped. They go through the normal ingestion path: upsert by forecast ID, agency
 * matching, and the notice link when the notice posts. Nexus admins only.
 */
public with sharing class NXP_ForecastImportController {
    public static final Integer MAX_ROWS = 500;

    @TestVisible
    private static Boolean canImportOverride;

    /** One spreadsheet row, mapped by the screen. Dates are yyyy-mm-dd; value is a number. */
    public class Row {
        public String forecastId;
        public String title;
        public String agency;
        public String subAgency;
        public String solicitationDate;
        public Decimal value;
        public String fiscalYear;
        public String naics;
        public String setAside;
        public String description;
    }

    public class ImportResult {
        @AuraEnabled
        public Integer read = 0;
        @AuraEnabled
        public Integer created = 0;
        @AuraEnabled
        public Integer updated = 0;
        @AuraEnabled
        public Integer unchanged = 0;
        @AuraEnabled
        public Integer rejected = 0;
        @AuraEnabled
        public List<String> problems = new List<String>();
    }

    public static Boolean canImport() {
        return canImportOverride != null ? canImportOverride : FeatureManagement.checkPermission('NXP_Admin_Access');
    }

    /**
     * Imports up to 500 mapped rows from one source (the screen sends a large file in batches).
     * sourceName is stored as the Source Feed, e.g. "Acquisition Gateway" or "DHS forecast".
     */
    @AuraEnabled
    public static ImportResult importForecasts(String sourceName, String rowsJson) {
        try {
            if (!canImport()) {
                throw new IllegalArgumentException('Only Nexus admins can import forecasts.');
            }
            List<Row> rows = (List<Row>) JSON.deserialize(rowsJson, List<Row>.class);
            if (rows.size() > MAX_ROWS) {
                throw new IllegalArgumentException('Send at most ' + MAX_ROWS + ' rows at a time.');
            }
            String source = String.isBlank(sourceName) ? 'Spreadsheet' : sourceName.trim().left(80);
            ImportResult out = new ImportResult();
            List<NXP_IngestRecord> records = new List<NXP_IngestRecord>();
            Integer line = 1;
            for (Row r : rows) {
                line++;
                out.read++;
                String problem = check(r);
                if (problem != null) {
                    out.rejected++;
                    addProblem(out, 'Row ' + line + ': ' + problem);
                    continue;
                }
                records.add(toRecord(r, source));
            }
            if (!records.isEmpty()) {
                NXP_IngestionService.Result res = NXP_IngestionService.ingest(records);
                out.created += res.created;
                out.updated += res.updated;
                out.unchanged += res.unchanged;
                out.rejected += res.rejected;
                for (NXP_IngestionService.RecordResult rr : res.results) {
                    if (rr.status == 'Rejected') {
                        addProblem(out, (rr.externalKey == null ? 'A row' : rr.externalKey) + ': ' + rr.message);
                    }
                }
            }
            return out;
        } catch (Exception e) {
            AuraHandledException a = new AuraHandledException(e.getMessage());
            a.setMessage(e.getMessage());
            throw a;
        }
    }

    @TestVisible
    private static String check(Row r) {
        if (String.isBlank(r.title)) {
            return 'no title';
        }
        if (String.isBlank(r.agency)) {
            return 'no agency';
        }
        if (String.isNotBlank(r.solicitationDate)) {
            try {
                Date.valueOf(r.solicitationDate);
            } catch (Exception e) {
                return 'date "' + r.solicitationDate + '" is not yyyy-mm-dd';
            }
        }
        return null;
    }

    @TestVisible
    private static NXP_IngestRecord toRecord(Row r, String source) {
        NXP_IngestRecord rec = new NXP_IngestRecord(NXP_IngestRecord.TYPE_FORECAST, null, source);
        rec.externalKey = String.isNotBlank(r.forecastId)
            ? r.forecastId.trim().left(100)
            : generatedKey(source, r.agency, r.title);
        rec.put('Name', r.title.trim().left(80));
        rec.put('Forecast_Id__c', rec.externalKey);
        rec.put(
            'Estimated_Solicitation_Date__c',
            String.isBlank(r.solicitationDate) ? null : Date.valueOf(r.solicitationDate)
        );
        rec.put('Estimated_Value__c', r.value);
        rec.put('Fiscal_Year__c', r.fiscalYear);
        rec.put('NAICS_Code__c', String.isBlank(r.naics) ? null : r.naics.replaceAll('[^0-9]', '').left(6));
        rec.put('Set_Aside__c', r.setAside);
        rec.put('Description__c', r.description);
        rec.put('Source_Feed__c', source);
        // Always use the › separator: agency names often contain dots ("Dept. of the Army").
        rec.agencyPathNames = String.isBlank(r.subAgency)
            ? r.agency.trim() + ' ›'
            : r.agency.trim() + ' › ' + r.subAgency.trim();
        return rec;
    }

    /** Sources without an ID column: a stable key from the source, agency and title. */
    @TestVisible
    private static String generatedKey(String source, String agency, String title) {
        String basis = (source + '|' + agency + '|' + title).toLowerCase().replaceAll('\\s+', ' ').trim();
        String hex = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(basis)));
        return (source.replaceAll('[^A-Za-z0-9]', '').left(20) + '-' + hex.left(16)).toUpperCase();
    }

    private static void addProblem(ImportResult out, String message) {
        if (out.problems.size() < 50) {
            out.problems.add(message);
        }
    }
}
