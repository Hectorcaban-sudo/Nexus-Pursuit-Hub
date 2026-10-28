/**
 * Channel-neutral record handed to NXP_IngestionService by every feed connector,
 * batch import and Apex REST call. values holds target field API name -> typed value.
 */
public inherited sharing class NXP_IngestRecord {
    public static final String TYPE_NOTICE = 'Notice';
    public static final String TYPE_FORECAST = 'Forecast';
    public static final String TYPE_VENDOR = 'Vendor';
    public static final String TYPE_AWARD = 'Award';

    public class ContactInfo {
        public String fullName;
        public String email;
        public String phone;
        public String role;
    }

    /** Notice, Forecast, Vendor or Award. */
    public String recordType = TYPE_NOTICE;
    /** External key: Notice_Id__c, Forecast_Id__c, UEI__c or PIID__c. */
    public String externalKey;
    /** Caller's own identifier (REST), echoed back in per-record results. */
    public String sourceId;
    public String sourceFeed;
    public Map<String, Object> values = new Map<String, Object>();
    /** Buyer path, outermost first, separated by '.', '>' or '›'. */
    public String agencyPathNames;
    /** Optional matching code path, e.g. 070.7014 (SAM.gov fullParentPathCode). */
    public String agencyPathCodes;
    public String vehicleCode;
    public String vendorUei;
    public String vendorName;
    public List<ContactInfo> contacts = new List<ContactInfo>();

    public NXP_IngestRecord() {
    }

    public NXP_IngestRecord(String recordType, String externalKey, String sourceFeed) {
        this.recordType = recordType;
        this.externalKey = externalKey;
        this.sourceFeed = sourceFeed;
    }

    public void put(String field, Object value) {
        if (value != null && !(value instanceof String && String.isBlank((String) value))) {
            values.put(field, value);
        }
    }
}
