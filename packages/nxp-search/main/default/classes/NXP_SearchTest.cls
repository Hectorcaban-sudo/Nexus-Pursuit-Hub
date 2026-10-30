@IsTest
private class NXP_SearchTest {
    private static NXP_Gov_Notice__c notice(String key, String title, String naics, Integer dueDays) {
        return new NXP_Gov_Notice__c(
            Notice_Id__c = key,
            Title__c = title,
            Description__c = 'The agency needs identity and zero trust engineering.',
            Agency_Path__c = 'Homeland Security › Customs and Border Protection',
            NAICS_Code__c = naics,
            Set_Aside__c = 'Total Small Business Set-Aside',
            Notice_Type__c = 'Solicitation',
            Status__c = 'Active',
            Market__c = 'Federal',
            Estimated_Value__c = 20000000,
            Posted_Date__c = Date.today().addDays(-3),
            Response_Due__c = dueDays == null ? null : Datetime.now().addDays(dueDays),
            Fit_Score__c = 80
        );
    }

    private static String criteria() {
        NXP_SearchCriteria c = new NXP_SearchCriteria();
        c.keywords = 'cyber AND ("zero trust" OR ZTA)';
        c.agencies = new List<String>{ 'Homeland Security' };
        c.naics = new List<String>{ '5415*' };
        c.setAsides = new List<String>{ 'Small Business' };
        c.minValue = 5000000;
        c.dueWithinDays = 45;
        return c.toJson();
    }

    @IsTest
    static void keywordExpressions() {
        String text = NXP_KeywordExpression.normalize('Cyber security: Zero-Trust architecture for ICAM systems');
        Set<String> hits = new Set<String>();
        System.assert(new NXP_KeywordExpression('cyber AND ("zero trust" OR ZTA)').evaluate(text, hits));
        System.assert(hits.contains('zero trust'), hits);
        System.assert(new NXP_KeywordExpression('icam*').evaluate(text, null));
        System.assert(new NXP_KeywordExpression('cyber architecture').evaluate(text, null));
        System.assert(!new NXP_KeywordExpression('cyber NOT security').evaluate(text, null));
        System.assert(!new NXP_KeywordExpression('cloud OR migration').evaluate(text, null));
        System.assert(
            !new NXP_KeywordExpression('trust').evaluate(NXP_KeywordExpression.normalize('trustworthy'), null)
        );
        System.assert(new NXP_KeywordExpression('').isEmpty());
        System.assert(new NXP_KeywordExpression(null).evaluate(text, null));
        for (String bad : new List<String>{ '(cyber', 'cyber)', '"open', 'AND cyber', 'cyber OR' }) {
            try {
                new NXP_KeywordExpression(bad);
                System.assert(false, 'Expected parse error for ' + bad);
            } catch (NXP_KeywordExpression.ParseException e) {
                System.assertNotEquals(null, e.getMessage());
            }
        }
    }

