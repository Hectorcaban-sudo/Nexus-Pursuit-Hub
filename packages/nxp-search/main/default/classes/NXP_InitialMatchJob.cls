/**
 * Runs once when a saved search is created or saved again: matches it against the open notices
 * already in Nexus, so what the live preview showed appears in the Match Inbox. Normal matching
 * (NXP_SearchMatchService) only sees notices as they arrive or change.
 *
 * These existing notices are matched quietly: no alerts are sent (Alert_Status__c = Suppressed) and
 * auto-push is not triggered. AI summaries are requested for the best-fit matches, at most
 * Initial_Match_Max_Summaries, and their SAM.gov description text is fetched right away.
 */
public without sharing class NXP_InitialMatchJob implements Queueable {
    public static final String CHANGE_TYPE = 'Already open';
    private static final Integer MAX_ROWS = 2000;
    /** Most notices whose description is fetched because only the text can decide this search. */
    private static final Integer MAX_TEXT_REQUESTS = 100;

    private final Id searchId;

    public NXP_InitialMatchJob(Id searchId) {
        this.searchId = searchId;
    }

    public void execute(QueueableContext context) {
        try {
            run(searchId);
        } catch (Exception e) {
            NXP_Logger.warn(
                'NXP_InitialMatchJob',
                'Initial match failed for search ' + searchId + ': ' + e.getMessage()
            );
        }
        NXP_Logger.flush();
    }

    /** Returns the number of new matches created. */
    public static Integer run(Id searchId) {
        List<NXP_Saved_Search__c> rows = [
            SELECT Id, Criteria_JSON__c, Active__c
            FROM NXP_Saved_Search__c
            WHERE Id = :searchId
            LIMIT 1
        ];
        if (rows.isEmpty() || !rows[0].Active__c) {
            return 0;
        }
        NXP_SearchCriteria c = NXP_SearchCriteria.parse(rows[0].Criteria_JSON__c);
        NXP_SearchQueryBuilder q = new NXP_SearchQueryBuilder(c, false, null);
        List<NXP_Gov_Notice__c> candidates = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE)
            .whereClause(
                q.whereClause,
                q.binds,
                'Fit_Score__c DESC NULLS LAST, Response_Due__c ASC NULLS LAST',
                MAX_ROWS
            );

        // Best fit first, so the summary cap keeps the most relevant ones.
        List<NXP_Gov_Notice__c> matched = new List<NXP_Gov_Notice__c>();
        Map<String, NXP_Search_Match__c> byKey = new Map<String, NXP_Search_Match__c>();
        List<NXP_Gov_Notice__c> wantText = new List<NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : candidates) {
            NXP_SearchCriteria.MatchResult r;
            try {
                r = c.matches(n);
            } catch (Exception e) {
                continue;
            }
            if (!r.matched) {
                // Only the description can decide: fetch it, and normal matching runs when it arrives.
                if (r.needsDescription && n.Description_Requested__c != true && wantText.size() < MAX_TEXT_REQUESTS) {
                    wantText.add(new NXP_Gov_Notice__c(Id = n.Id, Description_Requested__c = true));
                }
                continue;
            }
            matched.add(n);
            String key = NXP_SearchMatchService.matchKey(searchId, n.Id);
            byKey.put(
                key,
                new NXP_Search_Match__c(
                    Saved_Search__c = searchId,
                    Gov_Notice__c = n.Id,
                    Match_Key__c = key,
                    Matched_Terms__c = NXP_Text.truncate(String.join(r.terms, ', '), 255),
                    Change_Type__c = CHANGE_TYPE,
                    Matched_At__c = Datetime.now(),
                    User_Action__c = 'None',
                    Alert_Status__c = 'Suppressed'
                )
            );
        }
        if (!wantText.isEmpty()) {
            NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
            Database.update(wantText, false, AccessLevel.SYSTEM_MODE);
            NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
        }
        if (matched.isEmpty()) {
            if (!wantText.isEmpty()) {
                startDescriptionFetch(new Set<Id>());
            }
            return 0;
        }

        Set<String> keys = byKey.keySet();
        for (NXP_Search_Match__c m : [SELECT Match_Key__c FROM NXP_Search_Match__c WHERE Match_Key__c IN :keys]) {
            byKey.remove(m.Match_Key__c);
        }
        Database.insert(byKey.values(), false, AccessLevel.SYSTEM_MODE);

        Boolean fetchStarted = requestSummaries(matched);
        if (!wantText.isEmpty() && !fetchStarted) {
            startDescriptionFetch(new Set<Id>());
        }
        return byKey.size();
    }

    /** Returns true when it started the description fetch. */
    private static Boolean requestSummaries(List<NXP_Gov_Notice__c> matched) {
        Integer cap = NXP_Settings.getInteger('Initial_Match_Max_Summaries', 25);
        List<NXP_Gov_Notice__c> updates = new List<NXP_Gov_Notice__c>();
        Set<Id> needText = new Set<Id>();
        for (NXP_Gov_Notice__c n : matched) {
            if (updates.size() >= cap) {
                break;
            }
            if (n.AI_Summary_Status__c == null || n.AI_Summary_Status__c == 'Not Requested') {
                updates.add(new NXP_Gov_Notice__c(Id = n.Id, AI_Summary_Status__c = 'Pending'));
                if (n.Needs_Description__c == true) {
                    needText.add(n.Id);
                }
            }
        }
        if (!updates.isEmpty()) {
            NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
            Database.update(updates, false, AccessLevel.SYSTEM_MODE);
            NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
        }
        if (!needText.isEmpty()) {
            startDescriptionFetch(needText);
            return true;
        }
        return false;
    }

    /**
     * Fetches SAM.gov description text for the notices now waiting for a summary. The batch lives in
     * nxp-ingestion, which this package does not depend on, so it is found by name. Its default run
     * picks up every notice with a summary requested, including these.
     */
    private static void startDescriptionFetch(Set<Id> noticeIds) {
        Type t = Type.forName('NXP_NoticeEnrichBatch');
        if (t == null || Test.isRunningTest()) {
            return;
        }
        try {
            Database.executeBatch((Database.Batchable<SObject>) t.newInstance(), 20);
        } catch (Exception e) {
            NXP_Logger.warn('NXP_InitialMatchJob', 'Could not start the description fetch: ' + e.getMessage());
        }
    }
}
