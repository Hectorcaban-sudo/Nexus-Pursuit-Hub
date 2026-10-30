/**
 * Settings tab (nxpAdminSettings): every NXP setting, feed switch and fit rule weight on one
 * screen, with health checks and a change history. Admins only (NXP_Admin_Access).
 *
 * Custom metadata records can't be changed with DML, so Save sends a metadata deployment from
 * Apex (Metadata.Operations.enqueueDeployment). It takes about 30 seconds; NXP_SettingsDeployCallback
 * marks the NXP_Setting_Change__c rows Saved or Failed. The admin needs permission to deploy custom
 * metadata (Customize Application). Values in env-config are deployed again by each release.
 */
public with sharing class NXP_SettingsController {
    // ------------------------------------------------------------------ view model

    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Item {
        /** Record and field, e.g. NXP_Setting.AI_Enabled or NXP_Feed_Config.SAM_Opportunities.Active__c */
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String help;
        /** Boolean, Integer, Text or Picklist. */
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String defaultValue;
        @AuraEnabled
        public List<Option> options;
        /** Sub-heading inside a section, e.g. the feed name. */
        @AuraEnabled
        public String subgroup;
        /** Deployed again by each release from env-config, so a change here lasts until the next release. */
        @AuraEnabled
        public Boolean releaseManaged = false;
    }

    public class Section {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String help;
        @AuraEnabled
        public List<Item> items = new List<Item>();
    }

    public class Change {
        @AuraEnabled
        public String id { get; set; }
        @AuraEnabled
        public String value { get; set; }
    }

    public class HistoryRow {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String oldValue;
        @AuraEnabled
        public String newValue;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public String changedBy;
        @AuraEnabled
        public Datetime changed;
    }

    public class Model {
        @AuraEnabled
        public List<Section> sections = new List<Section>();
        @AuraEnabled
        public List<HistoryRow> history = new List<HistoryRow>();
        @AuraEnabled
        public Integer aiCallsToday = 0;
        @AuraEnabled
        public Boolean canDeploy = false;
    }

    public class Check {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String title;
        /** ok, warn or fail. */
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String detail;
        /** Button the screen shows: testKey, reschedule, rescore or a Setup page path. */
        @AuraEnabled
        public String action;
        @AuraEnabled
        public String actionLabel;
    }

    // ------------------------------------------------------------------ catalog

    /** Settings the screen knows, in display order: section, key, label, help, type, picklist values. */
    private static final List<List<String>> CATALOG = new List<List<String>>{
        new List<String>{
            'alerts',
            'Admin_Digest_Mode',
            'Admin problems e-mail',
            'Sent at 07:00. Problems: only when something failed. Daily: always, with an all-clear. Off: never.',
            'Picklist',
            'Problems;Daily;Off',
            'Problems'
        },
        new List<String>{
            'alerts',
            'Admin_Digest_Recipients',
            'Who gets the problems e-mail',
            'E-mail addresses separated by commas. Blank: every active NXP Admin user.',
            'Text',
            '',
            ''
        },
        new List<String>{
            'alerts',
            'Ebuy_Silence_Days',
            'Warn when no eBuy e-mail for (days)',
            'Catches broken forwarding. 0 = off.',
            'Integer',
            '',
            '3'
        },
        new List<String>{
            'alerts',
            'Alert_OrgWide_Email_Id',
            'Alerts come from',
            'A verified organization-wide e-mail address. Blank: the admin who scheduled the jobs.',
            'OrgWideEmail',
            '',
            ''
        },
        new List<String>{ 'searches', 'Inbox_Days', 'Match Inbox keeps cards for (days)', '', 'Integer', '', '30' },
        new List<String>{
            'searches',
            'Max_Searches_Per_User',
            'Saved searches per user',
            'Keeps matching fast.',
            'Integer',
            '',
            '50'
        },
        new List<String>{
            'searches',
            'Max_RealTime_Searches',
            'Real Time searches per user',
            'Use Daily for broad searches.',
            'Integer',
            '',
            '20'
        },
        new List<String>{
            'searches',
            'Initial_Match_Max_Summaries',
            'AI summaries when a search is saved',
            'For notices already open that match a newly saved search, best fit first.',
            'Integer',
            '',
            '25'
        },
        new List<String>{
            'ai',
            'AI_Enabled',
            'AI on',
            'Summaries, Document Reader, eBuy extraction, criteria drafts and Find similar keywords. Needs the prompt templates.',
            'Boolean',
            '',
            'false'
        },
        new List<String>{
            'ai',
            'AI_Max_Calls_Per_Day',
            'Most AI calls per day',
            'After that, AI work waits for tomorrow. 0 = no limit.',
            'Integer',
            '',
            '500'
        },
        new List<String>{
            'ai',
            'AI_Summary_Template',
            'Summary prompt template',
            'API name in Prompt Builder.',
            'Text',
            '',
            'NXP_Solicitation_Summary'
        },
        new List<String>{
            'ai',
            'AI_Change_Template',
            'Amendment summary prompt template',
            '',
            'Text',
            '',
            'NXP_Amendment_Impact'
        },
        new List<String>{
            'ai',
            'Similar_Keywords_Template',
            'Find similar prompt template',
            '',
            'Text',
            '',
            'NXP_Similar_Keywords'
        },
        new List<String>{
            'files',
            'Description_Min_Fit',
            'Fetch descriptions automatically from fit',
            'Matched notices always get theirs. Each is one SAM.gov call. 0 = all.',
            'Integer',
            '',
            '50'
        },
        new List<String>{
            'files',
            'Files_Auto_Download',
            'Download SAM.gov files automatically',
            'For matched notices and the fit below. Off: only Get SAM.gov files.',
            'Boolean',
            '',
            'true'
        },
        new List<String>{ 'files', 'Files_Min_Fit', 'Download files automatically from fit', '', 'Integer', '', '70' },
        new List<String>{
            'files',
            'Files_Max_Per_Notice',
            'Most SAM.gov files per notice',
            'Each is one SAM.gov call and uses file storage.',
            'Integer',
            '',
            '10'
        },
        new List<String>{
            'files',
            'Files_Max_MB',
            'Largest SAM.gov file (MB)',
            'Keep at 8 or less: a background job has 12 MB of memory.',
            'Integer',
            '',
            '6'
        },
        new List<String>{
            'files',
            'Document_Analysis_Enabled',
            'Document Reader on',
            'AI reads notice PDFs. Needs AI on and the NXP_Document_Analysis template.',
            'Boolean',
            '',
            'false'
        },
        new List<String>{
            'files',
            'Document_Analysis_Template',
            'Document Reader prompt template',
            '',
            'Text',
            '',
            'NXP_Document_Analysis'
        },
        new List<String>{
            'files',
            'Document_Max_MB',
            'Largest PDF the Document Reader reads (MB)',
            '',
            'Integer',
            '',
            '10'
        },
        new List<String>{
            'files',
            'Document_Max_Per_Notice',
            'PDFs read automatically per notice',
            'The rest with Analyze.',
            'Integer',
            '',
            '5'
        },
        new List<String>{
            'ebuy',
            'Ebuy_Allowed_Senders',
            'Accept eBuy e-mail from',
            'Addresses or domains, separated by commas.',
            'Text',
            '',
            'gsa.gov'
        },
        new List<String>{
            'ebuy',
            'Ebuy_Default_Vehicle',
            'Vehicle for eBuy e-mail to other addresses',
            'Contract vehicle code.',
            'Text',
            '',
            'GSA-MAS-IT'
        },
        new List<String>{ 'ebuy', 'Ebuy_AI_Template', 'eBuy prompt template', '', 'Text', '', 'NXP_Ebuy_RFQ_Extract' },
        new List<String>{
            'ebuy',
            'Ebuy_AI_Read_Attachments',
            'AI also reads the first PDF',
            'The template needs a File input named Attachment.',
            'Boolean',
            '',
            'false'
        },
        new List<String>{
            'ebuy',
            'Ebuy_Share_Files_With_Notice',
            'Link eBuy attachments to the notice',
            'Off: only admins see them, on the Inbound Email.',
            'Boolean',
            '',
            'true'
        },
        new List<String>{
            'push',
            'Push_Mapping_Set',
            'Push mapping set',
            'Which NXP Push Mapping rows are used. The rows themselves are edited in Setup.',
            'Text',
            '',
            'Opportunity_Default'
        },
        new List<String>{ 'push', 'Push_Max_Attempts', 'Auto-push tries', '', 'Integer', '', '3' },
        new List<String>{ 'feeds', 'Http_Max_Attempts', 'Tries per call', 'On HTTP 429 and 5xx.', 'Integer', '', '3' },
        new List<String>{ 'feeds', 'Http_Timeout_Ms', 'Call timeout (ms)', '', 'Integer', '', '60000' },
        new List<String>{ 'feeds', 'Queue_Max_Pages', 'Pages per pipeline run', '', 'Integer', '', '50' },
        new List<String>{ 'feeds', 'Batch_Max_Pages', 'Pages per batch run', '', 'Integer', '', '200' }
    };

    private static final List<List<String>> SECTIONS = new List<List<String>>{
        new List<String>{ 'alerts', 'Alerts and e-mail', 'How users and admins are told about matches and problems' },
        new List<String>{ 'feeds', 'SAM.gov and feeds', 'Which feeds run and how often' },
        new List<String>{ 'searches', 'Searches and inbox', 'Limits that keep matching fast' },
        new List<String>{ 'ai', 'AI', 'Summaries, Document Reader, eBuy extraction, criteria drafts' },
        new List<String>{
            'files',
            'Descriptions and files',
            'What is fetched from SAM.gov and read by the Document Reader'
        },
        new List<String>{ 'ebuy', 'GSA eBuy', 'The eBuy e-mail inbox' },
        new List<String>{ 'fit', 'Fit score rules', 'Rule weights; active weights must add up to 100' },
        new List<String>{ 'push', 'Push to Opportunity', 'Push mapping rows and the Opportunity fields stay in Setup' },
        new List<String>{ 'other', 'Other settings', 'Settings this screen has no description for. Change with care.' }
    };

    /** Deployed by every release from env-config/<env>. */
    private static final Set<String> RELEASE_MANAGED_SETTINGS = new Set<String>{ 'AI_Enabled', 'Org_Environment' };

    private static final List<String> FEED_FIELDS = new List<String>{
        'Active__c',
        'Interval_Minutes__c',
        'Lookback_Days__c',
        'Page_Size__c'
    };

    @TestVisible
    private static Boolean deployForTest = false;

    // ------------------------------------------------------------------ read

    @AuraEnabled
    public static Model getSettings() {
        requireAdmin();
        Model m = new Model();
        Map<String, Section> byKey = new Map<String, Section>();
        for (List<String> s : SECTIONS) {
            Section sec = new Section();
            sec.key = s[0];
            sec.label = s[1];
            sec.help = s[2];
            byKey.put(sec.key, sec);
            m.sections.add(sec);
        }

        Map<String, NXP_Setting__mdt> settings = NXP_Setting__mdt.getAll();
        Set<String> known = new Set<String>();
        List<Option> orgWide = orgWideOptions();
        for (List<String> c : CATALOG) {
            known.add(c[1]);
            NXP_Setting__mdt rec = settings.get(c[1]);
            Item i = new Item();
            i.id = 'NXP_Setting.' + c[1];
            i.label = c[2];
            i.help = c[3];
            i.type = c[4] == 'OrgWideEmail' ? 'Picklist' : c[4];
            i.defaultValue = c[6];
            i.value = rec == null || rec.Value__c == null ? c[6] : rec.Value__c;
            if (c[4] == 'Picklist') {
                i.options = new List<Option>();
                for (String v : c[5].split(';')) {
                    i.options.add(new Option(v, v));
                }
            } else if (c[4] == 'OrgWideEmail') {
                i.options = orgWide;
            }
            i.releaseManaged = RELEASE_MANAGED_SETTINGS.contains(c[1]);
            byKey.get(c[0]).items.add(i);
        }
        List<String> others = new List<String>(settings.keySet());
        others.sort();
        for (String key : others) {
            if (known.contains(key)) {
                continue;
            }
            NXP_Setting__mdt rec = settings.get(key);
            Item i = new Item();
            i.id = 'NXP_Setting.' + key;
            i.label = rec.MasterLabel;
            i.help = rec.Description__c;
            i.type = 'Text';
            i.value = rec.Value__c;
            i.releaseManaged = RELEASE_MANAGED_SETTINGS.contains(key);
            byKey.get('other').items.add(i);
        }

        // Feeds: on/off and timing per feed, first in their section.
        List<Item> feedItems = new List<Item>();
        for (NXP_Feed_Config__mdt f : [
            SELECT
                DeveloperName,
                MasterLabel,
                Active__c,
                Interval_Minutes__c,
                Lookback_Days__c,
                Page_Size__c,
                Channel__c
            FROM NXP_Feed_Config__mdt
            ORDER BY MasterLabel
        ]) {
            if (f.Channel__c == 'Apex REST') {
                continue;
            }
            String base = 'NXP_Feed_Config.' + f.DeveloperName + '.';
            feedItems.add(
                item(
                    base + 'Active__c',
                    'On',
                    'Off: the feed runs only with Run now.',
                    'Boolean',
                    String.valueOf(f.Active__c),
                    f.MasterLabel,
                    true
                )
            );
            feedItems.add(
                item(
                    base + 'Interval_Minutes__c',
                    'Every (minutes)',
                    '60 = hourly, 1440 = daily, 10080 = weekly.',
                    'Integer',
                    num(f.Interval_Minutes__c),
                    f.MasterLabel,
                    true
                )
            );
            feedItems.add(
                item(
                    base + 'Lookback_Days__c',
                    'First run looks back (days)',
                    'Later runs start a day before the last success.',
                    'Integer',
                    num(f.Lookback_Days__c),
                    f.MasterLabel,
                    true
                )
            );
            feedItems.add(
                item(
                    base + 'Page_Size__c',
                    'Records per call',
                    'SAM.gov allows up to 1000.',
                    'Integer',
                    num(f.Page_Size__c),
                    f.MasterLabel,
                    true
                )
            );
        }
        feedItems.addAll(byKey.get('feeds').items);
        byKey.get('feeds').items = feedItems;

        for (NXP_Fit_Rule__mdt r : [
            SELECT DeveloperName, MasterLabel, Active__c, Weight__c, Description__c
            FROM NXP_Fit_Rule__mdt
            ORDER BY MasterLabel
        ]) {
            String base = 'NXP_Fit_Rule.' + r.DeveloperName + '.';
            byKey.get('fit')
                .items.add(
                    item(
                        base + 'Active__c',
                        'On',
                        r.Description__c,
                        'Boolean',
                        String.valueOf(r.Active__c),
                        r.MasterLabel,
                        false
                    )
                );
            byKey.get('fit')
                .items.add(
                    item(base + 'Weight__c', 'Weight (points)', '', 'Integer', num(r.Weight__c), r.MasterLabel, false)
                );
        }

        for (NXP_Setting_Change__c c : [
            SELECT Label__c, Old_Value__c, New_Value__c, Status__c, Detail__c, CreatedBy.Name, CreatedDate
            FROM NXP_Setting_Change__c
            ORDER BY CreatedDate DESC
            LIMIT 15
        ]) {
            HistoryRow h = new HistoryRow();
            h.label = c.Label__c;
            h.oldValue = c.Old_Value__c;
            h.newValue = c.New_Value__c;
            h.status = c.Status__c;
            h.detail = c.Detail__c;
            h.changedBy = c.CreatedBy.Name;
            h.changed = c.CreatedDate;
            m.history.add(h);
        }

        NXP_AI_Usage__c u = NXP_AI_Usage__c.getOrgDefaults();
        m.aiCallsToday = u == null || u.Day__c != Date.today() || u.Calls__c == null ? 0 : u.Calls__c.intValue();
        m.canDeploy = FeatureManagement.checkPermission('NXP_Admin_Access');
        return m;
    }

    // ------------------------------------------------------------------ save

    /** Validates the changes, records them and starts the deployment. Returns the deployment Id. */
    @AuraEnabled
    public static String saveSettings(List<Change> changes) {
        requireAdmin();
        if (changes == null || changes.isEmpty()) {
            throw new AuraHandledException('Nothing to save.');
        }
        Map<String, Item> current = new Map<String, Item>();
        for (Section s : getSettings().sections) {
            for (Item i : s.items) {
                current.put(i.id, i);
            }
        }
        // record (type.name) -> field -> new value
        Map<String, Map<String, String>> byRecord = new Map<String, Map<String, String>>();
        List<NXP_Setting_Change__c> rows = new List<NXP_Setting_Change__c>();
        for (Change c : changes) {
            Item i = current.get(c.id);
            if (i == null) {
                throw new AuraHandledException('Unknown setting ' + c.id);
            }
            String value = validate(i, c.value);
            List<String> parts = c.id.split('\\.');
            String record = parts[0] + '.' + parts[1];
            String field = parts.size() > 2 ? parts[2] : 'Value__c';
            if (!byRecord.containsKey(record)) {
                byRecord.put(record, new Map<String, String>());
            }
            byRecord.get(record).put(field, value);
            rows.add(
                new NXP_Setting_Change__c(
                    Setting__c = c.id.left(255),
                    Label__c = ((i.subgroup == null ? '' : i.subgroup + ': ') + i.label).left(255),
                    Old_Value__c = i.value == null ? null : i.value.left(255),
                    New_Value__c = value == null ? null : value.left(255),
                    Status__c = 'Pending'
                )
            );
        }
        checkFitWeights(current, byRecord);

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        for (String record : byRecord.keySet()) {
            container.addMetadata(toMetadata(record, byRecord.get(record)));
        }
        String jobId = 'test';
        if (!Test.isRunningTest() || deployForTest) {
            jobId = Metadata.Operations.enqueueDeployment(container, new NXP_SettingsDeployCallback());
        }
        for (NXP_Setting_Change__c r : rows) {
            r.Deploy_Id__c = jobId;
        }
        insert as user rows;
        return jobId;
    }

    /**
     * Deploying the packages puts the shipped values back. Saves again the last value saved on
     * this screen for every setting a release changed (not those env-config sets on purpose).
     * Returns the deployment Id, or null when nothing needs reapplying.
     */
    @AuraEnabled
    public static String reapplySettings() {
        requireAdmin();
        List<Change> changes = releaseDrift();
        return changes.isEmpty() ? null : saveSettings(changes);
    }

    /** Settings whose current value differs from the last value saved here. */
    @TestVisible
    private static List<Change> releaseDrift() {
        Map<String, Item> current = new Map<String, Item>();
        for (Section s : getSettings().sections) {
            for (Item i : s.items) {
                current.put(i.id, i);
            }
        }
        Map<String, String> lastSaved = new Map<String, String>();
        for (NXP_Setting_Change__c c : [
            SELECT Setting__c, New_Value__c
            FROM NXP_Setting_Change__c
            WHERE Status__c = 'Saved'
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Name DESC
            LIMIT 2000
        ]) {
            if (!lastSaved.containsKey(c.Setting__c)) {
                lastSaved.put(c.Setting__c, c.New_Value__c);
            }
        }
        List<Change> out = new List<Change>();
        for (String id : lastSaved.keySet()) {
            Item i = current.get(id);
            String want = lastSaved.get(id) == null ? '' : lastSaved.get(id);
            String have = i == null || i.value == null ? '' : i.value;
            if (i != null && !i.releaseManaged && want != have) {
                Change c = new Change();
                c.id = id;
                c.value = want;
                out.add(c);
            }
        }
        return out;
    }

    /** Pending, Saved or Failed (with the reason) for one deployment. */
    @AuraEnabled
    public static Map<String, String> getSaveStatus(String deployId) {
        requireAdmin();
        Map<String, String> out = new Map<String, String>{ 'status' => 'Pending' };
        for (NXP_Setting_Change__c c : [
            SELECT Status__c, Detail__c
            FROM NXP_Setting_Change__c
            WHERE Deploy_Id__c = :deployId
            WITH USER_MODE
            LIMIT 1
        ]) {
            out.put('status', c.Status__c);
            out.put('detail', c.Detail__c);
        }
        return out;
    }

    @TestVisible
    private static String validate(Item i, String raw) {
        String value = raw == null ? null : raw.trim();
        if (i.type == 'Boolean') {
            if (value != 'true' && value != 'false') {
                throw new AuraHandledException(i.label + ': choose on or off.');
            }
        } else if (i.type == 'Integer') {
            if (String.isBlank(value) || !value.isNumeric()) {
                throw new AuraHandledException(i.label + ': enter a whole number of 0 or more.');
            }
        } else if (i.type == 'Picklist' && i.options != null && String.isNotBlank(value)) {
            Boolean ok = false;
            for (Option o : i.options) {
                ok = ok || o.value == value;
            }
            if (!ok) {
                throw new AuraHandledException(i.label + ': choose one of the listed values.');
            }
        }
        if (value != null && value.length() > 255) {
            throw new AuraHandledException(i.label + ': 255 characters at most.');
        }
        return value;
    }

    /** Active fit rule weights must still add up to 100 after the change. */
    private static void checkFitWeights(Map<String, Item> current, Map<String, Map<String, String>> byRecord) {
        Boolean touched = false;
        for (String record : byRecord.keySet()) {
            touched = touched || record.startsWith('NXP_Fit_Rule.');
        }
        if (!touched) {
            return;
        }
        Integer total = 0;
        for (String id : current.keySet()) {
            if (!id.startsWith('NXP_Fit_Rule.') || !id.endsWith('.Active__c')) {
                continue;
            }
            String record = id.substringBeforeLast('.');
            Map<String, String> changed = byRecord.containsKey(record)
                ? byRecord.get(record)
                : new Map<String, String>();
            String active = changed.containsKey('Active__c') ? changed.get('Active__c') : current.get(id).value;
            String weight = changed.containsKey('Weight__c')
                ? changed.get('Weight__c')
                : current.get(record + '.Weight__c').value;
            if (active == 'true' && String.isNotBlank(weight)) {
                total += Integer.valueOf(weight);
            }
        }
        if (total != 100) {
            throw new AuraHandledException(
                'Active fit rule weights must add up to 100; they would add up to ' + total + '.'
            );
        }
    }

    /**
     * A full custom metadata record for the deployment: a deployed record replaces the old one, so
     * every field is sent, with the changed ones replaced.
     */
    @TestVisible
    private static Metadata.CustomMetadata toMetadata(String record, Map<String, String> changed) {
        String typeName = record.substringBefore('.');
        String devName = record.substringAfter('.');
        String objectName = typeName + '__mdt';
        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe()
            .fields.getMap();
        List<String> custom = new List<String>();
        for (String f : fields.keySet()) {
            Schema.DescribeFieldResult d = fields.get(f).getDescribe();
            if (d.isCustom()) {
                custom.add(d.getName());
            }
        }
        String label = devName.replace('_', ' ');
        Map<String, Object> values = new Map<String, Object>();
        List<SObject> rows = Database.queryWithBinds(
            'SELECT MasterLabel, ' + String.join(custom, ', ') + ' FROM ' + objectName + ' WHERE DeveloperName = :dev',
            new Map<String, Object>{ 'dev' => devName },
            AccessLevel.SYSTEM_MODE
        );
        if (!rows.isEmpty()) {
            label = (String) rows[0].get('MasterLabel');
            for (String f : custom) {
                values.put(f, rows[0].get(f));
            }
        } else if (typeName == 'NXP_Setting') {
            // A catalogued setting not deployed yet: create it with its description.
            for (List<String> c : CATALOG) {
                if (c[1] == devName) {
                    label = c[2].left(40);
                    values.put('Description__c', c[3].left(255));
                }
            }
        }
        for (String f : changed.keySet()) {
            Schema.DisplayType t = fields.get(f.toLowerCase()).getDescribe().getType();
            String v = changed.get(f);
            values.put(
                f,
                v == null
                    ? null
                    : t == Schema.DisplayType.BOOLEAN
                          ? (Object) Boolean.valueOf(v)
                          : t == Schema.DisplayType.DOUBLE ||
                                t == Schema.DisplayType.INTEGER
                                ? (Object) Decimal.valueOf(v)
                                : (Object) v
            );
        }
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = record;
        md.label = label;
        md.protected_x = false;
        for (String f : values.keySet()) {
            Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
            v.field = f;
            v.value = values.get(f);
            md.values.add(v);
        }
        return md;
    }

    // ------------------------------------------------------------------ health

    @AuraEnabled
    public static List<Check> getHealth() {
        requireAdmin();
        List<Check> out = new List<Check>();

        Check mail = check('mail', 'E-mail delivery');
        try {
            Messaging.reserveSingleEmailCapacity(1);
            ok(mail, 'This org can send e-mail.');
        } catch (System.NoAccessException e) {
            fail(mail, 'Deliverability is not All email, so no alert, digest or problems e-mail is sent.');
            mail.action = '/lightning/setup/OrgEmailSettings/home';
            mail.actionLabel = 'Open Deliverability';
        } catch (Exception e) {
            warn(mail, 'Today\'s e-mail limit may be used up: ' + e.getMessage().left(120));
        }
        out.add(mail);

        Check bell = check('bell', 'Bell notifications');
        try {
            List<SObject> types = Database.query(
                'SELECT Desktop, Mobile FROM CustomNotificationType WHERE DeveloperName = \'NXP_Match_Alert\' LIMIT 1'
            );
            if (types.isEmpty()) {
                fail(bell, 'The NXP Match Alert notification type is missing.');
            } else {
                Boolean desktop = (Boolean) types[0].get('Desktop');
                Boolean mobile = (Boolean) types[0].get('Mobile');
                if (desktop && mobile) {
                    ok(bell, 'NXP Match Alert: desktop and mobile on.');
                } else {
                    warn(
                        bell,
                        'NXP Match Alert: desktop ' +
                            (desktop ? 'on' : 'off') +
                            ', mobile ' +
                            (mobile ? 'on' : 'off') +
                            '.'
                    );
                }
            }
        } catch (Exception e) {
            warn(bell, 'Could not read the notification settings; check them in Setup.');
        }
        if (bell.status != 'ok') {
            bell.action = '/lightning/setup/CustomNotifications/home';
            bell.actionLabel = 'Open Custom Notifications';
        }
        out.add(bell);

        Check sam = check('sam', 'SAM.gov key and feed');
        List<NXP_Feed_Run__c> lastRun = [
            SELECT Status__c, Started__c
            FROM NXP_Feed_Run__c
            WHERE Feed_Name__c = 'SAM_Opportunities'
            ORDER BY Started__c DESC
            LIMIT 1
        ];
        if (lastRun.isEmpty()) {
            warn(sam, 'The SAM.gov feed has never run.');
        } else if (lastRun[0].Status__c == 'Failed') {
            fail(
                sam,
                'The last SAM.gov run failed (' + lastRun[0].Started__c.format('MMM d h:mm a') + '). Test the key.'
            );
        } else {
            ok(
                sam,
                'Last SAM.gov run ' + lastRun[0].Started__c.format('MMM d h:mm a') + ': ' + lastRun[0].Status__c + '.'
            );
        }
        sam.action = 'testKey';
        sam.actionLabel = 'Test the key';
        out.add(sam);

        Check jobs = check('jobs', 'Scheduled jobs');
        Set<String> expected = new Set<String>(EXPECTED_JOBS);
        Set<String> running = new Set<String>();
        String owner;
        for (CronTrigger ct : [
            SELECT CronJobDetail.Name, CreatedBy.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'NXP %'
        ]) {
            running.add(ct.CronJobDetail.Name);
            owner = ct.CreatedBy.Name;
        }
        expected.removeAll(running);
        if (expected.isEmpty()) {
            ok(jobs, EXPECTED_JOBS.size() + ' of ' + EXPECTED_JOBS.size() + ' scheduled, by ' + owner + '.');
        } else {
            fail(jobs, 'Not scheduled: ' + String.join(new List<String>(expected), ', ') + '.');
        }
        jobs.action = 'reschedule';
        jobs.actionLabel = 'Reschedule all';
        out.add(jobs);

        Check saved = check('saved', 'Settings saved here');
        List<Change> drift = releaseDrift();
        if (drift.isEmpty()) {
            ok(saved, 'Everything saved on this screen is in effect.');
        } else {
            List<String> names = new List<String>();
            for (Change c : drift) {
                names.add(c.id.substringAfter('.'));
            }
            warn(
                saved,
                drift.size() +
                    ' setting(s) were put back to the shipped value by a release: ' +
                    String.join(names, ', ') +
                    '.'
            );
            saved.action = 'reapply';
            saved.actionLabel = 'Reapply my settings';
        }
        out.add(saved);

        Check files = check('files', 'SAM.gov file downloads');
        Integer failed = [
            SELECT COUNT()
            FROM NXP_Gov_Notice__c
            WHERE Files_Status__c LIKE '%could not be downloaded%' AND LastModifiedDate = LAST_N_DAYS:7
        ];
        if (failed > 0) {
            warn(
                files,
                failed +
                ' notice(s) in the last 7 days had a file that couldn\'t be downloaded. An "Unauthorized endpoint" needs a Remote Site Setting.'
            );
            files.action = '/lightning/setup/SecurityRemoteProxy/home';
            files.actionLabel = 'Open Remote Site Settings';
        } else {
            ok(files, 'No download problems in the last 7 days.');
        }
        out.add(files);

        Check profile = check('profile', 'Company Profile');
        Integer active = [SELECT COUNT() FROM NXP_Company_Profile__c WHERE Active__c = TRUE];
        if (active == 1) {
            ok(profile, 'One active profile. After changing it, rescore the notices.');
        } else if (active == 0) {
            fail(profile, 'No active Company Profile: every fit score is 0.');
        } else {
            warn(profile, active + ' active profiles: only one is used.');
        }
        profile.action = 'rescore';
        profile.actionLabel = 'Rescore notices';
        out.add(profile);

        Check ai = check('ai', 'AI');
        if (!NXP_Settings.getBoolean('AI_Enabled', false)) {
            warn(ai, 'AI is off. Everything works without it; summaries and the Document Reader don\'t run.');
        } else {
            List<String> missing = missingTemplates();
            if (missing == null) {
                ok(ai, 'AI is on. Prompt templates couldn\'t be listed here; check Prompt Builder.');
            } else if (missing.isEmpty()) {
                ok(ai, 'AI is on and the prompt templates exist.');
            } else {
                warn(ai, 'AI is on, but these prompt templates are missing: ' + String.join(missing, ', ') + '.');
            }
        }
        out.add(ai);
        return out;
    }

    public static final List<String> EXPECTED_JOBS = new List<String>{
        'NXP Feed Scheduler',
        'NXP Daily Digest',
        'NXP Weekly Digest',
        'NXP Notice Analyst :15',
        'NXP Notice Analyst :45',
        'NXP Push Retry',
        'NXP Admin Digest'
    };

    /** One small SAM.gov call (a single record from yesterday) to check the key. */
    @AuraEnabled
    public static String testSamKey() {
        requireAdmin();
        NXP_Feed_Config__mdt cfg = NXP_Feed_Config__mdt.getInstance('SAM_Opportunities');
        if (cfg == null) {
            throw new AuraHandledException('The SAM_Opportunities feed configuration is missing.');
        }
        Date d = Date.today();
        String today =
            String.valueOf(d.month()).leftPad(2, '0') +
            '/' +
            String.valueOf(d.day()).leftPad(2, '0') +
            '/' +
            d.year();
        Date y = d.addDays(-1);
        String yesterday =
            String.valueOf(y.month()).leftPad(2, '0') +
            '/' +
            String.valueOf(y.day()).leftPad(2, '0') +
            '/' +
            y.year();
        try {
            HttpResponse res = new NXP_HttpClient()
                .get(
                    cfg.Named_Credential__c,
                    cfg.Endpoint_Path__c,
                    new Map<String, String>{
                        'postedFrom' => yesterday,
                        'postedTo' => today,
                        'limit' => '1',
                        'offset' => '0'
                    }
                );
            return 'The SAM.gov key works (HTTP ' + res.getStatusCode() + ').';
        } catch (NXP_HttpClient.CalloutFailureException e) {
            String advice = e.statusCode == 401 ||
                e.statusCode == 403
                ? ' The key is wrong or expired, or the parameter isn\'t named ApiKey.'
                : e.statusCode == 429 ? ' The key\'s daily limit is used up.' : '';
            throw new AuraHandledException('SAM.gov answered HTTP ' + e.statusCode + '.' + advice);
        } catch (Exception e) {
            throw new AuraHandledException('SAM.gov could not be reached: ' + e.getMessage());
        }
    }

    /** Stops and reschedules every NXP job, like scripts/post-deploy/schedule-jobs.apex. */
    @AuraEnabled
    public static Integer rescheduleJobs() {
        requireAdmin();
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'NXP %']) {
            System.abortJob(ct.Id);
        }
        NXP_FeedScheduler.scheduleHourly();
        NXP_DigestBatch.scheduleDefaults();
        Type analyst = Type.forName('NXP_NoticeAnalystJob');
        if (analyst != null) {
            System.schedule('NXP Notice Analyst :15', '0 15 * * * ?', (Schedulable) analyst.newInstance());
            System.schedule('NXP Notice Analyst :45', '0 45 * * * ?', (Schedulable) analyst.newInstance());
        }
        System.schedule('NXP Push Retry', '0 20 * * * ?', new NXP_PushRetryJob());
        NXP_AdminDigestJob.scheduleDefaults();
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'NXP %'];
    }

    /** Re-scores open notices in the background (after a Company Profile or fit rule change). */
    @AuraEnabled
    public static Id rescoreNotices() {
        requireAdmin();
        return Database.executeBatch(new NXP_RescoreBatch(), 200);
    }

    // ------------------------------------------------------------------ helpers

    private static void requireAdmin() {
        if (!FeatureManagement.checkPermission('NXP_Admin_Access')) {
            throw new AuraHandledException('The Settings tab is for Nexus admins (NXP Admin Access).');
        }
    }

    private static List<Option> orgWideOptions() {
        List<Option> out = new List<Option>{ new Option('(The admin who scheduled the jobs)', '') };
        for (OrgWideEmailAddress a : [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            ORDER BY Address
            LIMIT 50
        ]) {
            out.add(new Option(a.DisplayName + ' <' + a.Address + '>', a.Id));
        }
        return out;
    }

    /** Prompt templates the settings name that don't exist, or null when they can't be listed. */
    private static List<String> missingTemplates() {
        Set<String> wanted = new Set<String>{
            NXP_Settings.getString('AI_Summary_Template', 'NXP_Solicitation_Summary'),
            NXP_Settings.getString('AI_Change_Template', 'NXP_Amendment_Impact')
        };
        if (NXP_Settings.getBoolean('Document_Analysis_Enabled', false)) {
            wanted.add(NXP_Settings.getString('Document_Analysis_Template', 'NXP_Document_Analysis'));
        }
        try {
            Set<String> found = new Set<String>();
            for (SObject t : Database.query('SELECT DeveloperName FROM GenAiPromptTemplate LIMIT 2000')) {
                found.add((String) t.get('DeveloperName'));
            }
            List<String> missing = new List<String>();
            for (String w : wanted) {
                if (!found.contains(w)) {
                    missing.add(w);
                }
            }
            missing.sort();
            return missing;
        } catch (Exception e) {
            return null;
        }
    }

    private static Item item(
        String id,
        String label,
        String help,
        String type,
        String value,
        String subgroup,
        Boolean managed
    ) {
        Item i = new Item();
        i.id = id;
        i.label = label;
        i.help = help;
        i.type = type;
        i.value = value;
        i.subgroup = subgroup;
        i.releaseManaged = managed;
        return i;
    }

    private static String num(Decimal d) {
        return d == null ? null : String.valueOf(d.intValue());
    }

    private static Check check(String key, String title) {
        Check c = new Check();
        c.key = key;
        c.title = title;
        return c;
    }

    private static void ok(Check c, String detail) {
        c.status = 'ok';
        c.detail = detail;
    }

    private static void warn(Check c, String detail) {
        c.status = 'warn';
        c.detail = detail;
    }

    private static void fail(Check c, String detail) {
        c.status = 'fail';
        c.detail = detail;
    }
}
