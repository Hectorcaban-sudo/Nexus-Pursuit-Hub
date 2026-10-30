/**
 * Search Builder, My Searches and Match Inbox (nxpSearchBuilder, nxpMatchInbox LWCs).
 * Runs in user mode: users see only notices, searches and matches they have access to.
 */
public with sharing class NXP_SearchController {
    public class SearchSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String frequency;
        @AuraEnabled
        public String visibility;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public Boolean mine;
        @AuraEnabled
        public String autoPush;
        @AuraEnabled
        public Integer newCount = 0;
        @AuraEnabled
        public String description;
    }

    public class SearchInput {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String criteriaJson { get; set; }
        @AuraEnabled
        public String visibility { get; set; }
        @AuraEnabled
        public String teamGroup { get; set; }
        @AuraEnabled
        public String frequency { get; set; }
        @AuraEnabled
        public List<String> channels { get; set; }
        @AuraEnabled
        public Boolean alertOnChanges { get; set; }
        @AuraEnabled
        public String autoPush { get; set; }
        @AuraEnabled
        public Decimal autoPushMinFit { get; set; }
        @AuraEnabled
        public Boolean active { get; set; }
        /** Set when the search is created with Use template. */
        @AuraEnabled
        public Id templateId { get; set; }
    }

    /** An org template on My Searches: what it finds now and how many people copied it. */
    public class TemplateSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String ownerName;
        @AuraEnabled
        public Integer matchCount = 0;
        @AuraEnabled
        public Boolean capped = false;
        @AuraEnabled
        public Integer usedBy = 0;
    }

    public class Preview {
        @AuraEnabled
        public Integer count = 0;
        @AuraEnabled
        public Boolean capped = false;
        @AuraEnabled
        public List<NXP_Gov_Notice__c> top = new List<NXP_Gov_Notice__c>();
        @AuraEnabled
        public List<Integer> weekly = new List<Integer>();
        @AuraEnabled
        public Integer backtestTotal = 0;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String token;
    }

    public class InboxItem {
        @AuraEnabled
        public Id matchId;
        @AuraEnabled
        public Id searchId;
        @AuraEnabled
        public String searchName;
        @AuraEnabled
        public String matchedTerms;
        @AuraEnabled
        public String changeType;
        @AuraEnabled
        public String userAction;
        @AuraEnabled
        public Datetime matchedAt;
        @AuraEnabled
        public NXP_Gov_Notice__c notice;
        /** Points where a read document disagrees with the notice, not yet marked checked. */
        @AuraEnabled
        public Integer openChecks = 0;
    }

    private static final Integer PREVIEW_ROWS = 2000;

    // --------------------------------------------------------------- searches

    @AuraEnabled
    public static List<SearchSummary> getMySearches() {
        Id me = UserInfo.getUserId();
        List<NXP_Saved_Search__c> searches = [
            SELECT Id, Name, OwnerId, Alert_Frequency__c, Visibility__c, Active__c, Auto_Push__c, Criteria_JSON__c
            FROM NXP_Saved_Search__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT 500
        ];
        Map<Id, Integer> counts = new Map<Id, Integer>();
        Datetime since = Datetime.now().addDays(-NXP_Settings.getInteger('Inbox_Days', 30));
        for (AggregateResult ar : [
            SELECT Saved_Search__c s, COUNT(Id) c
            FROM NXP_Search_Match__c
            WHERE Saved_Search__r.OwnerId = :me AND User_Action__c = 'None' AND Matched_At__c >= :since
            WITH USER_MODE
            GROUP BY Saved_Search__c
        ]) {
            counts.put((Id) ar.get('s'), (Integer) ar.get('c'));
        }
        List<SearchSummary> out = new List<SearchSummary>();
        for (NXP_Saved_Search__c s : searches) {
            SearchSummary sum = new SearchSummary();
            sum.id = s.Id;
            sum.name = s.Name;
            sum.frequency = s.Alert_Frequency__c;
            sum.visibility = s.Visibility__c;
            sum.active = s.Active__c;
            sum.mine = s.OwnerId == me;
            sum.autoPush = s.Auto_Push__c;
            sum.newCount = counts.containsKey(s.Id) ? counts.get(s.Id) : 0;
            try {
                sum.description = NXP_SearchCriteria.parse(s.Criteria_JSON__c).describe();
            } catch (Exception e) {
                sum.description = 'Invalid criteria';
            }
            out.add(sum);
        }
        return out;
    }

    @AuraEnabled
    public static NXP_Saved_Search__c getSearch(Id searchId) {
        return [
            SELECT
                Id,
                Name,
                OwnerId,
                Criteria_JSON__c,
                Description__c,
                Visibility__c,
                Team_Group__c,
                Alert_Frequency__c,
                Channels__c,
                Alert_On_Changes__c,
                Auto_Push__c,
                Auto_Push_Min_Fit__c,
                Active__c
            FROM NXP_Saved_Search__c
            WHERE Id = :searchId
            WITH USER_MODE
        ];
    }

    @AuraEnabled
    public static NXP_CriteriaDraftService.Draft draftCriteria(String text) {
        return NXP_CriteriaDraftService.draft(text);
    }

    @AuraEnabled
    public static Preview previewSearch(String criteriaJson) {
        NXP_SearchCriteria c;
        try {
            c = NXP_SearchCriteria.parse(criteriaJson);
            c.validate();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return preview(c);
    }

    /** Shared with the assistant's Preview Search action. */
    public static Preview preview(NXP_SearchCriteria c) {
        Preview p = new Preview();
        p.description = c.describe();
        NXP_GovNoticeSelector selector = new NXP_GovNoticeSelector(AccessLevel.USER_MODE);

        NXP_SearchQueryBuilder q = new NXP_SearchQueryBuilder(c, false, null);
        List<NXP_Gov_Notice__c> rows = selector.whereClause(
            q.whereClause,
            q.binds,
            'Fit_Score__c DESC NULLS LAST, Response_Due__c ASC NULLS LAST',
            PREVIEW_ROWS
        );
        p.capped = rows.size() >= PREVIEW_ROWS;
        for (NXP_Gov_Notice__c n : rows) {
            if (c.matches(n).matched) {
                p.count++;
                if (p.top.size() < 20) {
                    p.top.add(n);
                }
            }
        }

        // 13-week back-test on posted date, ignoring today's status and due-date filters.
        NXP_SearchQueryBuilder bq = new NXP_SearchQueryBuilder(c, true, 91);
        List<Integer> weeks = new List<Integer>();
        for (Integer i = 0; i < 13; i++) {
            weeks.add(0);
        }
        NXP_SearchCriteria history = c.clone();
        history.statuses = new List<String>{ 'Active', 'Archived', 'Cancelled', 'Awarded' };
        history.dueWithinDays = null;
        for (
            NXP_Gov_Notice__c n : selector.whereClause(bq.whereClause, bq.binds, 'Posted_Date__c DESC', PREVIEW_ROWS)
        ) {
            if (n.Posted_Date__c != null && history.matches(n).matched) {
                Integer weeksAgo = n.Posted_Date__c.daysBetween(Date.today()) / 7;
                if (weeksAgo >= 0 && weeksAgo < 13) {
                    weeks[12 - weeksAgo]++;
                    p.backtestTotal++;
                }
            }
        }
        p.weekly = weeks;
        p.token = NXP_PreviewToken.issue('search', c.toJson());
        return p;
    }

    /** Org templates anyone can copy, with today's match count. */
    @AuraEnabled
    public static List<TemplateSummary> getTemplates() {
        List<NXP_Saved_Search__c> rows = [
            SELECT Id, Name, Criteria_JSON__c, Owner.Name
            FROM NXP_Saved_Search__c
            WHERE Visibility__c = 'Org Template'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 12
        ];
        Map<Id, Integer> used = NXP_SearchSharingService.copyCounts(new Map<Id, NXP_Saved_Search__c>(rows).keySet());
        List<TemplateSummary> out = new List<TemplateSummary>();
        for (NXP_Saved_Search__c s : rows) {
            TemplateSummary t = new TemplateSummary();
            t.id = s.Id;
            t.name = s.Name;
            t.ownerName = s.Owner.Name;
            t.usedBy = used.containsKey(s.Id) ? used.get(s.Id) : 0;
            try {
                NXP_SearchCriteria c = NXP_SearchCriteria.parse(s.Criteria_JSON__c);
                t.description = c.describe();
                Preview p = countNow(c);
                t.matchCount = p.count;
                t.capped = p.capped;
            } catch (Exception e) {
                t.description = 'Invalid criteria';
            }
            out.add(t);
        }
        return out;
    }

    /** Today's match count only (no back-test), for template cards. */
    private static Preview countNow(NXP_SearchCriteria c) {
        Preview p = new Preview();
        NXP_SearchQueryBuilder q = new NXP_SearchQueryBuilder(c, false, null);
        List<NXP_Gov_Notice__c> rows = new NXP_GovNoticeSelector(AccessLevel.USER_MODE)
            .whereClause(q.whereClause, q.binds, 'Fit_Score__c DESC NULLS LAST', PREVIEW_ROWS);
        p.capped = rows.size() >= PREVIEW_ROWS;
        for (NXP_Gov_Notice__c n : rows) {
            if (c.matches(n).matched) {
                p.count++;
            }
        }
        return p;
    }

    @AuraEnabled
    public static Id saveSearch(SearchInput input) {
        try {
            return save(input);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Shared with the assistant's Save Search action. */
    public static Id save(SearchInput input) {
        if (String.isBlank(input.name)) {
            throw new AuraHandledException('Give the search a name.');
        }
        NXP_SearchCriteria c = NXP_SearchCriteria.parse(input.criteriaJson);
        c.validate();
        Boolean power = FeatureManagement.checkPermission('NXP_Power_User');
        String visibility = String.isBlank(input.visibility) ? 'Private' : input.visibility;
        String autoPush = String.isBlank(input.autoPush) ? 'Off' : input.autoPush;
        if (!power && visibility != 'Private') {
            throw new AuraHandledException('Only Power Users can share searches with a team or the org.');
        }
        if (!power && autoPush != 'Off') {
            throw new AuraHandledException('Only Power Users can turn on auto-push.');
        }
        String frequency = String.isBlank(input.frequency) ? 'Daily' : input.frequency;
        enforceLimits(input.id, frequency);

        // A template is a starting point to copy: it never alerts, matches or auto-pushes by itself.
        Boolean template = visibility == 'Org Template';
        NXP_Saved_Search__c s = new NXP_Saved_Search__c(
            Id = input.id,
            Name = NXP_Text.truncate(input.name, 80),
            Criteria_JSON__c = c.toJson(),
            Description__c = NXP_Text.truncate(c.describe(), 255),
            Visibility__c = visibility,
            Team_Group__c = input.teamGroup,
            Alert_Frequency__c = frequency,
            Channels__c = input.channels == null || input.channels.isEmpty()
                ? 'Email;Salesforce'
                : String.join(input.channels, ';'),
            Alert_On_Changes__c = input.alertOnChanges != false,
            Auto_Push__c = template ? 'Off' : autoPush,
            Auto_Push_Min_Fit__c = input.autoPushMinFit,
            Active__c = template ? false : input.active != false
        );
        if (template) {
            s.Alert_Frequency__c = 'None';
        }
        if (input.id == null && input.templateId != null) {
            s.Template__c = input.templateId;
        }
        upsert as user s;
        NXP_SearchSharingService.apply(new List<NXP_Saved_Search__c>{ s });
        // Open notices already in Nexus that match go to the Match Inbox now, not only future ones.
        if (s.Active__c && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new NXP_InitialMatchJob(s.Id));
        }
        return s.Id;
    }

    @AuraEnabled
    public static void deleteSearch(Id searchId) {
        delete as user new NXP_Saved_Search__c(Id = searchId);
    }

    // ------------------------------------------------------------------ inbox

    @AuraEnabled
    public static List<InboxItem> getInbox(Id searchId, Boolean includeWatching) {
        Id me = UserInfo.getUserId();
        Datetime since = Datetime.now().addDays(-NXP_Settings.getInteger('Inbox_Days', 30));
        List<String> actions = includeWatching == true
            ? new List<String>{ 'None', 'Watching' }
            : new List<String>{ 'None' };
        String soql =
            'SELECT Id, Saved_Search__c, Saved_Search__r.Name, Gov_Notice__c, Matched_Terms__c, Change_Type__c, User_Action__c, Matched_At__c ' +
            'FROM NXP_Search_Match__c WHERE Saved_Search__r.OwnerId = :me AND User_Action__c IN :actions AND Matched_At__c >= :since' +
            (searchId == null ? '' : ' AND Saved_Search__c = :searchId') +
            ' ORDER BY Matched_At__c DESC LIMIT 500';
        List<NXP_Search_Match__c> matches = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'me' => me, 'actions' => actions, 'since' => since, 'searchId' => searchId },
            AccessLevel.USER_MODE
        );
        Set<Id> noticeIds = new Set<Id>();
        for (NXP_Search_Match__c m : matches) {
            noticeIds.add(m.Gov_Notice__c);
        }
        Map<Id, NXP_Gov_Notice__c> notices = new Map<Id, NXP_Gov_Notice__c>(
            new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byIds(noticeIds)
        );

        Map<Id, Integer> checks = NXP_DocumentService.openCheckCounts(noticeIds);
        // One card per notice: the first (most recent) match wins.
        Map<Id, InboxItem> byNotice = new Map<Id, InboxItem>();
        for (NXP_Search_Match__c m : matches) {
            NXP_Gov_Notice__c n = notices.get(m.Gov_Notice__c);
            if (n == null || byNotice.containsKey(n.Id) || n.Pushed__c) {
                continue;
            }
            InboxItem item = new InboxItem();
            item.matchId = m.Id;
            item.searchId = m.Saved_Search__c;
            item.searchName = m.Saved_Search__r.Name;
            item.matchedTerms = m.Matched_Terms__c;
            item.changeType = m.Change_Type__c;
            item.userAction = m.User_Action__c;
            item.matchedAt = m.Matched_At__c;
            item.notice = n;
            item.openChecks = checks.containsKey(n.Id) ? checks.get(n.Id) : 0;
            byNotice.put(n.Id, item);
        }
        return byNotice.values();
    }

    @AuraEnabled
    public static void setMatchAction(Id matchId, String action, String reason) {
        if (action != 'Watching' && action != 'Dismissed' && action != 'None') {
            throw new AuraHandledException('Unknown action ' + action);
        }
        NXP_Search_Match__c m = [SELECT Id, Gov_Notice__c FROM NXP_Search_Match__c WHERE Id = :matchId WITH USER_MODE];
        update as user new NXP_Search_Match__c(
            Id = m.Id,
            User_Action__c = action,
            Dismiss_Reason__c = NXP_Text.truncate(reason, 255)
        );
        if (action == 'Watching') {
            followNotice(m.Gov_Notice__c, true);
        }
    }

    /** Watch or dismiss several matches at once (Match Inbox bulk actions). Returns how many changed. */
    @AuraEnabled
    public static Integer setMatchActions(List<Id> matchIds, String action, String reason) {
        if (action != 'Watching' && action != 'Dismissed') {
            throw new AuraHandledException('Unknown action ' + action);
        }
        if (matchIds == null || matchIds.isEmpty() || matchIds.size() > 200) {
            throw new AuraHandledException('Select between 1 and 200 notices.');
        }
        List<NXP_Search_Match__c> updates = new List<NXP_Search_Match__c>();
        Set<Id> noticeIds = new Set<Id>();
        for (NXP_Search_Match__c m : [
            SELECT Id, Gov_Notice__c
            FROM NXP_Search_Match__c
            WHERE Id IN :matchIds
            WITH USER_MODE
        ]) {
            updates.add(
                new NXP_Search_Match__c(
                    Id = m.Id,
                    User_Action__c = action,
                    Dismiss_Reason__c = NXP_Text.truncate(reason, 255)
                )
            );
            noticeIds.add(m.Gov_Notice__c);
        }
        update as user updates;
        if (action == 'Watching' && !noticeIds.isEmpty()) {
            Map<String, Id> byKey = new Map<String, Id>();
            for (Id noticeId : noticeIds) {
                byKey.put(String.valueOf(UserInfo.getUserId()) + '-' + String.valueOf(noticeId), noticeId);
            }
            Set<String> keys = byKey.keySet();
            for (NXP_Follow__c f : [
                SELECT Follow_Key__c
                FROM NXP_Follow__c
                WHERE Follow_Key__c IN :keys
                WITH USER_MODE
            ]) {
                byKey.remove(f.Follow_Key__c);
            }
            List<NXP_Follow__c> follows = new List<NXP_Follow__c>();
            for (String key : byKey.keySet()) {
                follows.add(new NXP_Follow__c(Gov_Notice__c = byKey.get(key), Follow_Key__c = key));
            }
            insert as user follows;
        }
        return updates.size();
    }

    @AuraEnabled
    public static void followNotice(Id noticeId, Boolean follow) {
        String key = String.valueOf(UserInfo.getUserId()) + '-' + String.valueOf(noticeId);
        List<NXP_Follow__c> existing = [SELECT Id FROM NXP_Follow__c WHERE Follow_Key__c = :key WITH USER_MODE];
        if (follow == true && existing.isEmpty()) {
            insert as user new NXP_Follow__c(Gov_Notice__c = noticeId, Follow_Key__c = key);
        } else if (follow != true && !existing.isEmpty()) {
            delete as user existing;
        }
    }

    @AuraEnabled
    public static Boolean isFollowing(Id noticeId) {
        String key = String.valueOf(UserInfo.getUserId()) + '-' + String.valueOf(noticeId);
        return ![SELECT Id FROM NXP_Follow__c WHERE Follow_Key__c = :key WITH USER_MODE LIMIT 1].isEmpty();
    }

    private static void enforceLimits(Id searchId, String frequency) {
        Id me = UserInfo.getUserId();
        Integer total = [
            SELECT COUNT()
            FROM NXP_Saved_Search__c
            WHERE OwnerId = :me AND Id != :searchId
            WITH USER_MODE
        ];
        if (total >= NXP_Settings.getInteger('Max_Searches_Per_User', 50)) {
            throw new AuraHandledException('You have reached the limit of saved searches. Delete or pause one first.');
        }
        if (frequency == 'Real Time') {
            Integer realTime = [
                SELECT COUNT()
                FROM NXP_Saved_Search__c
                WHERE OwnerId = :me AND Id != :searchId AND Alert_Frequency__c = 'Real Time' AND Active__c = TRUE
                WITH USER_MODE
            ];
            if (realTime >= NXP_Settings.getInteger('Max_RealTime_Searches', 20)) {
                throw new AuraHandledException(
                    'You have reached the limit of real-time searches. Use a daily digest instead.'
                );
            }
        }
    }
}
