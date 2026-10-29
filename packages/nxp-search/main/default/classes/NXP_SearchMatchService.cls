/**
 * Runs every new or changed notice against every active saved search (event-driven, called from
 * the NXP_Gov_Notice_Changed__e trigger), records Search Matches, sends real-time and follow
 * alerts, and notifies match listeners (auto-push).
 */
public without sharing class NXP_SearchMatchService {
    public static final String SEARCH_FIELDS =
        'Id, Name, OwnerId, Criteria_JSON__c, Alert_Frequency__c, Channels__c, Alert_On_Changes__c, ' +
        'Auto_Push__c, Auto_Push_Min_Fit__c, Active__c, Visibility__c';

    public static void handleEvents(List<NXP_Gov_Notice_Changed__e> events) {
        Map<Id, String> changeTypes = new Map<Id, String>();
        Set<Id> newIds = new Set<Id>();
        for (NXP_Gov_Notice_Changed__e e : events) {
            if (String.isBlank(e.Notice_Record_Id__c)) {
                continue;
            }
            Id noticeId = Id.valueOf(e.Notice_Record_Id__c);
            changeTypes.put(noticeId, e.Change_Type__c);
            if (e.Is_New__c) {
                newIds.add(noticeId);
            }
        }
        if (!changeTypes.isEmpty()) {
            process(changeTypes, newIds);
        }
        // Watches on forecasts and awards (released forecast, possible follow-on). Never throws.
        NXP_WatchService.noticesCreated(newIds);
    }

    public static List<NXP_Search_Match__c> process(Map<Id, String> changeTypes, Set<Id> newIds) {
        List<NXP_Gov_Notice__c> notices = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE)
            .byIds(changeTypes.keySet());
        List<NXP_Saved_Search__c> searches = Database.query(
            'SELECT ' + SEARCH_FIELDS + ' FROM NXP_Saved_Search__c WHERE Active__c = TRUE LIMIT 20000'
        );
        Map<Id, NXP_Saved_Search__c> searchById = new Map<Id, NXP_Saved_Search__c>(searches);
        Map<Id, NXP_SearchCriteria> criteria = new Map<Id, NXP_SearchCriteria>();
        for (NXP_Saved_Search__c s : searches) {
            try {
                criteria.put(s.Id, NXP_SearchCriteria.parse(s.Criteria_JSON__c));
            } catch (Exception e) {
                NXP_Logger.warn(
                    'NXP_SearchMatchService',
                    'Skipping search ' + s.Id + ' with invalid criteria: ' + e.getMessage()
                );
            }
        }

        Set<String> keys = new Set<String>();
        Map<String, NXP_Search_Match__c> candidates = new Map<String, NXP_Search_Match__c>();
        for (NXP_Gov_Notice__c n : notices) {
            for (Id searchId : criteria.keySet()) {
                NXP_SearchCriteria.MatchResult r;
                try {
                    r = criteria.get(searchId).matches(n);
                } catch (Exception e) {
                    continue;
                }
                if (!r.matched) {
                    continue;
                }
                String key = matchKey(searchId, n.Id);
                keys.add(key);
                candidates.put(
                    key,
                    new NXP_Search_Match__c(
                        Saved_Search__c = searchId,
                        Gov_Notice__c = n.Id,
                        Match_Key__c = key,
                        Matched_Terms__c = NXP_Text.truncate(String.join(r.terms, ', '), 255),
                        Change_Type__c = NXP_Text.truncate(newIds.contains(n.Id) ? 'New' : changeTypes.get(n.Id), 255)
                    )
                );
            }
        }

        Map<String, NXP_Search_Match__c> existing = new Map<String, NXP_Search_Match__c>();
        if (!keys.isEmpty()) {
            for (NXP_Search_Match__c m : [
                SELECT Id, Match_Key__c, User_Action__c, Alert_Status__c
                FROM NXP_Search_Match__c
                WHERE Match_Key__c IN :keys
            ]) {
                existing.put(m.Match_Key__c, m);
            }
        }

        List<NXP_Search_Match__c> toInsert = new List<NXP_Search_Match__c>();
        List<NXP_Search_Match__c> toUpdate = new List<NXP_Search_Match__c>();
        for (String key : candidates.keySet()) {
            NXP_Search_Match__c m = candidates.get(key);
            NXP_Saved_Search__c s = searchById.get(m.Saved_Search__c);
            NXP_Search_Match__c prior = existing.get(key);
            Boolean silent = s.Alert_Frequency__c == 'None';
            if (prior == null) {
                m.Matched_At__c = Datetime.now();
                m.User_Action__c = 'None';
                m.Alert_Status__c = silent ? 'Suppressed' : 'Pending';
                toInsert.add(m);
            } else if (s.Alert_On_Changes__c && prior.User_Action__c != 'Dismissed' && m.Change_Type__c != 'New') {
                // Update only what changed: the master-detail field cannot be re-sent on update.
                toUpdate.add(
                    new NXP_Search_Match__c(
                        Id = prior.Id,
                        Change_Type__c = m.Change_Type__c,
                        Matched_Terms__c = m.Matched_Terms__c,
                        Alert_Status__c = silent ? 'Suppressed' : 'Pending'
                    )
                );
                // Keep lookups on the in-memory copy for alerts and listeners.
                m.Id = prior.Id;
                m.Alert_Status__c = silent ? 'Suppressed' : 'Pending';
                m.User_Action__c = prior.User_Action__c;
            }
        }
        Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        List<NXP_Search_Match__c> toSave = new List<NXP_Search_Match__c>();
        for (NXP_Search_Match__c m : candidates.values()) {
            if (m.Id != null) {
                toSave.add(m);
            }
        }

        requestSummaries(toSave, notices);
        Map<Id, NXP_Gov_Notice__c> noticeById = new Map<Id, NXP_Gov_Notice__c>(notices);
        NXP_AlertService.sendRealTime(toSave, searchById, noticeById);
        NXP_AlertService.sendFollowAlerts(changeTypes, newIds, noticeById);
        notifyListeners(toSave);
        NXP_Logger.flush();
        return toSave;
    }

    public static String matchKey(Id searchId, Id noticeId) {
        return String.valueOf(searchId) + '-' + String.valueOf(noticeId);
    }

    /** Marks matched notices for the Notice Analyst (AI summary) background job. */
    private static void requestSummaries(List<NXP_Search_Match__c> matches, List<NXP_Gov_Notice__c> notices) {
        Set<Id> matched = new Set<Id>();
        for (NXP_Search_Match__c m : matches) {
            matched.add(m.Gov_Notice__c);
        }
        List<NXP_Gov_Notice__c> updates = new List<NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : notices) {
            if (
                matched.contains(n.Id) && (n.AI_Summary_Status__c == null || n.AI_Summary_Status__c == 'Not Requested')
            ) {
                updates.add(new NXP_Gov_Notice__c(Id = n.Id, AI_Summary_Status__c = 'Pending'));
            }
        }
        if (!updates.isEmpty()) {
            NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
            Database.update(updates, false, AccessLevel.SYSTEM_MODE);
            NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
        }
    }

    private static void notifyListeners(List<NXP_Search_Match__c> matches) {
        if (matches.isEmpty()) {
            return;
        }
        for (String className : NXP_Text.splitList(NXP_Settings.getString('Match_Listeners', ''))) {
            Type t = Type.forName(className);
            if (t == null) {
                continue;
            }
            try {
                ((NXP_MatchListener) t.newInstance()).onMatches(matches);
            } catch (Exception e) {
                NXP_Logger.error('NXP_SearchMatchService', 'Match listener ' + className + ' failed', e, null);
            }
        }
    }
}
