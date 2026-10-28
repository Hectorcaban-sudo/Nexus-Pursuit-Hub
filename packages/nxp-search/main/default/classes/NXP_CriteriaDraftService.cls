/**
 * Turns a plain-English request ("DHS and CBP cyber notices, small business or 8(a), over $5M,
 * due in the next 45 days, daily") into draft search criteria without AI. The assistant may use
 * a prompt template instead when AI is enabled; this is the deterministic fallback and the
 * Search Builder's "Draft criteria" button.
 */
public inherited sharing class NXP_CriteriaDraftService {
    public class Draft {
        @AuraEnabled
        public NXP_SearchCriteria criteria;
        @AuraEnabled
        public String criteriaJson;
        @AuraEnabled
        public String frequency;
        @AuraEnabled
        public String summary;
    }

    /** Acronym -> text as it appears in SAM.gov agency paths. Extend as needed. */
    private static final Map<String, String> AGENCIES = new Map<String, String>{
        'dhs' => 'Homeland Security',
        'cbp' => 'Customs and Border Protection',
        'uscis' => 'Citizenship and Immigration',
        'ice' => 'Immigration and Customs Enforcement',
        'fema' => 'Federal Emergency Management',
        'tsa' => 'Transportation Security',
        'cisa' => 'Cybersecurity and Infrastructure',
        'uscg' => 'Coast Guard',
        'dod' => 'Defense',
        'army' => 'Army',
        'navy' => 'Navy',
        'usaf' => 'Air Force',
        'disa' => 'Defense Information Systems',
        'dla' => 'Defense Logistics',
        'va' => 'Veterans Affairs',
        'hhs' => 'Health and Human Services',
        'cms' => 'Medicare',
        'nih' => 'National Institutes of Health',
        'cdc' => 'Disease Control',
        'doe' => 'Energy',
        'doj' => 'Justice',
        'fbi' => 'Federal Bureau of Investigation',
        'gsa' => 'General Services Administration',
        'nasa' => 'National Aeronautics',
        'dot' => 'Transportation',
        'faa' => 'Federal Aviation',
        'usda' => 'Agriculture',
        'treasury' => 'Treasury',
        'irs' => 'Internal Revenue',
        'state' => 'State, Department of',
        'doc' => 'Commerce',
        'noaa' => 'Oceanic and Atmospheric',
        'epa' => 'Environmental Protection',
        'ssa' => 'Social Security',
        'sba' => 'Small Business Administration',
        'dol' => 'Labor',
        'ed' => 'Education',
        'hud' => 'Housing and Urban Development',
        'doi' => 'Interior',
        'opm' => 'Personnel Management'
    };

    private static final Map<String, String> SET_ASIDES = new Map<String, String>{
        'small business' => 'Small Business',
        '8(a)' => '8(a)',
        '8a' => '8(a)',
        'hubzone' => 'HUBZone',
        'sdvosb' => 'Service-Disabled',
        'service-disabled' => 'Service-Disabled',
        'service disabled' => 'Service-Disabled',
        'wosb' => 'Women-Owned',
        'women-owned' => 'Women-Owned',
        'women owned' => 'Women-Owned',
        'edwosb' => 'Economically Disadvantaged'
    };

    private static final Map<String, String> TYPES = new Map<String, String>{
        'sources sought' => 'Sources Sought',
        'rfi' => 'RFI',
        'presolicitation' => 'Pre-solicitation',
        'pre-solicitation' => 'Pre-solicitation',
        'solicitation' => 'Solicitation',
        'award' => 'Award Notice',
        'task order' => 'Task Order',
        'grant' => 'Grant'
    };

    private static final Set<String> STOP = new Set<String>{
        'show',
        'me',
        'find',
        'get',
        'all',
        'any',
        'the',
        'a',
        'an',
        'and',
        'or',
        'of',
        'for',
        'in',
        'on',
        'at',
        'to',
        'with',
        'notices',
        'notice',
        'opportunities',
        'opportunity',
        'contracts',
        'contract',
        'alert',
        'alerts',
        'daily',
        'weekly',
        'real',
        'time',
        'realtime',
        'immediately',
        'due',
        'next',
        'days',
        'day',
        'within',
        'over',
        'above',
        'under',
        'below',
        'more',
        'less',
        'than',
        'million',
        'billion',
        'set',
        'aside',
        'asides',
        'business',
        'small',
        'only',
        'from',
        'by',
        'new',
        'posted',
        'last',
        'naics',
        'psc',
        'agency',
        'agencies',
        'please',
        'i',
        'want',
        'need',
        'looking',
        'search'
    };

    public static Draft draft(String text) {
        NXP_SearchCriteria c = new NXP_SearchCriteria();
        Draft d = new Draft();
        String t = text == null ? '' : text.toLowerCase();
        String rest = ' ' + t + ' ';

        // Frequency
        if (t.contains('real time') || t.contains('realtime') || t.contains('immediately')) {
            d.frequency = 'Real Time';
        } else if (t.contains('weekly')) {
            d.frequency = 'Weekly';
        } else if (t.contains('daily')) {
            d.frequency = 'Daily';
        }

        // NAICS (6 digits) and PSC (letter + 3 alphanumerics, e.g. D302, DA01)
        c.naics = findAll('\\b(\\d{6})\\b', t);
        rest = rest.replaceAll('\\b\\d{6}\\b', ' ');

        // Due within N days
        Matcher due = Pattern.compile('due (?:in|within) (?:the )?(?:next )?(\\d{1,3}) days?').matcher(t);
        if (due.find()) {
            c.dueWithinDays = Integer.valueOf(due.group(1));
            rest = rest.replace(due.group(0), ' ');
        }

        // Value: over/above/under/below $5M, $5 million, $500k, $5,000,000
        Matcher money = Pattern.compile(
                '(over|above|more than|at least|under|below|less than) \\$?([\\d.,]+)\\s*(k|m|mm|b|million|billion|thousand)?'
            )
            .matcher(t);
        while (money.find()) {
            Decimal amount = toAmount(money.group(2), money.group(3));
            if (amount != null) {
                String op = money.group(1);
                if (op == 'under' || op == 'below' || op == 'less than') {
                    c.maxValue = amount;
                } else {
                    c.minValue = amount;
                }
                rest = rest.replace(money.group(0), ' ');
            }
        }

        // Set-asides (longest phrases first)
        c.setAsides = new List<String>();
        for (String key : sortedByLength(SET_ASIDES.keySet())) {
            if (rest.contains(key)) {
                String v = SET_ASIDES.get(key);
                if (!c.setAsides.contains(v)) {
                    c.setAsides.add(v);
                }
                rest = rest.replace(key, ' ');
            }
        }

        // Notice types
        c.noticeTypes = new List<String>();
        for (String key : sortedByLength(TYPES.keySet())) {
            if (Pattern.compile('\\b' + Pattern.quote(key) + 's?\\b').matcher(rest).find()) {
                String v = TYPES.get(key);
                if (!c.noticeTypes.contains(v)) {
                    c.noticeTypes.add(v);
                }
                rest = rest.replaceAll('\\b' + Pattern.quote(key) + 's?\\b', ' ');
            }
        }

        // Agencies by acronym or name
        c.agencies = new List<String>();
        for (String word : rest.split('[^a-z0-9]+')) {
            if (AGENCIES.containsKey(word) && !c.agencies.contains(AGENCIES.get(word))) {
                c.agencies.add(AGENCIES.get(word));
            }
        }
        for (String acronym : AGENCIES.keySet()) {
            rest = rest.replaceAll('\\b' + acronym + '\\b', ' ');
        }

        // Whatever meaningful words remain become keywords (all must match).
        List<String> words = new List<String>();
        for (String w : rest.split('[^a-z0-9()*-]+')) {
            if (String.isNotBlank(w) && !STOP.contains(w) && w.length() > 1 && !w.isNumeric()) {
                words.add(w);
            }
        }
        if (!words.isEmpty()) {
            c.keywords = String.join(words, ' ');
        }
        cleanup(c);
        d.criteria = c;
        d.criteriaJson = c.toJson();
        d.summary = c.describe() + (d.frequency == null ? '' : '; alerts: ' + d.frequency);
        return d;
    }

    private static void cleanup(NXP_SearchCriteria c) {
        if (c.naics != null && c.naics.isEmpty()) {
            c.naics = null;
        }
        if (c.setAsides != null && c.setAsides.isEmpty()) {
            c.setAsides = null;
        }
        if (c.noticeTypes != null && c.noticeTypes.isEmpty()) {
            c.noticeTypes = null;
        }
        if (c.agencies != null && c.agencies.isEmpty()) {
            c.agencies = null;
        }
    }

    private static List<String> findAll(String regex, String text) {
        List<String> out = new List<String>();
        Matcher m = Pattern.compile(regex).matcher(text);
        while (m.find()) {
            if (!out.contains(m.group(1))) {
                out.add(m.group(1));
            }
        }
        return out;
    }

    @TestVisible
    private static Decimal toAmount(String number, String unit) {
        Decimal n = NXP_Json.toDecimal(number.replace(',', ''));
        if (n == null) {
            return null;
        }
        String u = unit == null ? '' : unit;
        if (u == 'k' || u == 'thousand') {
            return n * 1000;
        }
        if (u == 'm' || u == 'mm' || u == 'million') {
            return n * 1000000;
        }
        if (u == 'b' || u == 'billion') {
            return n * 1000000000;
        }
        return n;
    }

    private static List<String> sortedByLength(Set<String> keys) {
        List<String> list1 = new List<String>(keys);
        // Simple insertion sort, longest first; the sets are small.
        for (Integer i = 1; i < list1.size(); i++) {
            String k = list1[i];
            Integer j = i - 1;
            while (j >= 0 && list1[j].length() < k.length()) {
                list1[j + 1] = list1[j];
                j--;
            }
            list1[j + 1] = k;
        }
        return list1;
    }
}
