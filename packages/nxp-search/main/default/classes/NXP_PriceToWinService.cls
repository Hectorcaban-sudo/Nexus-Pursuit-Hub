/**
 * Price-to-Win panel on the notice page: what this kind of work has sold for, from the Award
 * Summaries in Nexus. Plain statistics, no AI calls, so the same notice always shows the same numbers.
 *
 * - Values are compared per year: spend so far (Obligated) divided by the years the award has run,
 *   at least one year, so a 2-year and a 5-year contract line up. Ceiling is used only when no
 *   obligation is known, divided by the full period.
 * - Scopes: the notice's agency + NAICS, its department + NAICS, the NAICS across all agencies,
 *   or the agency across all our NAICS. Awards that started within the look-back window only.
 * - Incumbent hold is estimated: for awards that ended, the follow-on is the award at the same
 *   agency and NAICS that started closest to the end date (90 days before to 180 days after).
 * - Similar-awards estimate: a nearest-neighbour median over the 20 most similar awards (NAICS,
 *   agency, PSC, title words, recency). Used when a scope has too few awards for a range.
 *
 * Public data only has the winners, so nothing here is a chance of winning.
 * Reads run in user mode: a user sees statistics over the awards they can see.
 */
public with sharing class NXP_PriceToWinService {
    public static final String SCOPE_AGENCY = 'agency';
    public static final String SCOPE_DEPARTMENT = 'department';
    public static final String SCOPE_NAICS = 'naics';
    public static final String SCOPE_AGENCY_ALL = 'agencyAll';
    public static final List<String> SCOPE_KEYS = new List<String>{
        SCOPE_AGENCY,
        SCOPE_DEPARTMENT,
        SCOPE_NAICS,
        SCOPE_AGENCY_ALL
    };

    private static final Integer MAX_AWARDS = 2000;
    private static final Integer NEIGHBOURS = 20;
    private static final Decimal MIN_SIMILARITY = 2;
    private static final Integer SUCCESSOR_DAYS_BEFORE = 90;
    private static final Integer SUCCESSOR_DAYS_AFTER = 180;
    private static final Set<String> STOP_WORDS = new Set<String>{
        'with',
        'from',
        'that',
        'this',
        'support',
        'services',
        'service',
        'contract',
        'program',
        'requirement',
        'requirements',
        'agency',
        'office',
        'department',
        'federal',
        'other',
        'various',
        'task',
        'order',
        'solicitation',
        'notice',
        'base',
        'year',
        'years',
        'option',
        'options',
        'and/or'
    };

    // ------------------------------------------------------------------------------- shapes

    public class Award {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String piid;
        @AuraEnabled
        public Id vendorId;
        @AuraEnabled
        public String vendorName;
        @AuraEnabled
        public Id agencyId;
        @AuraEnabled
        public String agencyName;
        @AuraEnabled
        public String naics;
        @AuraEnabled
        public String psc;
        @AuraEnabled
        public Date periodStart;
        @AuraEnabled
        public Date periodEnd;
        @AuraEnabled
        public Decimal obligated;
        @AuraEnabled
        public Decimal ceiling;
        /** Years the per-year value is divided by (at least 1). */
        @AuraEnabled
        public Decimal years;
        @AuraEnabled
        public Decimal perYear;
        @AuraEnabled
        public Boolean inRange = false;
        @AuraEnabled
        public Boolean isPredecessor = false;
        @AuraEnabled
        public Decimal similarity;
        public transient Id departmentId;
        public transient String words;
    }

    public class Scope {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Integer count = 0;
        @AuraEnabled
        public Boolean available = false;
        @AuraEnabled
        public Boolean selected = false;
    }

    public class HoldExample {
        @AuraEnabled
        public String vendorName;
        @AuraEnabled
        public String fromPiid;
        @AuraEnabled
        public String toPiid;
        @AuraEnabled
        public String toVendorName;
        @AuraEnabled
        public Date endedOn;
        @AuraEnabled
        public Boolean kept;
    }

    public class Hold {
        /** Ended awards whose follow-on was found. */
        @AuraEnabled
        public Integer matched = 0;
        /** Of those, how many went to the same vendor. */
        @AuraEnabled
        public Integer kept = 0;
        @AuraEnabled
        public String incumbentName;
        @AuraEnabled
        public Integer incumbentMatched = 0;
        @AuraEnabled
        public Integer incumbentKept = 0;
        @AuraEnabled
        public List<HoldExample> examples = new List<HoldExample>();
    }

    public class Estimate {
        @AuraEnabled
        public Integer count = 0;
        @AuraEnabled
        public Decimal perYear;
        @AuraEnabled
        public Decimal low;
        @AuraEnabled
        public Decimal high;
        @AuraEnabled
        public List<Award> basis = new List<Award>();
    }

    public class Result {
        @AuraEnabled
        public Boolean enabled = true;
        @AuraEnabled
        public Id noticeId;
        @AuraEnabled
        public String scopeKey;
        @AuraEnabled
        public String scopeLabel;
        @AuraEnabled
        public List<Scope> scopes = new List<Scope>();
        @AuraEnabled
        public Integer lookbackYears;
        @AuraEnabled
        public Integer minAwards;
        @AuraEnabled
        public Integer count = 0;
        /** True when the scope has at least minAwards awards: low, quartiles and high are set. */
        @AuraEnabled
        public Boolean enough = false;
        @AuraEnabled
        public Decimal low;
        @AuraEnabled
        public Decimal q1;
        @AuraEnabled
        public Decimal median;
        @AuraEnabled
        public Decimal q3;
        @AuraEnabled
        public Decimal high;
        @AuraEnabled
        public Award predecessor;
        /** Years of performance assumed for this notice (the predecessor's length, else 5). */
        @AuraEnabled
        public Integer noticeYears;
        @AuraEnabled
        public String noticeYearsSource;
        @AuraEnabled
        public Hold hold = new Hold();
        @AuraEnabled
        public Estimate estimate = new Estimate();
        /** Every per-year value in the scope, lowest first (for Compare a price). */
        @AuraEnabled
        public List<Decimal> values = new List<Decimal>();
        /** Newest awards in the scope (up to 10). */
        @AuraEnabled
        public List<Award> awards = new List<Award>();
        @AuraEnabled
        public String note;
        @AuraEnabled
        public Date dataThrough;
    }

    // ------------------------------------------------------------------------------- entry

    public static Result analyze(Id noticeId, String scopeKey) {
        Result r = new Result();
        r.noticeId = noticeId;
        r.enabled = NXP_Settings.getBoolean('Price_Check_Enabled', true);
        r.lookbackYears = Math.max(1, NXP_Settings.getInteger('Price_Check_Lookback_Years', 5));
        r.minAwards = Math.max(2, NXP_Settings.getInteger('Price_Check_Min_Awards', 5));
        if (!r.enabled) {
            r.note = 'Price-to-Win is off. An admin turns it on in Settings (Price_Check_Enabled).';
            return r;
        }
        List<NXP_Gov_Notice__c> notices = [
            SELECT
                Id,
                Title__c,
                NAICS_Code__c,
                PSC_Code__c,
                Agency__c,
                Agency__r.Name,
                Agency__r.Parent_Agency__c,
                Agency__r.Parent_Agency__r.Name,
                Predecessor_Award__c,
                Incumbent__c,
                Incumbent__r.Name
            FROM NXP_Gov_Notice__c
            WHERE Id = :noticeId
            WITH USER_MODE
        ];
        if (notices.isEmpty()) {
            throw new IllegalArgumentException('Notice not found or not visible to you.');
        }
        NXP_Gov_Notice__c n = notices[0];
        Date since = Date.today().addYears(-r.lookbackYears);
        String naics = String.isBlank(n.NAICS_Code__c) ? null : n.NAICS_Code__c.trim();
        Id agencyId = n.Agency__c;
        Id departmentId = n.Agency__r == null ? null : n.Agency__r.Parent_Agency__c;

        // Scopes and their sizes.
        Map<String, String> labels = new Map<String, String>{
            SCOPE_AGENCY => 'NAICS + ' + shortName(n.Agency__r == null ? null : n.Agency__r.Name),
            SCOPE_DEPARTMENT => 'NAICS + ' +
            shortName(
                n.Agency__r == null || n.Agency__r.Parent_Agency__r == null ? null : n.Agency__r.Parent_Agency__r.Name
            ),
            SCOPE_NAICS => 'NAICS, all agencies',
            SCOPE_AGENCY_ALL => shortName(n.Agency__r == null ? null : n.Agency__r.Name) + ', all our NAICS'
        };
        Map<String, Boolean> possible = new Map<String, Boolean>{
            SCOPE_AGENCY => naics != null &&
            agencyId != null,
            SCOPE_DEPARTMENT => naics != null &&
            departmentId != null,
            SCOPE_NAICS => naics != null,
            SCOPE_AGENCY_ALL => agencyId != null
        };
        String preferred = String.isNotBlank(scopeKey)
            ? scopeKey
            : NXP_Settings.getString('Price_Check_Default_Scope', SCOPE_AGENCY);
        String chosen = null;
        for (String key : SCOPE_KEYS) {
            Scope s = new Scope();
            s.key = key;
            s.label = labels.get(key);
            s.available = possible.get(key);
            if (s.available) {
                s.count = countAwards(key, naics, agencyId, departmentId, since);
            }
            r.scopes.add(s);
        }
        // The asked-for scope if it can be computed; else the first with enough awards; else the first possible.
        for (Scope s : r.scopes) {
            if (s.key == preferred && s.available && (String.isNotBlank(scopeKey) || s.count >= r.minAwards)) {
                chosen = s.key;
            }
        }
        for (Scope s : r.scopes) {
            if (chosen == null && s.available && s.count >= r.minAwards) {
                chosen = s.key;
            }
        }
        for (Scope s : r.scopes) {
            if (chosen == null && s.available) {
                chosen = s.key;
            }
        }

        // Predecessor contract (always shown, in or out of the scope).
        if (n.Predecessor_Award__c != null) {
            List<Award> pred = toAwards(
                [
                    SELECT
                        Id,
                        Name,
                        PIID__c,
                        Vendor__c,
                        Vendor__r.Name,
                        Agency__c,
                        Agency__r.Name,
                        Agency__r.Parent_Agency__c,
                        NAICS_Code__c,
                        PSC_Code__c,
                        Period_Start__c,
                        Period_End__c,
                        Obligated_Amount__c,
                        Ceiling__c
                    FROM NXP_Award_Summary__c
                    WHERE Id = :n.Predecessor_Award__c
                    WITH USER_MODE
                ],
                false
            );
            if (!pred.isEmpty()) {
                r.predecessor = pred[0];
                r.predecessor.isPredecessor = true;
            }
        }
        r.noticeYears = 5;
        r.noticeYearsSource = 'default';
        if (r.predecessor != null && r.predecessor.periodStart != null && r.predecessor.periodEnd != null) {
            Decimal full = r.predecessor.periodStart.daysBetween(r.predecessor.periodEnd) / 365.25;
            r.noticeYears = Math.max(1, Math.min(10, full.round(System.RoundingMode.HALF_UP).intValue()));
            r.noticeYearsSource = 'predecessor';
        }

        if (chosen == null) {
            r.note = 'This notice has no NAICS code or agency, so there is nothing to compare it with.';
            return r;
        }
        r.scopeKey = chosen;
        r.scopeLabel = labels.get(chosen);
        for (Scope s : r.scopes) {
            s.selected = s.key == chosen;
        }

        List<Award> awards = toAwards(queryAwards(chosen, naics, agencyId, departmentId, since), false);
        r.count = awards.size();
        List<Decimal> values = new List<Decimal>();
        for (Award a : awards) {
            values.add(a.perYear);
            if (r.predecessor != null && a.id == r.predecessor.id) {
                a.isPredecessor = true;
            }
            if (r.dataThrough == null || (a.periodStart != null && a.periodStart > r.dataThrough)) {
                r.dataThrough = a.periodStart;
            }
        }
        values.sort();
        r.values = values;
        if (r.count >= r.minAwards) {
            r.enough = true;
            r.low = values[0];
            r.q1 = percentile(values, 0.25);
            r.median = percentile(values, 0.5);
            r.q3 = percentile(values, 0.75);
            r.high = values[values.size() - 1];
            for (Award a : awards) {
                a.inRange = a.perYear >= r.q1 && a.perYear <= r.q3;
            }
        } else {
            r.note =
                'Only ' +
                r.count +
                (r.count == 1 ? ' comparable award' : ' comparable awards') +
                ' here; a range needs ' +
                r.minAwards +
                '. Try a wider comparison, or use the similar-awards estimate.';
        }

        Id incumbentId = n.Incumbent__c != null
            ? n.Incumbent__c
            : (r.predecessor == null ? null : r.predecessor.vendorId);
        String incumbentName = n.Incumbent__r != null
            ? n.Incumbent__r.Name
            : (r.predecessor == null ? null : r.predecessor.vendorName);
        r.hold = hold(awards, incumbentId, incumbentName);

        // Newest first, up to 10, for the table.
        List<Award> newest = new List<Award>(awards);
        newest.sort(new NewestFirst());
        for (Integer i = 0; i < newest.size() && i < 10; i++) {
            r.awards.add(newest[i]);
        }

        r.estimate = estimate(n, naics, agencyId, departmentId, since);
        return r;
    }

    // ------------------------------------------------------------------------------- queries

    private static Integer countAwards(String key, String naics, Id agencyId, Id departmentId, Date since) {
        String soql =
            'SELECT COUNT() FROM NXP_Award_Summary__c WHERE ' +
            scopeFilter(key) +
            ' AND Period_Start__c >= :since AND Period_Start__c <= TODAY' +
            ' AND (Obligated_Amount__c > 0 OR Ceiling__c > 0)';
        return Database.countQueryWithBinds(soql, binds(naics, agencyId, departmentId, since), AccessLevel.USER_MODE);
    }

    private static List<NXP_Award_Summary__c> queryAwards(
        String key,
        String naics,
        Id agencyId,
        Id departmentId,
        Date since
    ) {
        String soql =
            'SELECT Id, Name, PIID__c, Vendor__c, Vendor__r.Name, Agency__c, Agency__r.Name, Agency__r.Parent_Agency__c,' +
            ' NAICS_Code__c, PSC_Code__c, Period_Start__c, Period_End__c, Obligated_Amount__c, Ceiling__c' +
            ' FROM NXP_Award_Summary__c WHERE ' +
            scopeFilter(key) +
            ' AND Period_Start__c >= :since AND Period_Start__c <= TODAY' +
            ' AND (Obligated_Amount__c > 0 OR Ceiling__c > 0)' +
            ' ORDER BY Period_Start__c DESC LIMIT ' +
            MAX_AWARDS;
        return Database.queryWithBinds(soql, binds(naics, agencyId, departmentId, since), AccessLevel.USER_MODE);
    }

    private static String scopeFilter(String key) {
        if (key == SCOPE_AGENCY) {
            return 'Agency__c = :agencyId AND NAICS_Code__c = :naics';
        }
        if (key == SCOPE_DEPARTMENT) {
            return '(Agency__c = :departmentId OR Agency__r.Parent_Agency__c = :departmentId) AND NAICS_Code__c = :naics';
        }
        if (key == SCOPE_NAICS) {
            return 'NAICS_Code__c = :naics';
        }
        return 'Agency__c = :agencyId';
    }

    private static Map<String, Object> binds(String naics, Id agencyId, Id departmentId, Date since) {
        return new Map<String, Object>{
            'naics' => naics,
            'agencyId' => agencyId,
            'departmentId' => departmentId,
            'since' => since
        };
    }

    // ------------------------------------------------------------------------------- per year

    private static List<Award> toAwards(List<NXP_Award_Summary__c> rows, Boolean withWords) {
        List<Award> out = new List<Award>();
        for (NXP_Award_Summary__c row : rows) {
            Award a = new Award();
            a.id = row.Id;
            a.name = row.Name;
            a.piid = row.PIID__c;
            a.vendorId = row.Vendor__c;
            a.vendorName = row.Vendor__r == null ? null : row.Vendor__r.Name;
            a.agencyId = row.Agency__c;
            a.agencyName = row.Agency__r == null ? null : row.Agency__r.Name;
            a.departmentId = row.Agency__r == null ? null : row.Agency__r.Parent_Agency__c;
            a.naics = row.NAICS_Code__c;
            a.psc = row.PSC_Code__c;
            a.periodStart = row.Period_Start__c;
            a.periodEnd = row.Period_End__c;
            a.obligated = row.Obligated_Amount__c;
            a.ceiling = row.Ceiling__c;
            perYear(a);
            if (a.perYear == null) {
                continue;
            }
            if (withWords) {
                a.words = (row.Name == null ? '' : row.Name).toLowerCase();
            }
            out.add(a);
        }
        return out;
    }

    /** Spend per year: Obligated over the years run so far (at least 1); else Ceiling over the full period. */
    @TestVisible
    private static void perYear(Award a) {
        if (a.periodStart == null || a.periodStart > Date.today()) {
            return;
        }
        if (a.obligated != null && a.obligated > 0) {
            Date stop = a.periodEnd == null || a.periodEnd > Date.today() ? Date.today() : a.periodEnd;
            a.years = Math.max(1.0, a.periodStart.daysBetween(stop) / 365.25).setScale(1);
            a.perYear = (a.obligated / a.years).setScale(0);
        } else if (a.ceiling != null && a.ceiling > 0 && a.periodEnd != null) {
            a.years = Math.max(1.0, a.periodStart.daysBetween(a.periodEnd) / 365.25).setScale(1);
            a.perYear = (a.ceiling / a.years).setScale(0);
        }
    }

    /** Linear interpolation between the closest ranks; values must be sorted. */
    @TestVisible
    private static Decimal percentile(List<Decimal> sorted, Decimal p) {
        if (sorted.isEmpty()) {
            return null;
        }
        Decimal pos = p * (sorted.size() - 1);
        Integer lo = Math.floor(pos).intValue();
        Integer hi = Math.ceil(pos).intValue();
        Decimal frac = pos - lo;
        return (sorted[lo] + (sorted[hi] - sorted[lo]) * frac).setScale(0);
    }

    // ------------------------------------------------------------------------------- incumbent hold

    @TestVisible
    private static Hold hold(List<Award> awards, Id incumbentId, String incumbentName) {
        Hold h = new Hold();
        h.incumbentName = incumbentName;
        // Same agency and NAICS: the follow-on must come from the same buyer for the same kind of work.
        Map<String, List<Award>> byBuyer = new Map<String, List<Award>>();
        for (Award a : awards) {
            String k = a.agencyId + '|' + (a.naics == null ? '' : a.naics);
            if (!byBuyer.containsKey(k)) {
                byBuyer.put(k, new List<Award>());
            }
            byBuyer.get(k).add(a);
        }
        List<HoldExample> examples = new List<HoldExample>();
        for (List<Award> sameBuyer : byBuyer.values()) {
            for (Award ended : sameBuyer) {
                if (ended.periodEnd == null || ended.periodEnd >= Date.today() || ended.vendorId == null) {
                    continue;
                }
                Award follower = null;
                Integer best = null;
                for (Award candidate : sameBuyer) {
                    if (
                        candidate === ended ||
                        candidate.vendorId == null ||
                        candidate.piid == ended.piid ||
                        candidate.periodStart <= ended.periodStart
                    ) {
                        continue;
                    }
                    Integer gap = ended.periodEnd.daysBetween(candidate.periodStart);
                    if (gap < -SUCCESSOR_DAYS_BEFORE || gap > SUCCESSOR_DAYS_AFTER) {
                        continue;
                    }
                    if (best == null || Math.abs(gap) < best) {
                        best = Math.abs(gap);
                        follower = candidate;
                    }
                }
                if (follower == null) {
                    continue;
                }
                HoldExample e = new HoldExample();
                e.vendorName = ended.vendorName;
                e.fromPiid = ended.piid;
                e.toPiid = follower.piid;
                e.toVendorName = follower.vendorName;
                e.endedOn = ended.periodEnd;
                e.kept = follower.vendorId == ended.vendorId;
                h.matched++;
                if (e.kept) {
                    h.kept++;
                }
                if (incumbentId != null && ended.vendorId == incumbentId) {
                    h.incumbentMatched++;
                    if (e.kept) {
                        h.incumbentKept++;
                    }
                }
                examples.add(e);
            }
        }
        examples.sort(new EndedLatestFirst());
        for (Integer i = 0; i < examples.size() && i < 5; i++) {
            h.examples.add(examples[i]);
        }
        return h;
    }

    // ------------------------------------------------------------------------------- similar awards

    /**
     * Nearest-neighbour estimate: scores recent awards that share the NAICS group or the buyer, keeps
     * the most similar 20 and takes their similarity-weighted median per year.
     */
    @TestVisible
    private static Estimate estimate(NXP_Gov_Notice__c n, String naics, Id agencyId, Id departmentId, Date since) {
        Estimate est = new Estimate();
        String prefix = naics == null || naics.length() < 4 ? null : naics.left(4) + '%';
        Set<Id> buyers = new Set<Id>();
        if (agencyId != null) {
            buyers.add(agencyId);
        }
        if (departmentId != null) {
            buyers.add(departmentId);
        }
        if (prefix == null && buyers.isEmpty()) {
            return est;
        }
        String soql =
            'SELECT Id, Name, PIID__c, Vendor__c, Vendor__r.Name, Agency__c, Agency__r.Name, Agency__r.Parent_Agency__c,' +
            ' NAICS_Code__c, PSC_Code__c, Period_Start__c, Period_End__c, Obligated_Amount__c, Ceiling__c' +
            ' FROM NXP_Award_Summary__c WHERE (' +
            (prefix == null ? '' : 'NAICS_Code__c LIKE :prefix') +
            (prefix != null && !buyers.isEmpty() ? ' OR ' : '') +
            (buyers.isEmpty() ? '' : 'Agency__c IN :buyers OR Agency__r.Parent_Agency__c IN :buyers') +
            ') AND Period_Start__c >= :since AND Period_Start__c <= TODAY' +
            ' AND (Obligated_Amount__c > 0 OR Ceiling__c > 0)' +
            ' ORDER BY Period_Start__c DESC LIMIT ' +
            MAX_AWARDS;
        List<Award> pool = toAwards(
            Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'prefix' => prefix, 'buyers' => buyers, 'since' => since },
                AccessLevel.USER_MODE
            ),
            true
        );
        Set<String> noticeWords = words(n.Title__c);
        Integer windowDays = Math.max(1, since.daysBetween(Date.today()));
        for (Award a : pool) {
            Decimal score = 0;
            if (naics != null && a.naics != null) {
                score += a.naics == naics ? 3.0 : (a.naics.left(4) == naics.left(4) ? 1.5 : 0.0);
            }
            if (agencyId != null && a.agencyId == agencyId) {
                score += 2.0;
            } else if (departmentId != null && (a.agencyId == departmentId || a.departmentId == departmentId)) {
                score += 1.0;
            }
            if (String.isNotBlank(n.PSC_Code__c) && a.psc != null) {
                score += a.psc == n.PSC_Code__c ? 1.5 : (a.psc.left(2) == n.PSC_Code__c.left(2) ? 0.5 : 0.0);
            }
            if (!noticeWords.isEmpty()) {
                Integer shared = 0;
                for (String w : words(a.words)) {
                    if (noticeWords.contains(w)) {
                        shared++;
                    }
                }
                score += 2.0 * Math.min(1.0, (Decimal) shared / Math.min(noticeWords.size(), 4));
            }
            score += 0.5 * (1 - (Decimal) a.periodStart.daysBetween(Date.today()) / windowDays);
            a.similarity = score.setScale(2);
            a.words = null;
        }
        List<Award> ranked = new List<Award>();
        for (Award a : pool) {
            if (a.similarity >= MIN_SIMILARITY) {
                ranked.add(a);
            }
        }
        ranked.sort(new MostSimilarFirst());
        List<Award> top = new List<Award>();
        for (Integer i = 0; i < ranked.size() && i < NEIGHBOURS; i++) {
            top.add(ranked[i]);
        }
        est.count = top.size();
        if (top.size() < 3) {
            est.count = 0;
            return est;
        }
        est.perYear = weightedMedian(top);
        List<Decimal> values = new List<Decimal>();
        for (Award a : top) {
            values.add(a.perYear);
        }
        values.sort();
        est.low = percentile(values, 0.25);
        est.high = percentile(values, 0.75);
        for (Integer i = 0; i < top.size() && i < 5; i++) {
            est.basis.add(top[i]);
        }
        return est;
    }

    @TestVisible
    private static Decimal weightedMedian(List<Award> awards) {
        List<Award> byValue = new List<Award>(awards);
        byValue.sort(new LowestPerYearFirst());
        Decimal total = 0;
        for (Award a : byValue) {
            total += a.similarity;
        }
        Decimal running = 0;
        for (Award a : byValue) {
            running += a.similarity;
            if (running >= total / 2) {
                return a.perYear;
            }
        }
        return byValue[byValue.size() - 1].perYear;
    }

    @TestVisible
    private static Set<String> words(String text) {
        Set<String> out = new Set<String>();
        if (String.isBlank(text)) {
            return out;
        }
        for (String w : text.toLowerCase().split('[^a-z0-9]+')) {
            if (w.length() >= 4 && !STOP_WORDS.contains(w)) {
                out.add(w);
            }
        }
        return out;
    }

    private static String shortName(String agencyName) {
        if (String.isBlank(agencyName)) {
            return 'agency';
        }
        // "U.S. Customs and Border Protection" -> "CBP"-style initials for long names; short names as they are.
        if (agencyName.length() <= 18) {
            return agencyName;
        }
        String name = agencyName.trim();
        if (name.endsWithIgnoreCase(', Department of')) {
            name = 'Department of ' + name.removeEndIgnoreCase(', Department of');
        }
        String initials = '';
        for (String w : name.replace('U.S.', '').split('[\\s,]+')) {
            if (w.length() > 0 && w.left(1).isAllUpperCase()) {
                initials += w.left(1);
            }
        }
        return initials.length() >= 2 ? initials : agencyName.left(18);
    }

    // ------------------------------------------------------------------------------- sorting

    private class NewestFirst implements System.Comparator<Award> {
        public Integer compare(Award a, Award b) {
            return b.periodStart == a.periodStart ? 0 : (b.periodStart > a.periodStart ? 1 : -1);
        }
    }

    private class EndedLatestFirst implements System.Comparator<HoldExample> {
        public Integer compare(HoldExample a, HoldExample b) {
            return b.endedOn == a.endedOn ? 0 : (b.endedOn > a.endedOn ? 1 : -1);
        }
    }

    private class MostSimilarFirst implements System.Comparator<Award> {
        public Integer compare(Award a, Award b) {
            if (a.similarity != b.similarity) {
                return b.similarity > a.similarity ? 1 : -1;
            }
            return b.periodStart == a.periodStart ? 0 : (b.periodStart > a.periodStart ? 1 : -1);
        }
    }

    private class LowestPerYearFirst implements System.Comparator<Award> {
        public Integer compare(Award a, Award b) {
            return a.perYear == b.perYear ? 0 : (a.perYear > b.perYear ? 1 : -1);
        }
    }
}
