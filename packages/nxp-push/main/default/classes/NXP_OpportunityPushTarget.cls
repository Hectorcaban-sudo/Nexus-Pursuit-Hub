/**
 * Push target driven entirely by NXP_Push_Mapping__mdt (mapping set from NXP_Setting
 * Push_Mapping_Set). Ships pointed at Opportunity; point Target_Object__c and the target fields at
 * the Opportunity object in each org. Dedupe uses mapping rows whose Source_Field__c is
 * Solicitation_Number__c or Notice_Id__c (add a field such as NXP_Solicitation_Number__c on the
 * target object and map it to enable this).
 */
public inherited sharing class NXP_OpportunityPushTarget implements NXP_PushTarget {
    private static final Set<String> MATCH_SOURCES = new Set<String>{ 'solicitation_number__c', 'notice_id__c' };

    @TestVisible
    private static List<NXP_Push_Mapping__mdt> mappingOverride;

    private final List<NXP_Push_Mapping__mdt> mappings;
    private final String objectName;
    private final Map<String, Schema.SObjectField> targetFields;

    public NXP_OpportunityPushTarget() {
        this.mappings = loadMappings();
        if (mappings.isEmpty()) {
            throw new IllegalArgumentException('No active NXP_Push_Mapping__mdt rows for mapping set ' + mappingSet());
        }
        this.objectName = mappings[0].Target_Object__c;
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
        if (t == null) {
            throw new IllegalArgumentException('Push target object not found: ' + objectName);
        }
        this.targetFields = t.getDescribe().fields.getMap();
    }

    public String targetObject() {
        return objectName;
    }

    public List<NXP_PushFieldPreview> preview(NXP_Gov_Notice__c notice) {
        List<NXP_PushFieldPreview> rows = new List<NXP_PushFieldPreview>();
        for (NXP_Push_Mapping__mdt m : mappings) {
            Object v = valueFor(m, notice);
            rows.add(
                new NXP_PushFieldPreview(
                    m.Target_Field__c,
                    labelOf(m.Target_Field__c),
                    display(v),
                    m.Required__c,
                    syncLabel(m.Sync_Behavior__c)
                )
            );
        }
        return rows;
    }

    public Map<Id, SObject> findExisting(List<NXP_Gov_Notice__c> notices) {
        Map<Id, SObject> found = new Map<Id, SObject>();
        for (NXP_Push_Mapping__mdt m : mappings) {
            if (m.Source_Field__c == null || !MATCH_SOURCES.contains(m.Source_Field__c.toLowerCase())) {
                continue;
            }
            Schema.SObjectField f = targetFields.get(m.Target_Field__c.toLowerCase());
            if (f == null || !f.getDescribe().isFilterable()) {
                continue;
            }
            Map<String, Id> noticeByValue = new Map<String, Id>();
            for (NXP_Gov_Notice__c n : notices) {
                Object v = n.get(m.Source_Field__c);
                if (v != null && !found.containsKey(n.Id)) {
                    noticeByValue.put(String.valueOf(v), n.Id);
                }
            }
            if (noticeByValue.isEmpty()) {
                continue;
            }
            Set<String> values = noticeByValue.keySet();
            String soql =
                'SELECT Id, Name, ' +
                m.Target_Field__c +
                ' FROM ' +
                objectName +
                ' WHERE ' +
                m.Target_Field__c +
                ' IN :values LIMIT 200';
            for (
                SObject row : Database.queryWithBinds(
                    soql,
                    new Map<String, Object>{ 'values' => values },
                    AccessLevel.USER_MODE
                )
            ) {
                Id noticeId = noticeByValue.get(String.valueOf(row.get(m.Target_Field__c)));
                if (noticeId != null) {
                    found.put(noticeId, row);
                }
            }
        }
        return found;
    }

    public List<SObject> build(List<NXP_Gov_Notice__c> notices, Id ownerId) {
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
        List<SObject> rows = new List<SObject>();
        for (NXP_Gov_Notice__c n : notices) {
            SObject row = t.newSObject();
            for (NXP_Push_Mapping__mdt m : mappings) {
                Object v = coerce(m.Target_Field__c, valueFor(m, n));
                if (v == null && m.Required__c) {
                    throw new IllegalArgumentException(
                        'Required value missing for ' + labelOf(m.Target_Field__c) + ' on notice ' + n.Notice_Id__c
                    );
                }
                if (v != null) {
                    row.put(m.Target_Field__c, v);
                }
            }
            if (ownerId != null && targetFields.containsKey('ownerid')) {
                row.put('OwnerId', ownerId);
            }
            rows.add(row);
        }
        return rows;
    }

    public Map<String, Object> syncValues(NXP_Gov_Notice__c notice, Set<String> changedNoticeFields) {
        Map<String, Object> values = new Map<String, Object>();
        for (NXP_Push_Mapping__mdt m : mappings) {
            if (
                m.Sync_Behavior__c == 'Update' &&
                m.Source_Field__c != null &&
                contains(changedNoticeFields, m.Source_Field__c)
            ) {
                values.put(m.Target_Field__c, coerce(m.Target_Field__c, notice.get(m.Source_Field__c)));
            }
        }
        return values;
    }

    public List<String> alertOnlyChanges(Set<String> changedNoticeFields) {
        List<String> labels = new List<String>();
        for (NXP_Push_Mapping__mdt m : mappings) {
            if (
                m.Sync_Behavior__c == 'Alert Only' &&
                m.Source_Field__c != null &&
                contains(changedNoticeFields, m.Source_Field__c)
            ) {
                labels.add(labelOf(m.Target_Field__c));
            }
        }
        return labels;
    }

    private static Boolean contains(Set<String> fields, String field) {
        for (String f : fields) {
            if (f.equalsIgnoreCase(field)) {
                return true;
            }
        }
        return false;
    }

    private Object valueFor(NXP_Push_Mapping__mdt m, NXP_Gov_Notice__c n) {
        Object v = String.isBlank(m.Source_Field__c) ? null : n.get(m.Source_Field__c);
        if (v == null && String.isNotBlank(m.Default_Value__c)) {
            v = m.Default_Value__c;
        }
        return v;
    }

    /** Converts a value to the target field's type (DateTime -> Date for close dates, text truncation). */
    private Object coerce(String fieldName, Object v) {
        if (v == null) {
            return null;
        }
        Schema.SObjectField f = targetFields.get(fieldName.toLowerCase());
        if (f == null) {
            throw new IllegalArgumentException('Target field not found: ' + objectName + '.' + fieldName);
        }
        Schema.DescribeFieldResult d = f.getDescribe();
        switch on d.getType() {
            when DATE {
                if (v instanceof Datetime) {
                    return ((Datetime) v).date();
                }
                return v instanceof Date ? v : NXP_Json.toDate(String.valueOf(v));
            }
            when DATETIME {
                return v instanceof Datetime ? v : NXP_Json.toDateTime(String.valueOf(v));
            }
            when CURRENCY, DOUBLE, PERCENT, INTEGER {
                return v instanceof Decimal ? v : NXP_Json.toDecimal(String.valueOf(v));
            }
            when BOOLEAN {
                return v instanceof Boolean ? v : Boolean.valueOf(String.valueOf(v));
            }
            when STRING, TEXTAREA, PICKLIST, URL, EMAIL, PHONE {
                return NXP_Text.truncate(NXP_Text.valueToString(v), d.getLength() > 0 ? d.getLength() : 131072);
            }
            when else {
                return v;
            }
        }
    }

    private String labelOf(String fieldName) {
        Schema.SObjectField f = targetFields.get(fieldName.toLowerCase());
        return f == null ? fieldName : f.getDescribe().getLabel();
    }

    private static String display(Object v) {
        if (v == null) {
            return '';
        }
        if (v instanceof Datetime) {
            return ((Datetime) v).format('MMM d, yyyy h:mm a z');
        }
        if (v instanceof Decimal) {
            return ((Decimal) v).format();
        }
        return String.valueOf(v);
    }

    private static String syncLabel(String behavior) {
        switch on behavior {
            when 'Update' {
                return 'Yes, updates on amendment';
            }
            when 'Alert Only' {
                return 'Alert owner only';
            }
            when else {
                return 'No';
            }
        }
    }

    private static String mappingSet() {
        return NXP_Settings.getString('Push_Mapping_Set', 'Opportunity_Default');
    }

    private static List<NXP_Push_Mapping__mdt> loadMappings() {
        if (mappingOverride != null) {
            return mappingOverride;
        }
        String setName = mappingSet();
        List<NXP_Push_Mapping__mdt> rows = new List<NXP_Push_Mapping__mdt>();
        for (NXP_Push_Mapping__mdt m : NXP_Push_Mapping__mdt.getAll().values()) {
            if (m.Active__c && m.Mapping_Set__c == setName) {
                rows.add(m);
            }
        }
        return rows;
    }
}
