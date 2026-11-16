/**
 * Analysis playbooks: analyses your organization writes (NXP_Analysis_Playbook__c) and runs on a
 * notice from Analyze this notice, next to the six Nexus analyses.
 *
 * A playbook is ordered steps (instructions to the model), the output sections, whether to ask for a
 * verdict and ranked strategies, and which Nexus facts it may use. Running one gathers those facts in
 * Apex (as NXP_NoticeAnalysisService does, plus the Price-to-Win figures and vendor profiles when
 * chosen), sends steps and facts to the model in one call, and reads the answer with the same
 * source checks: every point must cite a fact it was given, or it is marked as an assumption.
 *
 * Who edits: users with the NXP_Power_User or NXP_Admin_Access custom permission. Everyone with the
 * app sees published playbooks. Definitions are read and written in system mode after that check,
 * so BD users need no object permissions; the notice data itself is read in user mode.
 */
public with sharing class NXP_AnalysisPlaybookService {
    public static final String PREFIX = 'pb:';
    public static final Integer MAX_STEPS = 12;
    public static final List<String> SOURCES = new List<String>{
        'Notice',
        'Documents',
        'Fit reasons',
        'Incumbent',
        'Award history',
        'Price-to-Win',
        'Vendor profiles',
        'Company Profile',
        'Contract vehicles',
        'Version history'
    };

    @TestVisible
    private static Boolean canEditOverride;

    public class Step {
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String text;
    }

    /** A playbook as the Analyses tab edits it. */
    public class Definition {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String category;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer version;
        @AuraEnabled
        public List<Step> steps = new List<Step>();
        /** Output section titles; empty = one section per step. */
        @AuraEnabled
        public List<String> sections = new List<String>();
        @AuraEnabled
        public List<String> sources = new List<String>();
        @AuraEnabled
        public Boolean askVerdict = false;
        @AuraEnabled
        public Boolean askStrategies = false;
        @AuraEnabled
        public Integer timesUsed;
        @AuraEnabled
        public String ownerName;
        @AuraEnabled
        public Datetime lastModified;
        @AuraEnabled
        public Datetime publishedOn;
        @AuraEnabled
        public String changeNote;
    }

    public class VersionNote {
        @AuraEnabled
        public Integer version;
        @AuraEnabled
        public String note;
        @AuraEnabled
        public String byName;
        @AuraEnabled
        public Datetime changedOn;
    }

    // ------------------------------------------------------------------ who can edit

    public static Boolean canEdit() {
        if (canEditOverride != null) {
            return canEditOverride;
        }
        return FeatureManagement.checkPermission('NXP_Power_User') ||
            FeatureManagement.checkPermission('NXP_Admin_Access');
    }

    private static void requireEdit() {
        if (!canEdit()) {
            throw new PlaybookException('Only Power Users and Nexus admins can change analysis playbooks.');
        }
    }

    // ------------------------------------------------------------------ reading

    private static List<NXP_Analysis_Playbook__c> query(String whereClause, Map<String, Object> binds) {
        return Database.queryWithBinds(
            'SELECT Id, Name, Key__c, Category__c, Description__c, Status__c, Version__c, Steps__c, Sections__c,' +
                ' Sources__c, Ask_Verdict__c, Ask_Strategies__c, Times_Used__c, Owner.Name, LastModifiedDate,' +
                ' Published_On__c, Change_Note__c FROM NXP_Analysis_Playbook__c ' +
                whereClause +
                ' ORDER BY Category__c, Name LIMIT 200',
            binds,
            AccessLevel.SYSTEM_MODE
        );
    }

    /** Published playbooks as chips for Analyze this notice. */
    public static List<NXP_NoticeAnalysisService.Kind> publishedKinds() {
        List<NXP_NoticeAnalysisService.Kind> out = new List<NXP_NoticeAnalysisService.Kind>();
        for (NXP_Analysis_Playbook__c p : query('WHERE Status__c = \'Published\'', new Map<String, Object>())) {
            NXP_NoticeAnalysisService.Kind k = new NXP_NoticeAnalysisService.Kind(PREFIX + p.Key__c, p.Name);
            k.category = p.Category__c;
            k.description = p.Description__c;
            k.org = true;
            k.version = p.Version__c == null ? 0 : p.Version__c.intValue();
            k.sources = sourcesOf(p);
            out.add(k);
        }
        return out;
    }

    /** All playbooks for the Analyses tab: published for everyone, drafts and retired for editors. */
    public static List<Definition> library() {
        String whereClause = canEdit() ? 'WHERE Id != null' : 'WHERE Status__c = \'Published\'';
        List<Definition> out = new List<Definition>();
        for (NXP_Analysis_Playbook__c p : query(whereClause, new Map<String, Object>())) {
            out.add(toDefinition(p));
        }
        return out;
    }

    public static Definition get(Id playbookId) {
        List<NXP_Analysis_Playbook__c> rows = query('WHERE Id = :id', new Map<String, Object>{ 'id' => playbookId });
        if (rows.isEmpty() || (rows[0].Status__c != 'Published' && !canEdit())) {
            throw new PlaybookException('Playbook not found.');
        }
        return toDefinition(rows[0]);
    }

    /** Published versions with their change notes, newest first (from field history). */
    public static List<VersionNote> versions(Id playbookId) {
        List<VersionNote> out = new List<VersionNote>();
        Map<Datetime, VersionNote> byTime = new Map<Datetime, VersionNote>();
        for (NXP_Analysis_Playbook__History h : [
            SELECT Field, NewValue, CreatedDate, CreatedBy.Name
            FROM NXP_Analysis_Playbook__History
            WHERE ParentId = :playbookId AND Field IN ('Version__c', 'Change_Note__c')
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            VersionNote v = byTime.containsKey(h.CreatedDate) ? byTime.get(h.CreatedDate) : new VersionNote();
            v.changedOn = h.CreatedDate;
            v.byName = h.CreatedBy.Name;
            if (h.Field == 'Version__c' && h.NewValue != null) {
                v.version = Integer.valueOf(String.valueOf(h.NewValue));
            } else if (h.Field == 'Change_Note__c' && h.NewValue != null) {
                v.note = String.valueOf(h.NewValue);
            }
            if (!byTime.containsKey(h.CreatedDate)) {
                byTime.put(h.CreatedDate, v);
                out.add(v);
            }
        }
        List<VersionNote> published = new List<VersionNote>();
        for (VersionNote v : out) {
            if (v.version != null) {
                published.add(v);
            }
        }
        return published;
    }

    private static Definition toDefinition(NXP_Analysis_Playbook__c p) {
        Definition d = new Definition();
        d.id = p.Id;
        d.key = p.Key__c;
        d.name = p.Name;
        d.category = p.Category__c;
        d.description = p.Description__c;
        d.status = p.Status__c;
        d.version = p.Version__c == null ? 0 : p.Version__c.intValue();
        d.steps = stepsOf(p.Steps__c);
        d.sections = linesOf(p.Sections__c);
        d.sources = sourcesOf(p);
        d.askVerdict = p.Ask_Verdict__c;
        d.askStrategies = p.Ask_Strategies__c;
        d.timesUsed = p.Times_Used__c == null ? 0 : p.Times_Used__c.intValue();
        d.ownerName = p.Owner == null ? null : p.Owner.Name;
        d.lastModified = p.LastModifiedDate;
        d.publishedOn = p.Published_On__c;
        d.changeNote = p.Change_Note__c;
        return d;
    }

    private static List<Step> stepsOf(String raw) {
        if (String.isBlank(raw)) {
            return new List<Step>();
        }
        try {
            return (List<Step>) System.JSON.deserialize(raw, List<Step>.class);
        } catch (Exception e) {
            Step s = new Step();
            s.title = 'Instructions';
            s.text = raw;
            return new List<Step>{ s };
        }
    }

    private static List<String> linesOf(String text) {
        List<String> out = new List<String>();
        if (String.isBlank(text)) {
            return out;
        }
        for (String line : text.split('\n')) {
            if (String.isNotBlank(line)) {
                out.add(line.trim());
            }
        }
        return out;
    }

    private static List<String> sourcesOf(NXP_Analysis_Playbook__c p) {
        return String.isBlank(p.Sources__c) ? new List<String>() : p.Sources__c.split(';');
    }

    // ------------------------------------------------------------------ saving

    /**
     * Saves a playbook. publish = true makes it the next published version (everyone sees it);
     * otherwise it is saved as a draft. A published playbook changes only by publishing again.
     */
    public static Definition save(Definition d, Boolean publish, String changeNote) {
        requireEdit();
        validate(d);
        NXP_Analysis_Playbook__c p;
        if (d.id != null) {
            List<NXP_Analysis_Playbook__c> rows = query('WHERE Id = :id', new Map<String, Object>{ 'id' => d.id });
            if (rows.isEmpty()) {
                throw new PlaybookException('Playbook not found.');
            }
            p = rows[0];
            if (p.Status__c == 'Published' && !publish) {
                throw new PlaybookException(
                    'This playbook is published: publish a new version, or unpublish it first to keep editing a draft.'
                );
            }
        } else {
            p = new NXP_Analysis_Playbook__c(Key__c = newKey(d.name), Status__c = 'Draft', Version__c = 0);
        }
        p.Name = d.name.trim().left(80);
        p.Category__c = String.isBlank(d.category) ? 'Capture' : d.category;
        p.Description__c = d.description == null ? null : d.description.trim().left(255);
        p.Steps__c = System.JSON.serialize(cleanSteps(d.steps));
        p.Sections__c = d.sections == null ? null : String.join(d.sections, '\n').left(2000);
        p.Sources__c = String.join(d.sources, ';');
        p.Ask_Verdict__c = d.askVerdict == true;
        p.Ask_Strategies__c = d.askStrategies == true;
        if (publish) {
            p.Status__c = 'Published';
            p.Version__c = (p.Version__c == null ? 0 : p.Version__c) + 1;
            p.Published_On__c = Datetime.now();
            p.Change_Note__c = String.isBlank(changeNote)
                ? (p.Version__c == 1 ? 'First version' : 'Updated')
                : changeNote.trim().left(255);
        }
        upsert as system p;
        return get(p.Id);
    }

    /** Draft (unpublish), Published (publish the saved definition as is, as a new version) or Retired. */
    public static Definition setStatus(Id playbookId, String status) {
        requireEdit();
        if (status != 'Draft' && status != 'Retired') {
            throw new PlaybookException('Use Publish to publish a playbook.');
        }
        update as system new NXP_Analysis_Playbook__c(Id = playbookId, Status__c = status);
        return get(playbookId);
    }

    /** A new draft copied from a Nexus analysis (brief, swot, ...) or from another playbook. */
    public static Definition copy(String source) {
        requireEdit();
        Definition d = new Definition();
        if (NXP_NoticeAnalysisService.instructionsOf(source) == null && source != null && source instanceof Id) {
            Definition other = get((Id) source);
            other.id = null;
            other.name = (other.name + ' (copy)').left(80);
            return save(other, false, null);
        }
        String instructions = NXP_NoticeAnalysisService.instructionsOf(source);
        if (instructions == null) {
            throw new PlaybookException('Nothing to copy: ' + source);
        }
        for (NXP_NoticeAnalysisService.Kind k : NXP_NoticeAnalysisService.defaultKinds()) {
            if (k.key == source) {
                d.name = (k.label + ' (our version)').left(80);
                d.category = k.category;
                d.description = k.description;
                d.sources = k.sources;
            }
        }
        Step s = new Step();
        s.title = 'Instructions';
        s.text = instructions;
        d.steps.add(s);
        d.askVerdict = source == 'brief';
        d.askStrategies = source == 'brief' || source == 'swot';
        return save(d, false, null);
    }

    private static void validate(Definition d) {
        if (d == null || String.isBlank(d.name)) {
            throw new PlaybookException('Give the playbook a name.');
        }
        List<Step> steps = cleanSteps(d.steps);
        if (steps.isEmpty()) {
            throw new PlaybookException('Add at least one step.');
        }
        if (steps.size() > MAX_STEPS) {
            throw new PlaybookException('Use at most ' + MAX_STEPS + ' steps.');
        }
        Integer length = 0;
        for (Step s : steps) {
            length += s.text.length() + (s.title == null ? 0 : s.title.length());
        }
        if (length > 8000) {
            throw new PlaybookException('The steps are too long (8,000 characters at most). Shorten them.');
        }
        if (d.sources == null || d.sources.isEmpty()) {
            throw new PlaybookException('Choose at least one kind of fact it can use.');
        }
        for (String src : d.sources) {
            if (!SOURCES.contains(src)) {
                throw new PlaybookException('Unknown fact source: ' + src);
            }
        }
    }

    private static List<Step> cleanSteps(List<Step> steps) {
        List<Step> out = new List<Step>();
        for (Step s : steps == null ? new List<Step>() : steps) {
            if (s != null && String.isNotBlank(s.text)) {
                s.text = s.text.trim();
                s.title = String.isBlank(s.title) ? null : s.title.trim().left(120);
                out.add(s);
            }
        }
        return out;
    }

    private static String newKey(String name) {
        String base = name.toLowerCase().replaceAll('[^a-z0-9]+', '-').removeStart('-').removeEnd('-').left(60);
        String suffix = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(6);
        return (String.isBlank(base) ? 'playbook' : base) + '-' + suffix;
    }

    // ------------------------------------------------------------------ running

    /** Runs a published playbook on a notice (Analyze this notice, the assistant). */
    public static NXP_NoticeAnalysisService.Analysis run(Id noticeId, String key) {
        List<NXP_Analysis_Playbook__c> rows = query('WHERE Key__c = :key', new Map<String, Object>{ 'key' => key });
        if (rows.isEmpty() || (rows[0].Status__c != 'Published' && !canEdit())) {
            throw new NXP_NoticeAnalysisService.AnalysisException('This analysis playbook is not available.');
        }
        NXP_NoticeAnalysisService.Analysis a = runDefinition(noticeId, toDefinition(rows[0]));
        if (a.aiUsed && rows[0].Status__c == 'Published') {
            update as system new NXP_Analysis_Playbook__c(
                Id = rows[0].Id,
                Times_Used__c = (rows[0].Times_Used__c == null ? 0 : rows[0].Times_Used__c) + 1
            );
        }
        return a;
    }

    /** Test on a notice from the editor: the definition as it is on screen, saved or not. */
    public static NXP_NoticeAnalysisService.Analysis testRun(Id noticeId, Definition d) {
        requireEdit();
        validate(d);
        NXP_NoticeAnalysisService.Analysis a = runDefinition(noticeId, d);
        a.note = (a.note == null ? '' : a.note + ' ') + 'Test run: not saved.';
        return a;
    }

    private static NXP_NoticeAnalysisService.Analysis runDefinition(Id noticeId, Definition d) {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            throw new NXP_NoticeAnalysisService.AnalysisException('Notice not found or not visible to you.');
        }
        NXP_NoticeAnalysisService.Analysis a = new NXP_NoticeAnalysisService.Analysis();
        a.kind = PREFIX + (d.key == null ? 'test' : d.key);
        a.label = d.name + (d.version != null && d.version > 0 ? ' (v' + d.version + ')' : ' (draft)');
        a.generatedAt = Datetime.now();
        a.facts = facts(n, new Set<String>(d.sources));
        NXP_NoticeAnalyzer ai = NXP_NoticeAnalysisService.analyzer();
        if (ai == null || !ai.isEnabled()) {
            a.note = 'AI is off, or today\'s AI limit is used up: these are the facts this playbook would use.';
            return a;
        }
        String raw = ai.analyze(n.Id, question(d), NXP_NoticeAnalysisService.factsText(a.facts));
        a.aiUsed = true;
        NXP_NoticeAnalysisService.read(raw, a);
        return a;
    }

    /** The instructions sent to the model: the steps in order, then the output rules and format. */
    @TestVisible
    private static String question(Definition d) {
        List<String> lines = new List<String>{ 'You are helping our capture team. Work through these steps in order:' };
        Integer i = 0;
        for (Step s : cleanSteps(d.steps)) {
            i++;
            lines.add(i + '. ' + (s.title == null ? '' : s.title + ': ') + s.text);
        }
        lines.add('');
        if (d.sections != null && !d.sections.isEmpty()) {
            List<String> quoted = new List<String>();
            for (String t : d.sections) {
                quoted.add('"' + t.replace('"', '\'') + '"');
            }
            lines.add('Return these sections, in this order: ' + String.join(quoted, ', ') + '.');
        } else {
            lines.add('Return one section per step, titled like the step.');
        }
        lines.add('"summary": two or three sentences for a busy reader.');
        lines.add(
            d.askVerdict == true
                ? 'Set "verdict" to exactly one of: Bid, Lean bid, Lean no-bid, No-bid, and "confidence" to low, medium or high.'
                : 'Leave "verdict" and "confidence" empty.'
        );
        lines.add(
            d.askStrategies == true
                ? '"strategies": the top 3 to 5 actions, ranked by impact and effort, each with a first step.'
                : 'No strategies.'
        );
        return String.join(lines, '\n') + NXP_NoticeAnalysisService.FORMAT;
    }

    // ------------------------------------------------------------------ facts

    /** The Nexus facts, kept to the sources the playbook chose, plus Price-to-Win and vendor profiles. */
    @TestVisible
    private static List<NXP_NoticeAnalysisService.Fact> facts(NXP_Gov_Notice__c n, Set<String> sources) {
        List<NXP_NoticeAnalysisService.Fact> out = new List<NXP_NoticeAnalysisService.Fact>();
        for (NXP_NoticeAnalysisService.Fact f : NXP_NoticeAnalysisService.facts(n)) {
            if (sources.contains(groupOf(f.source))) {
                out.add(f);
            }
        }
        if (sources.contains('Price-to-Win')) {
            NXP_NoticeAnalysisService.Fact f = priceFact(n.Id);
            if (f != null) {
                out.add(f);
            }
        }
        if (sources.contains('Vendor profiles')) {
            out.addAll(vendorFacts(n));
        }
        return out;
    }

    @TestVisible
    private static String groupOf(String factSource) {
        if (factSource == null) {
            return null;
        }
        if (factSource.startsWith('Notice')) {
            return 'Notice';
        }
        if (factSource.startsWith('Document')) {
            return 'Documents';
        }
        return factSource;
    }

    private static NXP_NoticeAnalysisService.Fact priceFact(Id noticeId) {
        NXP_PriceToWinService.Result r;
        try {
            r = NXP_PriceToWinService.analyze(noticeId, null);
        } catch (Exception e) {
            return null;
        }
        if (r == null || !r.enabled || r.scopeKey == null) {
            return null;
        }
        List<String> parts = new List<String>{
            'Compared with ' +
            r.scopeLabel +
            ': ' +
            r.count +
            ' awards started in the last ' +
            r.lookbackYears +
            ' years'
        };
        if (r.enough) {
            parts.add(
                'spend per year low ' +
                    money(r.low) +
                    ', median ' +
                    money(r.median) +
                    ', high ' +
                    money(r.high) +
                    ', middle half ' +
                    money(r.q1) +
                    ' to ' +
                    money(r.q3)
            );
        }
        if (r.predecessor != null && r.predecessor.perYear != null) {
            parts.add(
                'predecessor ' +
                    r.predecessor.piid +
                    ' (' +
                    r.predecessor.vendorName +
                    ') spends ' +
                    money(r.predecessor.perYear) +
                    ' a year'
            );
        }
        if (r.hold != null && r.hold.matched > 0) {
            parts.add(
                'estimated incumbent hold: ' +
                    r.hold.kept +
                    ' of ' +
                    r.hold.matched +
                    ' ended contracts went to the same vendor'
            );
        }
        if (r.estimate != null && r.estimate.count > 0) {
            parts.add(
                'similar-awards estimate ' + money(r.estimate.perYear) + ' a year from ' + r.estimate.count + ' awards'
            );
        }
        parts.add('these are past award values, not winning bid prices');
        return new NXP_NoticeAnalysisService.Fact('Price-to-Win', String.join(parts, '; '));
    }

    /** The incumbent and the vendors with the most awards here: where else they win, last 5 years. */
    private static List<NXP_NoticeAnalysisService.Fact> vendorFacts(NXP_Gov_Notice__c n) {
        List<NXP_NoticeAnalysisService.Fact> out = new List<NXP_NoticeAnalysisService.Fact>();
        Date since = Date.today().addYears(-5);
        Set<Id> vendorIds = new Set<Id>();
        if (n.Incumbent__c != null) {
            vendorIds.add(n.Incumbent__c);
        }
        if (n.Agency__c != null && String.isNotBlank(n.NAICS_Code__c)) {
            for (AggregateResult r : [
                SELECT Vendor__c vendorId, COUNT(Id) awardCount
                FROM NXP_Award_Summary__c
                WHERE
                    Agency__c = :n.Agency__c
                    AND NAICS_Code__c = :n.NAICS_Code__c
                    AND Vendor__c != NULL
                    AND Period_Start__c >= :since
                WITH USER_MODE
                GROUP BY Vendor__c
                ORDER BY COUNT(Id) DESC
                LIMIT 5
            ]) {
                vendorIds.add((Id) r.get('vendorId'));
            }
        }
        if (vendorIds.isEmpty()) {
            return out;
        }
        Map<String, List<String>> byVendor = new Map<String, List<String>>();
        Map<String, Integer> totals = new Map<String, Integer>();
        for (AggregateResult r : [
            SELECT
                Vendor__r.Name vendorName,
                Agency__r.Name agencyName,
                COUNT(Id) awardCount,
                SUM(Obligated_Amount__c) total
            FROM NXP_Award_Summary__c
            WHERE Vendor__c IN :vendorIds AND Period_Start__c >= :since
            WITH USER_MODE
            GROUP BY Vendor__r.Name, Agency__r.Name
            ORDER BY COUNT(Id) DESC
            LIMIT 60
        ]) {
            String v = (String) r.get('vendorName');
            Integer c = (Integer) r.get('awardCount');
            if (!byVendor.containsKey(v)) {
                byVendor.put(v, new List<String>());
                totals.put(v, 0);
            }
            totals.put(v, totals.get(v) + c);
            if (byVendor.get(v).size() < 3) {
                Decimal total = (Decimal) r.get('total');
                byVendor.get(v)
                    .add(
                        (r.get('agencyName') == null ? 'unknown agency' : (String) r.get('agencyName')) +
                            ' (' +
                            c +
                            (total == null ? '' : ', ' + money(total)) +
                            ')'
                    );
            }
        }
        for (String v : byVendor.keySet()) {
            out.add(
                new NXP_NoticeAnalysisService.Fact(
                    'Vendor profile: ' + v,
                    v +
                        ' has ' +
                        totals.get(v) +
                        ' awards in Nexus since ' +
                        since.year() +
                        '; most at ' +
                        String.join(byVendor.get(v), '; ')
                )
            );
        }
        return out;
    }

    private static String money(Decimal v) {
        if (v == null) {
            return 'unknown';
        }
        if (Math.abs(v) >= 1000000) {
            return '$' + (v / 1000000).setScale(2) + 'M';
        }
        return '$' + v.setScale(0).format();
    }

    public class PlaybookException extends Exception {
    }
}
