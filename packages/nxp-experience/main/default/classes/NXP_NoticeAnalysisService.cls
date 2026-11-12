/**
 * Analyze this notice: a bid / no-bid brief, an opportunity SWOT, the incumbent and competitors,
 * requirement gaps, win themes or teaming partners for one notice.
 *
 * Apex gathers the facts from Nexus data (the notice, fit reasons, the Company Profile, vehicles
 * we hold, award history, the Document Reader results and the version history), each labelled with
 * its source. The model (one call, NXP_Notice_Analysis prompt template) answers from those facts only
 * and tags every point with a source label or marks it as an assumption to check. Without AI the
 * facts are still shown. Used by the notice page and by the assistant's actions.
 */
public with sharing class NXP_NoticeAnalysisService {
    public class Fact {
        @AuraEnabled
        public String source;
        @AuraEnabled
        public String text;
        public Fact() {
            this.source = null;
        }
        public Fact(String source, String text) {
            this.source = source;
            this.text = text;
        }
    }

    public class Item {
        @AuraEnabled
        public String text;
        @AuraEnabled
        public List<String> sources = new List<String>();
        /** No fact supports it: an assumption to check. */
        @AuraEnabled
        public Boolean assumption = false;
    }

    public class Section {
        @AuraEnabled
        public String title;
        @AuraEnabled
        public List<Item> items = new List<Item>();
    }

    public class Strategy {
        @AuraEnabled
        public Integer rank;
        @AuraEnabled
        public String text;
        @AuraEnabled
        public String pairs;
        @AuraEnabled
        public String impact;
        @AuraEnabled
        public String effort;
        @AuraEnabled
        public String firstStep;
    }

    public class Kind {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        public Kind() {
            this.key = null;
        }
        public Kind(String key, String label) {
            this.key = key;
            this.label = label;
        }
    }

    public class Analysis {
        @AuraEnabled
        public String kind;
        @AuraEnabled
        public String label;
        /** Bid, Lean bid, Lean no-bid or No-bid (bid / no-bid brief only). */
        @AuraEnabled
        public String verdict;
        @AuraEnabled
        public String summary;
        @AuraEnabled
        public String confidence;
        @AuraEnabled
        public List<Section> sections = new List<Section>();
        @AuraEnabled
        public List<Strategy> strategies = new List<Strategy>();
        /** The facts the answer was built from. */
        @AuraEnabled
        public List<Fact> facts = new List<Fact>();
        @AuraEnabled
        public Boolean aiUsed = false;
        /** Why there is no AI part, or why it is shown as plain text. */
        @AuraEnabled
        public String note;
        /** The model's answer when it could not be read as JSON. */
        @AuraEnabled
        public String text;
        @AuraEnabled
        public Datetime generatedAt;
    }

    /** key -> label, then what to answer and which sections to return. */
    @TestVisible
    private static final Map<String, List<String>> KINDS = new Map<String, List<String>>{
        'brief' => new List<String>{
            'Bid / no-bid brief',
            'Recommend whether to bid. Set "verdict" to exactly one of: Bid, Lean bid, Lean no-bid, No-bid, and "confidence" to low, medium or high. "summary": one or two sentences with the conditions that would change the decision. Sections: "Reasons to bid", "Reasons not to bid", "What would change the decision". "strategies": the top 3 next steps, ranked.'
        },
        'swot' => new List<String>{
            'Opportunity SWOT',
            'Write a SWOT for us on this opportunity. Strengths and weaknesses are about us against this notice; opportunities and threats are outside conditions (customer, incumbent, competitors, timing). Sections: "Strengths", "Weaknesses", "Opportunities", "Threats", 2 to 4 items each. "strategies": the top 5 strategies, ranked by impact and effort, each pairing a strength or weakness with an opportunity or threat ("pairs", e.g. "Strength + Threat").'
        },
        'competitors' => new List<String>{
            'Incumbent and competitors',
            'Describe the incumbent and the likely bidders, using only vendors named in the facts. Sections: "Incumbent", "Likely bidders", "How we compare". "summary": one sentence. No strategies.'
        },
        'gaps' => new List<String>{
            'Requirements we may not meet',
            'Compare the requirements in the facts with our Company Profile and vehicles. Sections: "Requirements we meet", "Requirements we may not meet", "Questions to ask the contracting officer". "summary": one sentence. No strategies.'
        },
        'themes' => new List<String>{
            'Win themes',
            'Draft win themes for our response. Sections: "Win themes" (each with its proof point), "Discriminators", "Incumbent weaknesses to address". "summary": one sentence. No strategies.'
        },
        'teaming' => new List<String>{
            'Teaming partners',
            'Suggest what a teaming partner should bring and who it could be, using only vendors named in the facts. Sections: "Gaps a partner should fill", "Candidate partners", "Questions before teaming". "summary": one sentence. No strategies.'
        }
    };

    private static final List<String> ORDER = new List<String>{
        'brief',
        'swot',
        'competitors',
        'gaps',
        'themes',
        'teaming'
    };

    private static final String FORMAT =
        '\n\nAnswer only from the facts below. Each fact starts with its source label in square brackets. ' +
        'Tag every item with the labels of the facts it rests on. If no fact supports an item, give it no sources ' +
        'and set "assumption": true. Never invent vendors, dates, amounts or requirements. ' +
        'Return only JSON, no prose, in this shape: {"verdict": "", "confidence": "", "summary": "", ' +
        '"sections": [{"title": "", "items": [{"text": "", "sources": [""], "assumption": false}]}], ' +
        '"strategies": [{"rank": 1, "text": "", "pairs": "", "impact": "High|Medium|Low", "effort": "High|Medium|Low", "firstStep": ""}]}';

    @TestVisible
    private static NXP_NoticeAnalyzer analyzerOverride;

    public static NXP_NoticeAnalyzer analyzer() {
        if (analyzerOverride != null) {
            return analyzerOverride;
        }
        Type t = Type.forName('NXP_NoticeAnalysisAi');
        return t == null ? null : (NXP_NoticeAnalyzer) t.newInstance();
    }

    public static Boolean isKind(String key) {
        return key != null && KINDS.containsKey(key);
    }

    public static List<Kind> kinds() {
        List<Kind> out = new List<Kind>();
        for (String key : ORDER) {
            out.add(new Kind(key, KINDS.get(key)[0]));
        }
        return out;
    }

    /** One analysis of a notice: facts always, the AI part when AI is available. */
    public static Analysis analyze(Id noticeId, String kind) {
        if (!KINDS.containsKey(kind)) {
            throw new AnalysisException('Unknown analysis: ' + kind);
        }
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            throw new AnalysisException('Notice not found or not visible to you.');
        }
        Analysis a = new Analysis();
        a.kind = kind;
        a.label = KINDS.get(kind)[0];
        a.generatedAt = Datetime.now();
        a.facts = facts(n);
        NXP_NoticeAnalyzer ai = analyzer();
        if (ai == null || !ai.isEnabled()) {
            a.note = 'AI is off, or today\'s AI limit is used up: these are the facts Nexus has for this notice.';
            return a;
        }
        String raw = ai.analyze(n.Id, KINDS.get(kind)[1] + FORMAT, factsText(a.facts));
        a.aiUsed = true;
        read(raw, a);
        return a;
    }

    // ------------------------------------------------------------------ facts

    /** The facts Nexus has for a notice, each with its source label. No AI. */
    public static List<Fact> facts(NXP_Gov_Notice__c n) {
        List<Fact> out = new List<Fact>();
        Date today = Date.today();
        List<String> basics = new List<String>{ 'Title: ' + n.Title__c };
        basics.add('Notice type: ' + n.Notice_Type__c);
        basics.add('Agency: ' + n.Agency_Path__c);
        basics.add('NAICS: ' + n.NAICS_Code__c + '; PSC: ' + n.PSC_Code__c);
        basics.add('Set-aside: ' + (String.isBlank(n.Set_Aside__c) ? 'none (full and open)' : n.Set_Aside__c));
        basics.add(
            'Estimated value: ' + (n.Estimated_Value__c == null ? 'not published' : '$' + n.Estimated_Value__c.format())
        );
        if (n.Response_Due__c != null) {
            basics.add(
                'Response due: ' +
                    n.Response_Due__c.format('MMM d, yyyy') +
                    ' (' +
                    today.daysBetween(n.Response_Due__c.date()) +
                    ' days from today)'
            );
        }
        if (n.Contract_Vehicle_Code__c != null) {
            basics.add('Contract vehicle: ' + n.Contract_Vehicle_Code__c);
        }
        out.add(new Fact('Notice', String.join(basics, '. ')));
        if (String.isNotBlank(n.Description__c) && !n.Description__c.startsWith('http')) {
            out.add(new Fact('Notice description', n.Description__c.left(3000)));
        }
        if (String.isNotBlank(n.AI_Summary__c)) {
            out.add(new Fact('Notice summary', n.AI_Summary__c.left(1500)));
        }

        if (String.isNotBlank(n.Fit_Breakdown__c)) {
            List<String> reasons = new List<String>();
            try {
                for (Object o : (List<Object>) JSON.deserializeUntyped(n.Fit_Breakdown__c)) {
                    Map<String, Object> r = (Map<String, Object>) o;
                    reasons.add(
                        r.get('rule') + ' ' + r.get('points') + ' of ' + r.get('weight') + ': ' + r.get('reason')
                    );
                }
            } catch (Exception e) {
                reasons.clear();
            }
            if (!reasons.isEmpty()) {
                out.add(new Fact('Fit reasons', 'Fit ' + n.Fit_Score__c + '. ' + String.join(reasons, '; ')));
            }
        }

        List<NXP_Company_Profile__c> profiles = [
            SELECT NAICS_Codes__c, PSC_Codes__c, Set_Asides__c, Keywords__c, Target_Agency_Codes__c
            FROM NXP_Company_Profile__c
            WHERE Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!profiles.isEmpty()) {
            NXP_Company_Profile__c p = profiles[0];
            out.add(
                new Fact(
                    'Company Profile',
                    ('Our NAICS: ' +
                        flat(p.NAICS_Codes__c) +
                        '. Our capabilities and keywords: ' +
                        flat(p.Keywords__c) +
                        '. Our set-aside eligibility: ' +
                        flat(p.Set_Asides__c) +
                        '. Target agencies: ' +
                        flat(p.Target_Agency_Codes__c))
                        .left(2000)
                )
            );
        }

        List<String> held = new List<String>();
        for (NXP_Contract_Vehicle__c v : [
            SELECT Name, Vehicle_Code__c, Expiry_Date__c
            FROM NXP_Contract_Vehicle__c
            WHERE We_Hold__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 25
        ]) {
            held.add(v.Name + (v.Expiry_Date__c == null ? '' : ' (expires ' + v.Expiry_Date__c.format() + ')'));
        }
        if (!held.isEmpty()) {
            out.add(new Fact('Contract vehicles', 'Vehicles we hold: ' + String.join(held, ', ')));
        }

        if (n.Predecessor_Award__c != null) {
            for (NXP_Award_Summary__c a : [
                SELECT PIID__c, Vendor__r.Name, Obligated_Amount__c, Ceiling__c, Period_Start__c, Period_End__c
                FROM NXP_Award_Summary__c
                WHERE Id = :n.Predecessor_Award__c
                WITH USER_MODE
            ]) {
                out.add(new Fact('Incumbent', 'Predecessor award ' + award(a)));
            }
        } else if (n.Incumbent__c != null) {
            out.add(new Fact('Incumbent', 'Incumbent named on the notice: ' + n.Incumbent__r.Name));
        }

        if (n.Agency__c != null && String.isNotBlank(n.NAICS_Code__c)) {
            Date since = today.addYears(-5);
            List<String> leaders = new List<String>();
            for (AggregateResult r : [
                SELECT Vendor__r.Name vendorName, COUNT(Id) awardCount, SUM(Obligated_Amount__c) obligated
                FROM NXP_Award_Summary__c
                WHERE
                    Agency__c = :n.Agency__c
                    AND NAICS_Code__c = :n.NAICS_Code__c
                    AND Vendor__c != NULL
                    AND Period_Start__c >= :since
                WITH USER_MODE
                GROUP BY Vendor__r.Name
                ORDER BY SUM(Obligated_Amount__c) DESC NULLS LAST
                LIMIT 6
            ]) {
                Decimal total = (Decimal) r.get('obligated');
                leaders.add(
                    r.get('vendorName') +
                        ': ' +
                        r.get('awardCount') +
                        ' awards' +
                        (total == null ? '' : ', $' + total.setScale(0).format() + ' obligated')
                );
            }
            if (!leaders.isEmpty()) {
                out.add(
                    new Fact(
                        'Award history',
                        'Vendors with the most awards at this agency in NAICS ' +
                            n.NAICS_Code__c +
                            ' since ' +
                            since.year() +
                            ': ' +
                            String.join(leaders, '; ')
                    )
                );
            }
            Date fromDate = today.addMonths(-6);
            Date toDate = today.addMonths(18);
            List<String> ending = new List<String>();
            for (NXP_Award_Summary__c a : [
                SELECT PIID__c, Vendor__r.Name, Obligated_Amount__c, Ceiling__c, Period_Start__c, Period_End__c
                FROM NXP_Award_Summary__c
                WHERE
                    Agency__c = :n.Agency__c
                    AND NAICS_Code__c = :n.NAICS_Code__c
                    AND Period_End__c >= :fromDate
                    AND Period_End__c <= :toDate
                WITH USER_MODE
                ORDER BY Obligated_Amount__c DESC NULLS LAST
                LIMIT 5
            ]) {
                ending.add(award(a));
            }
            if (!ending.isEmpty()) {
                out.add(
                    new Fact(
                        'Award history',
                        'Awards at this agency and NAICS ending soon: ' + String.join(ending, '; ')
                    )
                );
            }
        }

        for (NXP_Document_Analysis__c d : [
            SELECT File_Name__c, Result_Json__c
            FROM NXP_Document_Analysis__c
            WHERE Gov_Notice__c = :n.Id AND Status__c = 'Complete' AND Result_Json__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Analyzed__c DESC
            LIMIT 3
        ]) {
            String text = documentText(d.Result_Json__c);
            if (String.isNotBlank(text)) {
                out.add(new Fact('Document: ' + d.File_Name__c, text.left(3000)));
            }
        }

        if (n.Version_Count__c != null && n.Version_Count__c > 1) {
            out.add(
                new Fact(
                    'Version history',
                    (n.Version_Count__c.intValue() - 1) +
                        ' amendment(s); last change: ' +
                        (n.Last_Change_Type__c == null ? 'unknown' : n.Last_Change_Type__c)
                )
            );
        }
        return out;
    }

    /** The facts as the model gets them: one per line, source label first. */
    public static String factsText(List<Fact> facts) {
        List<String> lines = new List<String>();
        for (Fact f : facts) {
            lines.add('[' + f.source + '] ' + f.text);
        }
        return String.join(lines, '\n').left(30000);
    }

    private static String award(NXP_Award_Summary__c a) {
        return a.PIID__c +
            ' held by ' +
            (a.Vendor__r == null ? 'an unknown vendor' : a.Vendor__r.Name) +
            (a.Obligated_Amount__c == null ? '' : ', $' + a.Obligated_Amount__c.setScale(0).format() + ' obligated') +
            (a.Period_End__c == null ? '' : ', ends ' + a.Period_End__c.format());
    }

    private static String flat(String s) {
        return String.isBlank(s) ? 'not set' : s.replaceAll('[\\r\\n]+', ', ');
    }

    /** Summary, requirements, evaluation factors, key dates and risks from a Document Reader result. */
    private static String documentText(String resultJson) {
        Map<String, Object> r;
        try {
            r = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        } catch (Exception e) {
            return null;
        }
        List<String> parts = new List<String>();
        Map<String, String> labels = new Map<String, String>{
            'summary' => 'Summary',
            'requirements' => 'Requirements',
            'evaluationFactors' => 'Evaluation factors',
            'keyDates' => 'Key dates',
            'risks' => 'Risks'
        };
        for (String key : labels.keySet()) {
            Object v = r.get(key);
            if (v == null) {
                continue;
            }
            String text;
            if (v instanceof List<Object>) {
                List<String> items = new List<String>();
                for (Object o : (List<Object>) v) {
                    items.add(o instanceof String ? (String) o : JSON.serialize(o));
                    if (items.size() == 12) {
                        break;
                    }
                }
                text = String.join(items, '; ');
            } else {
                text = v instanceof String ? (String) v : JSON.serialize(v);
            }
            if (String.isNotBlank(text)) {
                parts.add(labels.get(key) + ': ' + text);
            }
        }
        return String.join(parts, '. ');
    }

    // ------------------------------------------------------------------ the answer

    /** Reads the model's JSON into the analysis; keeps the text when it isn't JSON. */
    @TestVisible
    private static void read(String raw, Analysis a) {
        if (String.isBlank(raw)) {
            a.note = 'The AI returned nothing. The facts are below.';
            return;
        }
        Map<String, Object> m;
        try {
            Integer start = raw.indexOf('{');
            Integer stop = raw.lastIndexOf('}');
            m = (Map<String, Object>) JSON.deserializeUntyped(raw.substring(start, stop + 1));
        } catch (Exception e) {
            a.text = raw;
            a.note = 'Shown as text: the AI did not return the expected format.';
            return;
        }
        Set<String> labels = new Set<String>();
        for (Fact f : a.facts) {
            labels.add(f.source.toLowerCase());
        }
        a.verdict = str(m.get('verdict'));
        a.confidence = str(m.get('confidence'));
        a.summary = str(m.get('summary'));
        for (Object so : asList(m.get('sections'))) {
            Map<String, Object> sm = (Map<String, Object>) so;
            Section s = new Section();
            s.title = str(sm.get('title'));
            for (Object io : asList(sm.get('items'))) {
                Item item = new Item();
                if (io instanceof String) {
                    item.text = (String) io;
                } else {
                    Map<String, Object> im = (Map<String, Object>) io;
                    item.text = str(im.get('text'));
                    for (Object src : asList(im.get('sources'))) {
                        String label = str(src);
                        // Only labels of facts we gave count as sources.
                        if (String.isNotBlank(label) && labels.contains(label.toLowerCase())) {
                            item.sources.add(label);
                        }
                    }
                }
                item.assumption = item.sources.isEmpty();
                if (String.isNotBlank(item.text)) {
                    s.items.add(item);
                }
            }
            if (String.isNotBlank(s.title) && !s.items.isEmpty()) {
                a.sections.add(s);
            }
        }
        Integer rank = 0;
        for (Object o : asList(m.get('strategies'))) {
            Map<String, Object> sm = (Map<String, Object>) o;
            Strategy s = new Strategy();
            rank++;
            s.rank = rank;
            s.text = str(sm.get('text'));
            s.pairs = str(sm.get('pairs'));
            s.impact = str(sm.get('impact'));
            s.effort = str(sm.get('effort'));
            s.firstStep = str(sm.get('firstStep'));
            if (String.isNotBlank(s.text)) {
                a.strategies.add(s);
            }
        }
    }

    private static String str(Object o) {
        return o == null ? null : String.valueOf(o).trim();
    }

    private static List<Object> asList(Object o) {
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
    }

    // ------------------------------------------------------------------ text and saving

    /** The analysis as plain text (Markdown), for Copy, saving to the notice and the assistant. */
    public static String toText(Analysis a, NXP_Gov_Notice__c n) {
        List<String> lines = new List<String>{ '# ' + a.label + ': ' + (n == null ? '' : n.Title__c) };
        lines.add(
            'Nexus Pursuit Hub, ' +
                a.generatedAt.format('MMM d, yyyy h:mm a') +
                (a.aiUsed ? '. AI draft: check items marked (assumption).' : '. Facts only.')
        );
        if (String.isNotBlank(a.verdict)) {
            lines.add('');
            lines.add(
                '**' + a.verdict + '**' + (String.isBlank(a.confidence) ? '' : ' (confidence: ' + a.confidence + ')')
            );
        }
        if (String.isNotBlank(a.summary)) {
            lines.add('');
            lines.add(a.summary);
        }
        for (Section s : a.sections) {
            lines.add('');
            lines.add('## ' + s.title);
            for (Item i : s.items) {
                lines.add('- ' + i.text + (i.assumption ? ' (assumption)' : ' [' + String.join(i.sources, ', ') + ']'));
            }
        }
        if (!a.strategies.isEmpty()) {
            lines.add('');
            lines.add('## Top strategies');
            for (Strategy s : a.strategies) {
                lines.add(
                    s.rank +
                        '. ' +
                        s.text +
                        ' (' +
                        s.pairs +
                        '; impact ' +
                        s.impact +
                        ', effort ' +
                        s.effort +
                        '). First step: ' +
                        s.firstStep
                );
            }
        }
        if (String.isNotBlank(a.text)) {
            lines.add('');
            lines.add(a.text);
        }
        lines.add('');
        lines.add('## Facts used');
        for (Fact f : a.facts) {
            lines.add('- [' + f.source + '] ' + f.text);
        }
        return String.join(lines, '\n');
    }

    /** Saves the analysis as a file on the notice; it goes with the notice when it is pushed. */
    public static Id save(Id noticeId, Analysis a) {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            throw new AnalysisException('Notice not found or not visible to you.');
        }
        if (a.generatedAt == null) {
            a.generatedAt = Datetime.now();
        }
        ContentVersion v = new ContentVersion(
            Title = (a.label + ' ' + a.generatedAt.format('yyyy-MM-dd')).left(255),
            PathOnClient = 'nexus-' + a.kind + '.md',
            VersionData = Blob.valueOf(toText(a, n)),
            FirstPublishLocationId = noticeId
        );
        insert as user v;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id WITH SYSTEM_MODE].ContentDocumentId;
    }

    public class AnalysisException extends Exception {
    }
}
