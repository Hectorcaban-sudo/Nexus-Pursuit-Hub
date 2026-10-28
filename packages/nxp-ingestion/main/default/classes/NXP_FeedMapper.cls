/**
 * Applies NXP_Feed_Mapping__mdt rows (source JSON path -> target field, with a transform)
 * to one raw source record.
 */
public inherited sharing class NXP_FeedMapper {
    private static Map<String, List<NXP_Feed_Mapping__mdt>> byFeed;

    @TestVisible
    private static void setForTest(String feed, List<NXP_Feed_Mapping__mdt> rows) {
        load();
        byFeed.put(feed, rows);
    }

    public static List<NXP_Feed_Mapping__mdt> mappingsFor(String feed) {
        load();
        return byFeed.containsKey(feed) ? byFeed.get(feed) : new List<NXP_Feed_Mapping__mdt>();
    }

    public static void apply(String feed, Object raw, NXP_IngestRecord rec) {
        for (NXP_Feed_Mapping__mdt m : mappingsFor(feed)) {
            Object value = NXP_Json.coerce(NXP_Json.getPath(raw, m.Source_Path__c), m.Transform__c);
            if (value == null && String.isNotBlank(m.Default_Value__c)) {
                value = NXP_Json.coerce(m.Default_Value__c, m.Transform__c);
            }
            rec.put(m.Target_Field__c, value);
        }
    }

    private static void load() {
        if (byFeed != null) {
            return;
        }
        byFeed = new Map<String, List<NXP_Feed_Mapping__mdt>>();
        for (NXP_Feed_Mapping__mdt m : NXP_Feed_Mapping__mdt.getAll().values()) {
            if (!byFeed.containsKey(m.Feed__c)) {
                byFeed.put(m.Feed__c, new List<NXP_Feed_Mapping__mdt>());
            }
            byFeed.get(m.Feed__c).add(m);
        }
    }
}
