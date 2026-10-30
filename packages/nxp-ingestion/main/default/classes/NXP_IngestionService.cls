/**
 * The single processing path for every channel (standard pipeline, scheduled batch, Apex REST,
 * Data Cloud follow-ups, manual imports):
 *   normalize -> resolve agency/vehicle -> dedupe -> version -> DML -> contacts -> publish change event.
 * Fit scoring happens in the Gov Notice trigger. Runs in system mode: callers check access.
 */
public without sharing class NXP_IngestionService {
    /** Fields whose change makes a new Notice Version (an amendment). */
    public static final List<String> TRACKED_FIELDS = new List<String>{
        'Title__c',
        'Notice_Type__c',
        'Status__c',
        'NAICS_Code__c',
        'PSC_Code__c',
        'Set_Aside__c',
        'Response_Due__c',
        'Estimated_Value__c',
        'Archive_Date__c',
        'Place_Of_Performance__c',
        'Description__c'
    };

    private static final Map<String, String> CHANGE_TYPES = new Map<String, String>{
        'Response_Due__c' => 'Due date',
        'Set_Aside__c' => 'Set-aside',
        'NAICS_Code__c' => 'Classification',
        'PSC_Code__c' => 'Classification',
        'Title__c' => 'Scope',
        'Description__c' => 'Scope',
        'Status__c' => 'Status',
        'Estimated_Value__c' => 'Value',
        'Notice_Type__c' => 'Notice type',
        'Archive_Date__c' => 'Archive date',
        'Place_Of_Performance__c' => 'Place of performance'
    };

    public class RecordResult {
        public String sourceId;
        public String externalKey;
        public String status; // Created, Updated, Unchanged, Rejected
        public Id recordId;
        public String message;
    }

    public class Result {
        public Integer read = 0;
        public Integer created = 0;
        public Integer updated = 0;
        public Integer unchanged = 0;
        public Integer rejected = 0;
        public List<RecordResult> results = new List<RecordResult>();
        public Set<Id> changedNoticeIds = new Set<Id>();
        public List<String> errors = new List<String>();

        public void add(Result other) {
            read += other.read;
            created += other.created;
            updated += other.updated;
            unchanged += other.unchanged;
            rejected += other.rejected;
            results.addAll(other.results);
            changedNoticeIds.addAll(other.changedNoticeIds);
            errors.addAll(other.errors);
        }
    }

    public static Result ingest(List<NXP_IngestRecord> records) {
        Result result = new Result();
        if (records == null || records.isEmpty()) {
            return result;
        }
        result.read = records.size();
        Map<String, List<NXP_IngestRecord>> byType = new Map<String, List<NXP_IngestRecord>>();
        for (NXP_IngestRecord rec : records) {
            if (!byType.containsKey(rec.recordType)) {
                byType.put(rec.recordType, new List<NXP_IngestRecord>());
            }
            byType.get(rec.recordType).add(rec);
        }
        Map<String, NXP_AgencyResolver.Resolved> agencies = NXP_AgencyResolver.resolve(records);

        if (byType.containsKey(NXP_IngestRecord.TYPE_VENDOR)) {
            upsertSimple(
                byType.get(NXP_IngestRecord.TYPE_VENDOR),
                NXP_Gov_Vendor__c.SObjectType,
                NXP_Gov_Vendor__c.UEI__c,
                agencies,
                result
            );
        }
        if (byType.containsKey(NXP_IngestRecord.TYPE_AWARD)) {
            upsertAwards(byType.get(NXP_IngestRecord.TYPE_AWARD), agencies, result);
        }
        if (byType.containsKey(NXP_IngestRecord.TYPE_FORECAST)) {
            upsertSimple(
                byType.get(NXP_IngestRecord.TYPE_FORECAST),
                NXP_Gov_Forecast__c.SObjectType,
                NXP_Gov_Forecast__c.Forecast_Id__c,
                agencies,
                result
            );
        }
        if (byType.containsKey(NXP_IngestRecord.TYPE_NOTICE)) {
            ingestNotices(byType.get(NXP_IngestRecord.TYPE_NOTICE), agencies, result);
        }
        return result;
    }

    /** Stable hash of the tracked fields. A description that is still a link is ignored. */
    public static String computeHash(SObject n) {
        List<String> parts = new List<String>();
        for (String f : TRACKED_FIELDS) {
            Object v = n.get(f);
            if (f == 'Description__c' && v != null && String.valueOf(v).startsWithIgnoreCase('http')) {
                v = null;
            }
            parts.add(f + '=' + NXP_Text.valueToString(v));
        }
        return NXP_Text.sha256(String.join(parts, '|'));
    }

    public static String normalizeNoticeType(String value) {
        return NXP_SamOpportunityConnector.normalizeType(value);
    }

    // ---------------------------------------------------------------- notices

    private static void ingestNotices(
        List<NXP_IngestRecord> records,
        Map<String, NXP_AgencyResolver.Resolved> agencies,
        Result result
    ) {
        Map<String, Id> vehicles = vehicleIds(records);
        List<NXP_IngestRecord> valid = new List<NXP_IngestRecord>();
        List<NXP_Gov_Notice__c> candidates = new List<NXP_Gov_Notice__c>();

        for (NXP_IngestRecord rec : records) {
            NXP_Gov_Notice__c n = new NXP_Gov_Notice__c();
            String error = applyValues(n, rec);
            if (String.isBlank(rec.externalKey)) {
                error = 'Missing notice ID';
            }
            if (error != null) {
                reject(rec, error, result);
                continue;
            }
            n.Notice_Id__c = rec.externalKey;
            NXP_AgencyResolver.Resolved agency = agencies.get(NXP_AgencyResolver.keyFor(rec));
            if (agency != null) {
                n.Agency__c = agency.agencyId;
                n.Agency_Path__c = agency.displayPath;
                if (String.isBlank(n.Office__c)) {
                    n.Office__c = NXP_Text.truncate(agency.leafName, 255);
                }
            }
            if (String.isNotBlank(rec.vehicleCode) && vehicles.containsKey(rec.vehicleCode.toUpperCase())) {
                n.Contract_Vehicle__c = vehicles.get(rec.vehicleCode.toUpperCase());
            }
            valid.add(rec);
            candidates.add(n);
        }
        if (candidates.isEmpty()) {
            return;
        }

        Map<String, NXP_Gov_Notice__c> existingByKey = findExisting(candidates);
        List<NXP_Gov_Notice__c> toInsert = new List<NXP_Gov_Notice__c>();
        List<NXP_IngestRecord> insertRecs = new List<NXP_IngestRecord>();
        List<NXP_Gov_Notice__c> toUpdate = new List<NXP_Gov_Notice__c>();
        List<NXP_IngestRecord> updateRecs = new List<NXP_IngestRecord>();
        Map<Id, NXP_Notice_Version__c> pendingVersions = new Map<Id, NXP_Notice_Version__c>();

        for (Integer i = 0; i < candidates.size(); i++) {
            NXP_Gov_Notice__c n = candidates[i];
            NXP_IngestRecord rec = valid[i];
            NXP_Gov_Notice__c existing = existingByKey.get(n.Notice_Id__c);
            if (existing == null && String.isNotBlank(n.Solicitation_Number__c)) {
                existing = existingByKey.get('SOL:' + n.Solicitation_Number__c.toUpperCase());
            }
            if (existing == null) {
                prepareNew(n, rec);
                toInsert.add(n);
                insertRecs.add(rec);
                continue;
            }
            // Fields we must not send on update: the existing Notice ID (a notice matched by
            // solicitation number from another source keeps its own) and, once fetched, the
            // description text (never replace it with the SAM.gov link again).
            Set<String> skip = new Set<String>{ 'notice_id__c' };
            if (
                n.Description__c != null &&
                n.Description__c.startsWithIgnoreCase('http') &&
                String.isNotBlank(existing.Description__c) &&
                !existing.Description__c.startsWithIgnoreCase('http')
            ) {
                skip.add('description__c');
                skip.add('needs_description__c');
            }
            // New SAM.gov attachments are saved even when no tracked field changed (no new version);
            // unchanged links leave the files flags alone.
            Boolean linksChanged = n.Resource_Links__c != null && n.Resource_Links__c != existing.Resource_Links__c;
            if (!linksChanged) {
                skip.add('resource_links__c');
                skip.add('files_pending__c');
            }
            NXP_Gov_Notice__c upd = new NXP_Gov_Notice__c(Id = existing.Id);
            NXP_Gov_Notice__c merged = existing.clone(true, true, false, false);
            Map<String, Object> populated = n.getPopulatedFieldsAsMap();
            for (String f : populated.keySet()) {
                if (!skip.contains(f.toLowerCase())) {
                    upd.put(f, populated.get(f));
                    merged.put(f, populated.get(f));
                }
            }
            String newHash = computeHash(merged);
            String lineage = appendLineage(existing.Source_Lineage__c, rec.sourceFeed);
            if (newHash == existing.Content_Hash__c && lineage == existing.Source_Lineage__c && !linksChanged) {
                result.unchanged++;
                result.results.add(recordResult(rec, 'Unchanged', existing.Id, null));
                continue;
            }
            upd.Source_Lineage__c = lineage;
            if (newHash != existing.Content_Hash__c) {
                List<String> changed = changedFields(existing, merged);
                Integer version = (existing.Version_Count__c == null ? 1 : existing.Version_Count__c.intValue()) + 1;
                upd.Content_Hash__c = newHash;
                upd.Version_Count__c = version;
                upd.Last_Change_Type__c = NXP_Text.truncate(changeTypes(changed, merged), 255);
                upd.Last_Changed__c = Datetime.now();
                pendingVersions.put(existing.Id, buildVersion(existing.Id, version, changed, existing, merged));
            }
            toUpdate.add(upd);
            updateRecs.add(rec);
        }

        List<NXP_Gov_Notice_Changed__e> events = new List<NXP_Gov_Notice_Changed__e>();
        List<NXP_Notice_Version__c> versions = new List<NXP_Notice_Version__c>();
        Map<Id, NXP_IngestRecord> contactsFor = new Map<Id, NXP_IngestRecord>();

        Database.SaveResult[] inserted = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < inserted.size(); i++) {
            NXP_IngestRecord rec = insertRecs[i];
            if (inserted[i].isSuccess()) {
                Id noticeId = inserted[i].getId();
                result.created++;
                result.changedNoticeIds.add(noticeId);
                result.results.add(recordResult(rec, 'Created', noticeId, null));
                versions.add(buildVersion(noticeId, 1, new List<String>(), null, toInsert[i]));
                events.add(event(noticeId, 'New', true, rec.sourceFeed));
                contactsFor.put(noticeId, rec);
            } else {
                reject(rec, errorText(inserted[i].getErrors()), result);
            }
        }

        Database.SaveResult[] updated = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < updated.size(); i++) {
            NXP_IngestRecord rec = updateRecs[i];
            if (updated[i].isSuccess()) {
                Id noticeId = updated[i].getId();
                result.updated++;
                result.results.add(recordResult(rec, 'Updated', noticeId, null));
                contactsFor.put(noticeId, rec);
                if (pendingVersions.containsKey(noticeId)) {
                    versions.add(pendingVersions.get(noticeId));
                    result.changedNoticeIds.add(noticeId);
                    events.add(event(noticeId, toUpdate[i].Last_Change_Type__c, false, rec.sourceFeed));
                }
            } else {
                reject(rec, errorText(updated[i].getErrors()), result);
            }
        }

        if (!versions.isEmpty()) {
            Database.insert(versions, false, AccessLevel.SYSTEM_MODE);
        }
        upsertContacts(contactsFor);
        linkForecasts(toInsert);
        if (!events.isEmpty()) {
            EventBus.publish(events);
        }
    }

    private static void prepareNew(NXP_Gov_Notice__c n, NXP_IngestRecord rec) {
        if (String.isBlank(n.Status__c)) {
            n.Status__c = 'Active';
        }
        if (String.isBlank(n.Market__c)) {
            n.Market__c = 'Federal';
        }
        if (String.isBlank(n.Source_Feed__c)) {
            n.Source_Feed__c = rec.sourceFeed;
        }
        n.Source_Lineage__c = appendLineage(null, rec.sourceFeed);
        n.Version_Count__c = 1;
        n.Content_Hash__c = computeHash(n);
        n.Last_Change_Type__c = 'New';
        n.Last_Changed__c = Datetime.now();
        n.AI_Summary_Status__c = 'Not Requested';
    }

    private static Map<String, NXP_Gov_Notice__c> findExisting(List<NXP_Gov_Notice__c> candidates) {
        Set<String> keys = new Set<String>();
        Set<String> sols = new Set<String>();
        for (NXP_Gov_Notice__c n : candidates) {
            keys.add(n.Notice_Id__c);
            if (String.isNotBlank(n.Solicitation_Number__c)) {
                sols.add(n.Solicitation_Number__c);
            }
        }
        NXP_GovNoticeSelector selector = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE);
        Map<String, NXP_Gov_Notice__c> byKey = new Map<String, NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : selector.byNoticeIds(keys)) {
            byKey.put(n.Notice_Id__c, n);
        }
        if (!sols.isEmpty()) {
            for (NXP_Gov_Notice__c n : selector.bySolicitationNumbers(sols)) {
                String solKey = 'SOL:' + n.Solicitation_Number__c.toUpperCase();
                // Prefer the most recently changed record when several share a solicitation number.
                if (!byKey.containsKey(solKey) || n.Last_Changed__c > byKey.get(solKey).Last_Changed__c) {
                    byKey.put(solKey, n);
                }
            }
        }
        return byKey;
    }

    private static List<String> changedFields(NXP_Gov_Notice__c before, NXP_Gov_Notice__c after) {
        List<String> changed = new List<String>();
        for (String f : TRACKED_FIELDS) {
            Object a = before.get(f);
            Object b = after.get(f);
            if (f == 'Description__c' && b != null && String.valueOf(b).startsWithIgnoreCase('http')) {
                continue;
            }
            if (NXP_Text.valueToString(a) != NXP_Text.valueToString(b)) {
                changed.add(f);
            }
        }
        return changed;
    }

    private static String changeTypes(List<String> changed, NXP_Gov_Notice__c after) {
        List<String> types = new List<String>();
        for (String f : changed) {
            String t = CHANGE_TYPES.get(f);
            if (t != null && !types.contains(t)) {
                types.add(t);
            }
        }
        if (after.Notice_Type__c == 'Award Notice' && !types.contains('Award')) {
            types.add('Award');
        }
        return types.isEmpty() ? 'Updated' : String.join(types, ', ');
    }

    private static NXP_Notice_Version__c buildVersion(
        Id noticeId,
        Integer version,
        List<String> changed,
        NXP_Gov_Notice__c before,
        NXP_Gov_Notice__c after
    ) {
        Map<String, Object> snapshot = new Map<String, Object>();
        for (String f : TRACKED_FIELDS) {
            if (f != 'Description__c') {
                snapshot.put(f, after.get(f));
            }
        }
        List<String> diffs = new List<String>();
        for (String f : changed) {
            String label = Schema.SObjectType.NXP_Gov_Notice__c.fields.getMap().get(f).getDescribe().getLabel();
            if (f == 'Description__c') {
                diffs.add(label + ' updated');
            } else {
                diffs.add(label + ': ' + display(before.get(f)) + ' → ' + display(after.get(f)));
            }
        }
        return new NXP_Notice_Version__c(
            Gov_Notice__c = noticeId,
            Version_Number__c = version,
            Change_Type__c = before == null ? 'Original' : NXP_Text.truncate(changeTypes(changed, after), 255),
            Changed_Fields__c = String.join(changed, ', '),
            Diff_Summary__c = before == null
                ? 'First version received.'
                : NXP_Text.truncate(String.join(diffs, '\n'), 32768),
            Snapshot__c = NXP_Text.truncate(JSON.serialize(snapshot), 131072)
        );
    }

    private static String display(Object v) {
        return v == null ? '(blank)' : NXP_Text.valueToString(v);
    }

    private static String appendLineage(String lineageJson, String feed) {
        List<String> feeds = String.isBlank(lineageJson)
            ? new List<String>()
            : (List<String>) JSON.deserialize(lineageJson, List<String>.class);
        if (String.isNotBlank(feed) && !feeds.contains(feed)) {
            feeds.add(feed);
        }
        return JSON.serialize(feeds);
    }

    private static Map<String, Id> vehicleIds(List<NXP_IngestRecord> records) {
        Set<String> codes = new Set<String>();
        for (NXP_IngestRecord rec : records) {
            if (String.isNotBlank(rec.vehicleCode)) {
                codes.add(rec.vehicleCode);
            }
        }
        Map<String, Id> ids = new Map<String, Id>();
        if (!codes.isEmpty()) {
            for (NXP_Contract_Vehicle__c v : [
                SELECT Id, Vehicle_Code__c
                FROM NXP_Contract_Vehicle__c
                WHERE Vehicle_Code__c IN :codes
            ]) {
                ids.put(v.Vehicle_Code__c.toUpperCase(), v.Id);
            }
        }
        return ids;
    }

    private static void upsertContacts(Map<Id, NXP_IngestRecord> recsByNotice) {
        List<NXP_Gov_Contact__c> contacts = new List<NXP_Gov_Contact__c>();
        for (Id noticeId : recsByNotice.keySet()) {
            NXP_IngestRecord rec = recsByNotice.get(noticeId);
            for (NXP_IngestRecord.ContactInfo c : rec.contacts) {
                String who = String.isNotBlank(c.email) ? c.email.toLowerCase() : c.fullName;
                contacts.add(
                    new NXP_Gov_Contact__c(
                        Name = NXP_Text.truncate(String.isBlank(c.fullName) ? c.email : c.fullName, 80),
                        Gov_Notice__c = noticeId,
                        Email__c = c.email,
                        Phone__c = NXP_Text.truncate(c.phone, 40),
                        Role__c = String.isBlank(c.role) ? 'Other' : c.role,
                        Contact_Key__c = NXP_Text.truncate(rec.externalKey + '|' + who, 255)
                    )
                );
            }
        }
        if (!contacts.isEmpty()) {
            Database.upsert(contacts, NXP_Gov_Contact__c.Contact_Key__c, false, AccessLevel.SYSTEM_MODE);
        }
    }

    /** Links a new solicitation to an open forecast at the same agency and NAICS with a similar title. */
    private static void linkForecasts(List<NXP_Gov_Notice__c> inserted) {
        Map<Id, List<NXP_Gov_Notice__c>> byAgency = new Map<Id, List<NXP_Gov_Notice__c>>();
        for (NXP_Gov_Notice__c n : inserted) {
            if (n.Id != null && n.Agency__c != null && n.Forecast__c == null) {
                if (!byAgency.containsKey(n.Agency__c)) {
                    byAgency.put(n.Agency__c, new List<NXP_Gov_Notice__c>());
                }
                byAgency.get(n.Agency__c).add(n);
            }
        }
        if (byAgency.isEmpty()) {
            return;
        }
        Set<Id> agencyIds = byAgency.keySet();
        List<NXP_Gov_Forecast__c> forecasts = [
            SELECT Id, Name, Agency__c, NAICS_Code__c
            FROM NXP_Gov_Forecast__c
            WHERE Matched_Notice__c = NULL AND Agency__c IN :agencyIds
            LIMIT 2000
        ];
        List<NXP_Gov_Notice__c> noticeUpdates = new List<NXP_Gov_Notice__c>();
        List<NXP_Gov_Forecast__c> forecastUpdates = new List<NXP_Gov_Forecast__c>();
        Set<Id> used = new Set<Id>();
        for (NXP_Gov_Forecast__c f : forecasts) {
            for (NXP_Gov_Notice__c n : byAgency.get(f.Agency__c)) {
                if (used.contains(n.Id) || (f.NAICS_Code__c != null && f.NAICS_Code__c != n.NAICS_Code__c)) {
                    continue;
                }
                if (similarity(f.Name, n.Title__c) >= 0.5) {
                    noticeUpdates.add(new NXP_Gov_Notice__c(Id = n.Id, Forecast__c = f.Id));
                    forecastUpdates.add(new NXP_Gov_Forecast__c(Id = f.Id, Matched_Notice__c = n.Id));
                    used.add(n.Id);
                    break;
                }
            }
        }
        if (!noticeUpdates.isEmpty()) {
            Database.update(noticeUpdates, false, AccessLevel.SYSTEM_MODE);
            Database.update(forecastUpdates, false, AccessLevel.SYSTEM_MODE);
        }
    }

    @TestVisible
    private static Decimal similarity(String a, String b) {
        Set<String> wa = words(a);
        Set<String> wb = words(b);
        if (wa.isEmpty() || wb.isEmpty()) {
            return 0;
        }
        Integer shared = 0;
        for (String w : wa) {
            if (wb.contains(w)) {
                shared++;
            }
        }
        return Decimal.valueOf(shared) / Math.min(wa.size(), wb.size());
    }

    private static Set<String> words(String s) {
        Set<String> out = new Set<String>();
        if (s == null) {
            return out;
        }
        for (String w : s.toLowerCase().split('[^a-z0-9]+')) {
            if (w.length() > 3) {
                out.add(w);
            }
        }
        return out;
    }

    // ---------------------------------------------------------- other types

    private static void upsertSimple(
        List<NXP_IngestRecord> records,
        SObjectType type,
        SObjectField key,
        Map<String, NXP_AgencyResolver.Resolved> agencies,
        Result result
    ) {
        List<SObject> rows = new List<SObject>();
        List<NXP_IngestRecord> recs = new List<NXP_IngestRecord>();
        for (NXP_IngestRecord rec : records) {
            SObject row = type.newSObject();
            String error = applyValues(row, rec);
            if (error == null && String.isBlank(rec.externalKey)) {
                error = 'Missing external key';
            }
            if (error != null) {
                reject(rec, error, result);
                continue;
            }
            row.put(key, rec.externalKey);
            NXP_AgencyResolver.Resolved agency = agencies.get(NXP_AgencyResolver.keyFor(rec));
            if (agency != null && type.getDescribe().fields.getMap().containsKey('agency__c')) {
                row.put('Agency__c', agency.agencyId);
            }
            if (row.get('Name') == null) {
                row.put('Name', NXP_Text.truncate(rec.externalKey, 80));
            }
            rows.add(row);
            recs.add(rec);
        }
        Database.UpsertResult[] saved = Database.upsert(rows, key, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                if (saved[i].isCreated()) {
                    result.created++;
                } else {
                    result.updated++;
                }
                result.results.add(
                    recordResult(recs[i], saved[i].isCreated() ? 'Created' : 'Updated', saved[i].getId(), null)
                );
            } else {
                reject(recs[i], errorText(saved[i].getErrors()), result);
            }
        }
    }

    private static void upsertAwards(
        List<NXP_IngestRecord> records,
        Map<String, NXP_AgencyResolver.Resolved> agencies,
        Result result
    ) {
        Map<String, NXP_Gov_Vendor__c> vendors = new Map<String, NXP_Gov_Vendor__c>();
        for (NXP_IngestRecord rec : records) {
            if (String.isNotBlank(rec.vendorUei) && !vendors.containsKey(rec.vendorUei)) {
                vendors.put(
                    rec.vendorUei,
                    new NXP_Gov_Vendor__c(
                        UEI__c = rec.vendorUei,
                        Name = NXP_Text.truncate(String.isBlank(rec.vendorName) ? rec.vendorUei : rec.vendorName, 80)
                    )
                );
            }
        }
        if (!vendors.isEmpty()) {
            // Only create unknown vendors; never overwrite SAM Entity data with award-feed names.
            for (NXP_Gov_Vendor__c existing : [
                SELECT UEI__c
                FROM NXP_Gov_Vendor__c
                WHERE UEI__c IN :vendors.keySet()
            ]) {
                vendors.remove(existing.UEI__c);
            }
            Database.insert(vendors.values(), false, AccessLevel.SYSTEM_MODE);
        }
        for (NXP_IngestRecord rec : records) {
            if (String.isNotBlank(rec.vendorUei)) {
                rec.values.put('Vendor__r', new NXP_Gov_Vendor__c(UEI__c = rec.vendorUei));
            }
        }
        upsertSimple(records, NXP_Award_Summary__c.SObjectType, NXP_Award_Summary__c.PIID__c, agencies, result);
    }

    // ---------------------------------------------------------------- helpers

    private static String applyValues(SObject row, NXP_IngestRecord rec) {
        for (String field : rec.values.keySet()) {
            Object value = rec.values.get(field);
            try {
                if (field.endsWith('__r')) {
                    row.putSObject(field, (SObject) value);
                } else {
                    row.put(field, fit(row.getSObjectType(), field, value));
                }
            } catch (Exception e) {
                return 'Field ' + field + ': ' + e.getMessage();
            }
        }
        return null;
    }

    /** Coerces and truncates a value to the target field's type and length. */
    private static Object fit(SObjectType type, String field, Object value) {
        if (value == null) {
            return null;
        }
        Schema.SObjectField f = type.getDescribe().fields.getMap().get(field.toLowerCase());
        if (f == null) {
            throw new IllegalArgumentException('unknown field');
        }
        Schema.DescribeFieldResult d = f.getDescribe();
        switch on d.getType() {
            when STRING, TEXTAREA, PHONE, URL, EMAIL, PICKLIST {
                return NXP_Text.truncate(String.valueOf(value), d.getLength());
            }
            when DATE {
                return value instanceof Date ? value : NXP_Json.toDate(String.valueOf(value));
            }
            when DATETIME {
                return value instanceof Datetime ? value : NXP_Json.toDateTime(String.valueOf(value));
            }
            when CURRENCY, DOUBLE, PERCENT, INTEGER {
                return value instanceof Decimal ? value : NXP_Json.toDecimal(String.valueOf(value));
            }
            when BOOLEAN {
                return value instanceof Boolean ? value : Boolean.valueOf(String.valueOf(value));
            }
            when else {
                return value;
            }
        }
    }

    private static NXP_Gov_Notice_Changed__e event(Id noticeId, String changeType, Boolean isNew, String feed) {
        return new NXP_Gov_Notice_Changed__e(
            Notice_Record_Id__c = noticeId,
            Change_Type__c = NXP_Text.truncate(changeType, 255),
            Is_New__c = isNew,
            Source_Feed__c = NXP_Text.truncate(feed, 80)
        );
    }

    private static RecordResult recordResult(NXP_IngestRecord rec, String status, Id recordId, String message) {
        RecordResult r = new RecordResult();
        r.sourceId = rec.sourceId;
        r.externalKey = rec.externalKey;
        r.status = status;
        r.recordId = recordId;
        r.message = message;
        return r;
    }

    private static void reject(NXP_IngestRecord rec, String message, Result result) {
        result.rejected++;
        result.results.add(recordResult(rec, 'Rejected', null, message));
        result.errors.add((rec.externalKey == null ? rec.sourceId : rec.externalKey) + ': ' + message);
    }

    private static String errorText(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error e : errors) {
            parts.add(e.getMessage());
        }
        return String.join(parts, '; ');
    }
}