    @IsTest
    static void criteriaMatchingAndDescription() {
        NXP_SearchCriteria c = NXP_SearchCriteria.parse(criteria());
        NXP_Gov_Notice__c n = notice('K', 'Cyber zero trust support', '541512', 10);
        NXP_SearchCriteria.MatchResult r = c.matches(n);
        System.assert(r.matched);
        System.assert(r.terms.contains('541512'));

        n.NAICS_Code__c = '236220';
        System.assert(!c.matches(n).matched);
        n.NAICS_Code__c = '541512';
        n.Response_Due__c = Datetime.now().addDays(90);
        System.assert(!c.matches(n).matched);
        n.Response_Due__c = Datetime.now().addDays(5);
        n.Estimated_Value__c = null;
        System.assert(c.matches(n).matched, 'Unknown value is included by default');
        c.includeUnknownValue = false;
        System.assert(!c.matches(n).matched);

        NXP_SearchCriteria other = new NXP_SearchCriteria();
        other.excludeAgencies = new List<String>{ 'Customs' };
        System.assert(!other.matches(notice('K2', 'x', '1', 1)).matched);
        other = new NXP_SearchCriteria();
        other.minFit = 90;
        System.assert(!other.matches(notice('K3', 'x', '1', 1)).matched);
        other = new NXP_SearchCriteria();
        other.places = new List<String>{ 'VA' };
        other.vehicles = new List<String>{ 'OASIS' };
        other.postedWithinDays = 1;
        System.assert(!other.matches(notice('K4', 'x', '1', 1)).matched);
        System.assertEquals('all active notices', new NXP_SearchCriteria().describe());
        System.assert(c.describe().contains('NAICS'));
        System.assertEquals(0, NXP_SearchCriteria.parse(null).effectiveStatuses().size() - 1);

        NXP_SearchCriteria bad = new NXP_SearchCriteria();
        bad.minValue = 10;
        bad.maxValue = 1;
        try {
            bad.validate();
            System.assert(false);
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('greater'));
        }
    }

    @IsTest
    static void queryBuilder() {
        NXP_SearchCriteria c = NXP_SearchCriteria.parse(criteria());
        c.psc = new List<String>{ 'DA01', 'D3*' };
        c.noticeTypes = new List<String>{ 'Solicitation' };
        c.markets = new List<String>{ 'Federal' };
        c.sources = new List<String>{ 'SAM_Opportunities' };
        c.minFit = 50;
        c.maxValue = 90000000;
        c.postedWithinDays = 30;
        NXP_SearchQueryBuilder q = new NXP_SearchQueryBuilder(c, false, null);
        System.assert(q.whereClause.contains('NAICS_Code__c LIKE'), q.whereClause);
        System.assert(q.whereClause.contains('PSC_Code__c IN'), q.whereClause);
        new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).whereClause(q.whereClause, q.binds, null, 10);
        NXP_SearchQueryBuilder back = new NXP_SearchQueryBuilder(c, true, 91);
        System.assert(!back.whereClause.contains('Status__c'));
    }

    @IsTest
    static void draftFromPlainEnglish() {
        NXP_CriteriaDraftService.Draft d = NXP_CriteriaDraftService.draft(
            'Alert me daily on DHS and CBP cyber notices, NAICS 541512, small business or 8(a), over $5M, due in the next 45 days, sources sought'
        );
        NXP_SearchCriteria c = d.criteria;
        System.assertEquals('Daily', d.frequency);
        System.assertEquals(new List<String>{ '541512' }, c.naics);
        System.assertEquals(5000000, c.minValue);
        System.assertEquals(45, c.dueWithinDays);
        System.assert(c.setAsides.contains('Small Business'), c.setAsides);
        System.assert(c.setAsides.contains('8(a)'), c.setAsides);
        System.assert(c.agencies.contains('Homeland Security'), c.agencies);
        System.assert(c.agencies.contains('Customs and Border Protection'), c.agencies);
        System.assert(c.noticeTypes.contains('Sources Sought'), c.noticeTypes);
        System.assertEquals('cyber', c.keywords);
        System.assertEquals('Real Time', NXP_CriteriaDraftService.draft('cloud real time under $500k').frequency);
        System.assertEquals(500000, NXP_CriteriaDraftService.draft('cloud under $500k').criteria.maxValue);
        System.assertEquals('Weekly', NXP_CriteriaDraftService.draft('weekly').frequency);
        System.assertEquals(2000000000, NXP_CriteriaDraftService.toAmount('2', 'billion'));
        System.assertNotEquals(null, NXP_SearchController.draftCriteria('cyber').criteriaJson);
    }

    @IsTest
    static void previewSaveInboxActionsAndFollow() {
        insert new List<NXP_Gov_Notice__c>{
            notice('A', 'Cyber zero trust support', '541512', 10),
            notice('B', 'Facilities maintenance', '561210', 10)
        };

        NXP_SearchController.Preview p = NXP_SearchController.previewSearch(criteria());
        System.assertEquals(1, p.count);
        System.assertEquals(13, p.weekly.size());
        System.assertEquals(1, p.backtestTotal);
        try {
            NXP_SearchController.previewSearch('{"keywords":"(broken"}');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        NXP_SearchController.SearchInput input = new NXP_SearchController.SearchInput();
        input.name = 'DHS cyber';
        input.criteriaJson = criteria();
        input.frequency = 'Real Time';
        input.channels = new List<String>{ 'Email', 'Salesforce' };
        Id searchId = NXP_SearchController.saveSearch(input);
        System.assertEquals('Private', NXP_SearchController.getSearch(searchId).Visibility__c);

        input.id = searchId;
        input.visibility = 'Team';
        try {
            NXP_SearchController.saveSearch(input);
            System.assert(false, 'Non power users cannot share');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        input.visibility = 'Private';
        input.autoPush = 'All Matches';
        try {
            NXP_SearchController.saveSearch(input);
            System.assert(false, 'Non power users cannot auto-push');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        NXP_SearchController.SearchInput noName = new NXP_SearchController.SearchInput();
        try {
            NXP_SearchController.saveSearch(noName);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        Test.startTest();
        Set<Id> ids = new Map<Id, NXP_Gov_Notice__c>([SELECT Id FROM NXP_Gov_Notice__c]).keySet();
        Map<Id, String> types = new Map<Id, String>();
        for (Id i : ids) {
            types.put(i, 'New');
        }
        List<NXP_Search_Match__c> matches = NXP_SearchMatchService.process(types, ids);
        Test.stopTest();
        System.assertEquals(1, matches.size());
        System.assertEquals('Sent', [SELECT Alert_Status__c FROM NXP_Search_Match__c].Alert_Status__c);
        System.assertEquals(
            'Pending',
            [SELECT AI_Summary_Status__c FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'A'].AI_Summary_Status__c
        );

        List<NXP_SearchController.SearchSummary> mine = NXP_SearchController.getMySearches();
        System.assertEquals(1, mine.size());
        System.assertEquals(1, mine[0].newCount);
        List<NXP_SearchController.InboxItem> inbox = NXP_SearchController.getInbox(null, false);
        System.assertEquals(1, inbox.size());
        System.assertEquals(1, NXP_SearchController.getInbox(searchId, true).size());

        NXP_SearchController.setMatchAction(inbox[0].matchId, 'Watching', null);
        System.assert(NXP_SearchController.isFollowing(inbox[0].notice.Id));
        NXP_SearchController.followNotice(inbox[0].notice.Id, false);
        System.assert(!NXP_SearchController.isFollowing(inbox[0].notice.Id));
        System.assertEquals(
            1,
            NXP_SearchController.setMatchActions(new List<Id>{ inbox[0].matchId }, 'Watching', null)
        );
        System.assert(NXP_SearchController.isFollowing(inbox[0].notice.Id), 'Bulk watch follows');
        try {
            NXP_SearchController.setMatchActions(new List<Id>(), 'Watching', null);
            System.assert(false, 'expected: nothing selected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(
            1,
            NXP_SearchController.setMatchActions(new List<Id>{ inbox[0].matchId }, 'Dismissed', 'Not a fit')
        );
        System.assertEquals(0, NXP_SearchController.getInbox(null, true).size());
        NXP_SearchController.setMatchAction(inbox[0].matchId, 'Dismissed', 'Not a fit');
        System.assertEquals(0, NXP_SearchController.getInbox(null, true).size());
        try {
            NXP_SearchController.setMatchAction(inbox[0].matchId, 'Bogus', null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        NXP_SearchController.deleteSearch(searchId);
        System.assertEquals(0, [SELECT COUNT() FROM NXP_Saved_Search__c]);
    }

    @IsTest
    static void savingASearchMatchesOpenNoticesQuietly() {
        insert new List<NXP_Gov_Notice__c>{
            notice('OPEN-1', 'Cyber zero trust support', '541512', 20),
            notice('OPEN-2', 'Office furniture', '337214', 20)
        };
        NXP_Saved_Search__c s = new NXP_Saved_Search__c(
            Name = 'S',
            Criteria_JSON__c = criteria(),
            Alert_Frequency__c = 'Real Time',
            Channels__c = 'Email',
            Active__c = true
        );
        insert s;

        System.assertEquals(1, NXP_InitialMatchJob.run(s.Id));
        NXP_Search_Match__c m = [
            SELECT Change_Type__c, Alert_Status__c, User_Action__c, Gov_Notice__r.Notice_Id__c
            FROM NXP_Search_Match__c
        ];
        System.assertEquals('OPEN-1', m.Gov_Notice__r.Notice_Id__c);
        System.assertEquals(NXP_InitialMatchJob.CHANGE_TYPE, m.Change_Type__c);
        System.assertEquals('Suppressed', m.Alert_Status__c, 'Existing notices never send alerts');
        System.assertEquals('None', m.User_Action__c);
        System.assertEquals(
            'Pending',
            [SELECT AI_Summary_Status__c FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'OPEN-1'].AI_Summary_Status__c
        );
        System.assertNotEquals(
            'Pending',
            [SELECT AI_Summary_Status__c FROM NXP_Gov_Notice__c WHERE Notice_Id__c = 'OPEN-2'].AI_Summary_Status__c
        );
        System.assertEquals(0, NXP_InitialMatchJob.run(s.Id), 'Already matched');
        System.assertEquals(1, NXP_SearchController.getInbox(s.Id, false).size());

        Test.startTest();
        NXP_SearchController.SearchInput input = new NXP_SearchController.SearchInput();
        input.id = s.Id;
        input.name = 'S';
        input.criteriaJson = criteria();
        input.frequency = 'Daily';
        NXP_SearchController.saveSearch(input);
        System.assertEquals(1, Limits.getQueueableJobs(), 'Saving queues the initial match');
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Search_Match__c]);
    }

    @IsTest
    static void changeEventsAlertFollowersAndChangedMatches() {
        NXP_Gov_Notice__c n = notice('A', 'Cyber zero trust support', '541512', 10);
        insert n;
        insert new NXP_Saved_Search__c(
            Name = 'S',
            Criteria_JSON__c = criteria(),
            Alert_Frequency__c = 'Daily',
            Channels__c = 'Email',
            Alert_On_Changes__c = true,
            Active__c = true
        );
        insert new NXP_Saved_Search__c(
            Name = 'Silent',
            Criteria_JSON__c = '{}',
            Alert_Frequency__c = 'None',
            Active__c = true
        );
        insert new NXP_Saved_Search__c(
            Name = 'Broken',
            Criteria_JSON__c = '{"keywords":"(x"}',
            Alert_Frequency__c = 'Daily',
            Active__c = true
        );
        insert new NXP_Follow__c(Gov_Notice__c = n.Id, Follow_Key__c = UserInfo.getUserId() + '-' + n.Id);

        Test.startTest();
        EventBus.publish(
            new NXP_Gov_Notice_Changed__e(Notice_Record_Id__c = n.Id, Change_Type__c = 'New', Is_New__c = true)
        );
        Test.getEventBus().deliver();
        System.assertEquals(2, [SELECT COUNT() FROM NXP_Search_Match__c]);
        System.assertEquals(1, [SELECT COUNT() FROM NXP_Search_Match__c WHERE Alert_Status__c = 'Suppressed']);

        update [SELECT Id FROM NXP_Search_Match__c];
        NXP_Search_Match__c m = [SELECT Id FROM NXP_Search_Match__c WHERE Saved_Search__r.Name = 'S'];
        m.Alert_Status__c = 'Sent';
        update m;
        EventBus.publish(
            new NXP_Gov_Notice_Changed__e(Notice_Record_Id__c = n.Id, Change_Type__c = 'Due date', Is_New__c = false)
        );
        Test.getEventBus().deliver();
        Test.stopTest();
        m = [SELECT Alert_Status__c, Change_Type__c FROM NXP_Search_Match__c WHERE Id = :m.Id];
        System.assertEquals('Pending', m.Alert_Status__c);
        System.assertEquals('Due date', m.Change_Type__c);
    }

    @IsTest
    static void digestSendsPendingMatches() {
        NXP_Gov_Notice__c n = notice('A', 'Cyber zero trust support', '541512', 10);
        n.AI_Summary__c = 'Summary';
        insert n;
        NXP_Saved_Search__c s = new NXP_Saved_Search__c(
            Name = 'S',
            Criteria_JSON__c = '{}',
            Alert_Frequency__c = 'Daily',
            Active__c = true
        );
        insert s;
        insert new NXP_Search_Match__c(
            Saved_Search__c = s.Id,
            Gov_Notice__c = n.Id,
            Match_Key__c = 'k1',
            Alert_Status__c = 'Pending',
            User_Action__c = 'None',
            Matched_At__c = Datetime.now(),
            Change_Type__c = 'Due date'
        );
        Test.startTest();
        Database.executeBatch(new NXP_DigestBatch('Daily'), 20);
        Test.stopTest();
        System.assertEquals('Sent', [SELECT Alert_Status__c FROM NXP_Search_Match__c].Alert_Status__c);
        System.assertNotEquals(null, [SELECT Last_Digest_Sent__c FROM NXP_Saved_Search__c].Last_Digest_Sent__c);
        new NXP_DigestBatch('Weekly').execute((SchedulableContext) null);
    }

    @IsTest
    static void sharingFollowsVisibility() {
        Group g = new Group(Name = 'NXP Test Team', DeveloperName = 'NXP_Test_Team', Type = 'Regular');
        insert g;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<NXP_Saved_Search__c> searches = new List<NXP_Saved_Search__c>{
                new NXP_Saved_Search__c(
                    Name = 'Team',
                    Visibility__c = 'Team',
                    Team_Group__c = 'NXP_Test_Team',
                    Active__c = true
                ),
                new NXP_Saved_Search__c(Name = 'Org', Visibility__c = 'Org Template', Active__c = true),
                new NXP_Saved_Search__c(Name = 'Mine', Visibility__c = 'Private', Active__c = true)
            };
            insert searches;
            NXP_SearchSharingService.apply(searches);
            System.assertEquals(2, [SELECT COUNT() FROM NXP_Saved_Search__Share WHERE RowCause = 'Manual']);
        }
    }

    @IsTest
    static void alertHelpers() {
        NXP_Gov_Notice__c n = notice('A', 'Title', '541512', 3);
        System.assert(NXP_AlertService.summaryLine(n).contains('fit 80'));
        NXP_AlertService.notify(UserInfo.getUserId(), 'Hello', 'Body', UserInfo.getUserId());
        NXP_AlertService.sendEmails(
            new List<Messaging.SingleEmailMessage>{ NXP_AlertService.email(UserInfo.getUserId(), 'Test', '<p>x</p>') }
        );
        System.assertEquals(36, NXP_SearchMatchService.matchKey('a0X000000000001', 'a0Y000000000001').length() - 1);
    }
}
