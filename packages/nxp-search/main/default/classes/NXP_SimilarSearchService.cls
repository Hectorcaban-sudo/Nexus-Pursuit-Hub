/**
 * Find similar: builds the starting point for a saved search from one notice. Buyer, NAICS, PSC,
 * set-aside and notice types come straight from the notice, each with a narrower and a wider
 * choice; keywords come from the AI (NXP_KeywordSuggester) when it's on, otherwise from the
 * distinctive words of the title. The user ticks and edits the choices, previews and saves.
 */
public inherited sharing class NXP_SimilarSearchService {
    public class Choice {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public Boolean selected = false;
    }

    public class ChoiceGroup {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String helpText;
        /** true: tick several (notice types); false: pick one or none. */
        @AuraEnabled
        public Boolean multiple = false;
        @AuraEnabled
        public List<Choice> choices = new List<Choice>();
    }

    public class Draft {
        @AuraEnabled
        public Id noticeId;
        @AuraEnabled
        public String noticeTitle;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<ChoiceGroup> groups = new List<ChoiceGroup>();
        @AuraEnabled
        public String keywords;
        /** AI, Title or None. */
        @AuraEnabled
        public String keywordsSource = 'None';
        @AuraEnabled
        public String note;
    }

    public static final List<String> TYPES = new List<String>{
        'Pre-solicitation',
        'Sources Sought',
        'RFI',
        'Solicitation',
        'Combined Synopsis/Solicitation',
        'Task Order'
    };

    /** Common words in titles that say nothing about the work. */
    @TestVisible
    private static final Set<String> GENERIC = new Set<String>{
        'the',
        'and',
        'for',
        'with',
        'from',
        'into',
        'its',
        'our',
        'all',
        'any',
        'new',
        'via',
        'per',
        'support',
        'supports',
        'services',
        'service',
        'engineering',
        'management',
        'program',
        'programs',
        'system',
        'systems',
        'solution',
        'solutions',
        'technical',
        'professional',
        'operations',
        'operational',
        'maintenance',
        'contract',
        'contracts',
        'requirement',
        'requirements',
        'acquisition',
        'procurement',
        'project',
        'projects',
        'task',
        'order',
        'orders',
        'sources',
        'sought',
        'notice',
        'rfi',
        'rfq',
        'rfp',
        'request',
        'information',
        'intent',
        'award',
        'office',
        'department',
        'agency',
        'federal',
        'government',
        'national',
        'center',
        'centre',
        'division',
        'branch',
        'various',
        'other',
        'general',
        'related',
        'including',
        'equipment',
        'supplies',
        'year',
        'years',
        'option',
        'base',
        'phase',
        'amendment',
        'combined',
        'synopsis',
        'solicitation',
        'presolicitation',
        'pre',
        'brand',
        'name',
        'only',
        'small',
        'business',
        'set',
        'aside',
        'total'
    };

    @TestVisible
    private static NXP_KeywordSuggester suggesterOverride;

    public static Draft draft(Id noticeId) {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            throw new AuraHandledException('Notice not found or not visible to you.');
        }
        Draft d = new Draft();
        d.noticeId = n.Id;
        d.noticeTitle = n.Title__c;
        d.name = NXP_Text.truncate('Like: ' + (String.isBlank(n.Title__c) ? n.Notice_Id__c : n.Title__c), 80);

        // Buyer: the sub-agency (narrow) or the department (wide).
        List<String> path = new List<String>();
        if (String.isNotBlank(n.Agency_Path__c)) {
            for (String part : n.Agency_Path__c.split('›')) {
                if (String.isNotBlank(part)) {
                    path.add(part.trim());
                }
            }
        }
        if (!path.isEmpty()) {
            ChoiceGroup g = newGroup('buyer', 'Buyer', 'The sub-agency is narrower; the department is wider');
            if (path.size() > 1) {
                g.choices.add(choice(path[path.size() - 1], path[path.size() - 1], true));
                g.choices.add(choice('All of ' + path[0], path[0], false));
            } else {
                g.choices.add(choice(path[0], path[0], true));
            }
            d.groups.add(g);
        }

        if (String.isNotBlank(n.NAICS_Code__c)) {
            ChoiceGroup g = newGroup('naics', 'NAICS', 'The family catches related work');
            g.choices.add(choice(n.NAICS_Code__c + ' only', n.NAICS_Code__c, false));
            if (n.NAICS_Code__c.length() >= 4) {
                g.choices.add(choice(n.NAICS_Code__c.left(4) + '* (family)', n.NAICS_Code__c.left(4) + '*', true));
            } else {
                g.choices[0].selected = true;
            }
            d.groups.add(g);
        }

        if (String.isNotBlank(n.PSC_Code__c)) {
            ChoiceGroup g = newGroup('psc', 'PSC', '');
            g.choices.add(choice(n.PSC_Code__c + ' only', n.PSC_Code__c, true));
            if (n.PSC_Code__c.length() >= 2) {
                g.choices.add(choice(n.PSC_Code__c.left(2) + '* (family)', n.PSC_Code__c.left(2) + '*', false));
            }
            d.groups.add(g);
        }

        String setAside = setAsideValue(n.Set_Aside__c);
        if (setAside != null) {
            ChoiceGroup g = newGroup('setAside', 'Set-aside', 'From the notice');
            g.choices.add(choice(setAside, setAside, true));
            d.groups.add(g);
        }

        ChoiceGroup typeGroup = newGroup('noticeTypes', 'Notice type', 'Early signals are included');
        typeGroup.multiple = true;
        Set<String> picked = new Set<String>{ 'Pre-solicitation', 'Sources Sought', 'Solicitation' };
        if (String.isNotBlank(n.Notice_Type__c)) {
            picked.add(n.Notice_Type__c);
        }
        List<String> typeList = new List<String>(TYPES);
        if (String.isNotBlank(n.Notice_Type__c) && !typeList.contains(n.Notice_Type__c)) {
            typeList.add(n.Notice_Type__c);
        }
        for (String t : typeList) {
            typeGroup.choices.add(choice(t, t, picked.contains(t)));
        }
        d.groups.add(typeGroup);

        keywords(d, n);
        return d;
    }

    private static void keywords(Draft d, NXP_Gov_Notice__c n) {
        NXP_KeywordSuggester ai = suggester();
        if (ai != null && ai.isEnabled()) {
            try {
                String expr = clean(ai.suggest(n.Id));
                if (String.isNotBlank(expr)) {
                    new NXP_KeywordExpression(expr);
                    d.keywords = expr;
                    d.keywordsSource = 'AI';
                    return;
                }
            } catch (Exception e) {
                d.note = 'The AI keywords could not be used, so they come from the title.';
                NXP_Logger.warn('NXP_SimilarSearchService', 'AI keywords failed for ' + n.Id + ': ' + e.getMessage());
            }
        }
        d.keywords = titleKeywords(n.Title__c);
        d.keywordsSource = String.isBlank(d.keywords) ? 'None' : 'Title';
    }

    /** Up to three distinctive title words, all required: "zero AND trust AND architecture". */
    public static String titleKeywords(String title) {
        if (String.isBlank(title)) {
            return null;
        }
        List<String> words = new List<String>();
        for (String w : title.toLowerCase().split('[^a-z0-9]+')) {
            if (w.length() >= 3 && !w.isNumeric() && !GENERIC.contains(w) && !words.contains(w)) {
                words.add(w);
            }
            if (words.size() == 3) {
                break;
            }
        }
        return words.isEmpty() ? null : String.join(words, ' AND ');
    }

    /** Strips code fences, labels and outer quotes a model may add around the expression. */
    @TestVisible
    private static String clean(String text) {
        if (text == null) {
            return null;
        }
        String s = text.trim();
        if (s.contains('```')) {
            s = s.substringAfter('```').substringBefore('```').trim();
        }
        s = s.removeStartIgnoreCase('keywords:').trim();
        if (s.startsWith('\'') && s.endsWith('\'') && s.length() > 1) {
            s = s.substring(1, s.length() - 1);
        }
        s = s.replaceAll('\\s+', ' ').trim();
        return s.length() > 500 ? null : s;
    }

    @TestVisible
    private static String setAsideValue(String setAside) {
        if (String.isBlank(setAside) || setAside.containsIgnoreCase('none') || setAside.containsIgnoreCase('no set')) {
            return null;
        }
        if (setAside.contains('8(a)') || setAside.containsIgnoreCase('8a ')) {
            return '8(a)';
        }
        if (setAside.containsIgnoreCase('hubzone')) {
            return 'HUBZone';
        }
        if (setAside.containsIgnoreCase('service-disabled') || setAside.containsIgnoreCase('sdvosb')) {
            return 'Service-Disabled';
        }
        if (setAside.containsIgnoreCase('women')) {
            return 'Women-Owned';
        }
        if (setAside.containsIgnoreCase('small business')) {
            return 'Small Business';
        }
        return null;
    }

    private static NXP_KeywordSuggester suggester() {
        if (suggesterOverride != null) {
            return suggesterOverride;
        }
        Type t = Type.forName('NXP_SimilarKeywordsAi');
        return t == null ? null : (NXP_KeywordSuggester) t.newInstance();
    }

    private static ChoiceGroup newGroup(String key, String label, String helpText) {
        ChoiceGroup g = new ChoiceGroup();
        g.key = key;
        g.label = label;
        g.helpText = helpText;
        return g;
    }

    private static Choice choice(String label, String value, Boolean selected) {
        Choice c = new Choice();
        c.label = label;
        c.value = value;
        c.selected = selected;
        return c;
    }
}
