/**
 * Forecast page (nxpForecastOverview): what a forecast is, how well it fits us, where it stands,
 * the awards it may replace, who wins this work, and other forecasts like it. Statistics and
 * rules only, no AI calls. Reads run in user mode.
 */
public with sharing class NXP_ForecastController {
    private static final Integer CANDIDATE_MONTHS = 12;

    public class Stage {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String detail;
        /** done, now or next. */
        @AuraEnabled
        public String state;
    }

    public class Candidate {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String piid;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Id vendorId;
        @AuraEnabled
        public String vendorName;
        @AuraEnabled
        public String agencyName;
        @AuraEnabled
        public Date periodEnd;
        @AuraEnabled
        public Decimal obligated;
        /** High, Medium or Low: how closely the title and timing match. */
        @AuraEnabled
        public String match;
        @AuraEnabled
        public Boolean confirmed = false;
        public transient Decimal score;
    }

    public class Leader {
        @AuraEnabled
        public Id vendorId;
        @AuraEnabled
        public String vendorName;
        @AuraEnabled
        public Integer awards;
        @AuraEnabled
        public Decimal obligated;
    }

    public class Overview {
        @AuraEnabled
        public NXP_Gov_Forecast__c forecast;
        @AuraEnabled
        public Integer daysToSolicitation;
        @AuraEnabled
        public Decimal fitScore;
        @AuraEnabled
        public List<NXP_FitScoreService.RuleResult> fit = new List<NXP_FitScoreService.RuleResult>();
        /** True / false when the forecast has a set-aside; null when it is open or unknown. */
        @AuraEnabled
        public Boolean setAsideOk;
        @AuraEnabled
        public String setAsideNote;
        @AuraEnabled
        public List<Stage> stages = new List<Stage>();
        @AuraEnabled
        public List<NXP_Gov_Notice__c> notices = new List<NXP_Gov_Notice__c>();
        @AuraEnabled
        public Integer watchers = 0;
        @AuraEnabled
        public Boolean watching = false;
        @AuraEnabled
        public List<Candidate> candidates = new List<Candidate>();
        @AuraEnabled
        public List<Leader> leaders = new List<Leader>();
        @AuraEnabled
        public List<NXP_Gov_Forecast__c> related = new List<NXP_Gov_Forecast__c>();
        /** Power Users and admins can confirm a predecessor and link a notice. */
        @AuraEnabled
        public Boolean canCurate = false;
    }

    @TestVisible
    private static Boolean canCurateOverride;

    /** Forecasts and notices are reference data, read-only for BD users: curating needs a Power User. */
    public static Boolean canCurate() {
        if (canCurateOverride != null) {
            return canCurateOverride;
        }
        return FeatureManagement.checkPermission('NXP_Power_User') ||
            FeatureManagement.checkPermission('NXP_Admin_Access');
    }

    private static void requireCurate() {
        if (!canCurate()) {
            throw new IllegalArgumentException('Only Power Users and Nexus admins can change a forecast\'s links.');
        }
    }

    @AuraEnabled
    public static Overview getOverview(Id forecastId) {
        try {
            return overview(forecastId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Confirms (or clears, with a null award) the predecessor; the notice inherits it when linked. */
    @AuraEnabled
    public static Overview setPredecessor(Id forecastId, Id awardId) {
        try {
            requireCurate();
            update as system new NXP_Gov_Forecast__c(Id = forecastId, Predecessor_Award__c = awardId);
            return overview(forecastId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Links a notice by hand when the automatic title match missed it. */
    @AuraEnabled
    public static Overview linkNotice(Id forecastId, Id noticeId) {
        try {
            requireCurate();
            NXP_Gov_Forecast__c f = [
                SELECT Id, Predecessor_Award__c
                FROM NXP_Gov_Forecast__c
                WHERE Id = :forecastId
                WITH USER_MODE
            ];
            NXP_Gov_Notice__c n = [
                SELECT Id, Predecessor_Award__c
                FROM NXP_Gov_Notice__c
                WHERE Id = :noticeId
                WITH USER_MODE
            ];
            n.Forecast__c = forecastId;
            if (n.Predecessor_Award__c == null && f.Predecessor_Award__c != null) {
                n.Predecessor_Award__c = f.Predecessor_Award__c;
            }
            update as system new NXP_Gov_Forecast__c(Id = forecastId, Matched_Notice__c = noticeId);
            update as system n;
            return overview(forecastId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @TestVisible
    private static Overview overview(Id forecastId) {
        List<NXP_Gov_Forecast__c> rows = [
            SELECT
                Id,
                Name,
                Forecast_Id__c,
                Agency__c,
                Agency__r.Name,
                Agency__r.Full_Path__c,
                Agency__r.Parent_Agency__c,
                Estimated_Solicitation_Date__c,
                Estimated_Value__c,
                Fiscal_Year__c,
                NAICS_Code__c,
                Set_Aside__c,
                Source_Feed__c,
                Description__c,
                Matched_Notice__c,
                Predecessor_Award__c,
                CreatedDate
            FROM NXP_Gov_Forecast__c
            WHERE Id = :forecastId
            WITH USER_MODE
        ];
        if (rows.isEmpty()) {
            throw new IllegalArgumentException('Forecast not found or not visible to you.');
        }
        NXP_Gov_Forecast__c f = rows[0];
        Overview o = new Overview();
        o.forecast = f;
        if (f.Estimated_Solicitation_Date__c != null) {
            o.daysToSolicitation = Date.today().daysBetween(f.Estimated_Solicitation_Date__c);
        }
        fit(f, o);
        stages(f, o);
        o.watching = NXP_WatchService.watchedByMe(new Set<Id>{ f.Id }).contains(f.Id);
        o.watchers = [SELECT COUNT() FROM NXP_Follow__c WHERE Forecast__c = :f.Id WITH SYSTEM_MODE];
        o.candidates = candidates(f);
        o.leaders = leaders(f);
        o.related = related(f);
        o.canCurate = canCurate();
        return o;
    }

    // ------------------------------------------------------------------ early fit

    /** The same fit rules as notices, applied to the forecast's fields. */
    private static void fit(NXP_Gov_Forecast__c f, Overview o) {
        NXP_FitScoreService svc = new NXP_FitScoreService();
        if (!svc.isConfigured()) {
            return;
        }
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Title__c = f.Name,
            Description__c = f.Description__c,
            NAICS_Code__c = f.NAICS_Code__c,
            Set_Aside__c = f.Set_Aside__c,
            Estimated_Value__c = f.Estimated_Value__c,
            Agency__c = f.Agency__c,
            Agency_Path__c = f.Agency__r == null ? null : f.Agency__r.Full_Path__c
        );
        Decimal total = 0;
        Decimal weights = 0;
        for (NXP_FitScoreService.RuleResult r : svc.evaluate(n)) {
            // A forecast is never on a vehicle yet: leave that rule out instead of scoring it zero.
            if (r.rule == 'Vehicle') {
                continue;
            }
            o.fit.add(r);
            total += r.points;
            weights += r.weight;
            if (
                r.rule == 'Set-Aside' &&
                String.isNotBlank(f.Set_Aside__c) &&
                !f.Set_Aside__c.containsIgnoreCase('none')
            ) {
                o.setAsideOk = r.points > 0;
                o.setAsideNote = o.setAsideOk ? 'We qualify' : 'We don\'t qualify: team with a firm that does';
            }
        }
        o.fitScore = weights == 0 ? null : (total * 100 / weights).setScale(0);
    }

    // ------------------------------------------------------------------ where it stands

    private static void stages(NXP_Gov_Forecast__c f, Overview o) {
        o.notices = [
            SELECT Id, Name, Title__c, Notice_Type__c, Posted_Date__c, Response_Due__c, Status__c
            FROM NXP_Gov_Notice__c
            WHERE Forecast__c = :f.Id OR Id = :f.Matched_Notice__c
            WITH USER_MODE
            ORDER BY Posted_Date__c ASC NULLS LAST
            LIMIT 20
        ];
        NXP_Gov_Notice__c early;
        NXP_Gov_Notice__c solicitation;
        NXP_Gov_Notice__c award;
        for (NXP_Gov_Notice__c n : o.notices) {
            String t = n.Notice_Type__c == null ? '' : n.Notice_Type__c;
            if (t.containsIgnoreCase('award')) {
                award = n;
            } else if (t.containsIgnoreCase('solicitation') && !t.containsIgnoreCase('pre-solicitation')) {
                solicitation = n;
            } else if (early == null) {
                early = n;
            }
        }
        o.stages.add(stage('Forecast', 'Posted ' + f.CreatedDate.date().format(), 'done'));
        o.stages.add(
            early != null
                ? stage(early.Notice_Type__c, 'Posted ' + dateOf(early.Posted_Date__c), 'done')
                : stage('Sources Sought / RFI', 'Not seen yet', solicitation == null && award == null ? 'now' : 'next')
        );
        String expected = f.Estimated_Solicitation_Date__c == null
            ? 'Date not known'
            : 'Expected ' + f.Estimated_Solicitation_Date__c.format();
        o.stages.add(
            solicitation != null
                ? stage('Solicitation', 'Posted ' + dateOf(solicitation.Posted_Date__c), 'done')
                : stage('Solicitation', expected, early != null ? 'now' : 'next')
        );
        o.stages.add(
            award != null
                ? stage('Award', 'Posted ' + dateOf(award.Posted_Date__c), 'done')
                : stage('Award', 'Not known', solicitation != null ? 'now' : 'next')
        );
    }

    private static Stage stage(String label, String detail, String state) {
        Stage s = new Stage();
        s.label = label;
        s.detail = detail;
        s.state = state;
        return s;
    }

    private static String dateOf(Date d) {
        return d == null ? 'date unknown' : d.format();
    }

    // ------------------------------------------------------------------ predecessor candidates

    /**
     * Awards at the same agency (and NAICS when known) ending within 12 months either side of the
     * expected solicitation, ranked by shared title words and how close the end date is.
     */
    @TestVisible
    private static List<Candidate> candidates(NXP_Gov_Forecast__c f) {
        List<Candidate> out = new List<Candidate>();
        if (f.Agency__c == null) {
            return out;
        }
        Date pivot = f.Estimated_Solicitation_Date__c == null ? Date.today() : f.Estimated_Solicitation_Date__c;
        Date fromDate = pivot.addMonths(-CANDIDATE_MONTHS);
        Date toDate = pivot.addMonths(CANDIDATE_MONTHS);
        Id agencyId = f.Agency__c;
        String naics = f.NAICS_Code__c;
        String soql =
            'SELECT Id, Name, PIID__c, Vendor__c, Vendor__r.Name, Agency__r.Name, Period_End__c, Obligated_Amount__c' +
            ' FROM NXP_Award_Summary__c WHERE Agency__c = :agencyId AND Period_End__c >= :fromDate AND Period_End__c <= :toDate' +
            (String.isBlank(naics) ? '' : ' AND NAICS_Code__c = :naics') +
            ' ORDER BY Period_End__c LIMIT 500';
        List<NXP_Award_Summary__c> awards = Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'agencyId' => agencyId,
                'fromDate' => fromDate,
                'toDate' => toDate,
                'naics' => naics
            },
            AccessLevel.USER_MODE
        );
        Set<String> want = words(f.Name + ' ' + (f.Description__c == null ? '' : f.Description__c.left(500)));
        for (NXP_Award_Summary__c a : awards) {
            Candidate c = new Candidate();
            c.id = a.Id;
            c.piid = a.PIID__c;
            c.name = a.Name;
            c.vendorId = a.Vendor__c;
            c.vendorName = a.Vendor__r == null ? null : a.Vendor__r.Name;
            c.agencyName = a.Agency__r == null ? null : a.Agency__r.Name;
            c.periodEnd = a.Period_End__c;
            c.obligated = a.Obligated_Amount__c;
            c.confirmed = a.Id == f.Predecessor_Award__c;
            Integer shared = 0;
            Set<String> have = words(a.Name);
            for (String w : have) {
                if (want.contains(w)) {
                    shared++;
                }
            }
            Decimal titleScore = have.isEmpty() ? 0 : Math.min(1.0, (Decimal) shared / Math.min(have.size(), 3));
            Decimal timing = 1 - Math.min(1.0, Math.abs((Decimal) pivot.daysBetween(a.Period_End__c)) / 365.0);
            c.score = titleScore * 2 + timing;
            c.match = c.score >= 2 ? 'High' : (c.score >= 1 ? 'Medium' : 'Low');
            out.add(c);
        }
        out.sort(new ByScore());
        List<Candidate> top = new List<Candidate>();
        for (Candidate c : out) {
            if (top.size() < 5 || c.confirmed) {
                top.add(c);
            }
        }
        return top;
    }

    private class ByScore implements System.Comparator<Candidate> {
        public Integer compare(Candidate a, Candidate b) {
            if (a.confirmed != b.confirmed) {
                return a.confirmed ? -1 : 1;
            }
            return a.score == b.score ? 0 : (b.score > a.score ? 1 : -1);
        }
    }

    @TestVisible
    private static Set<String> words(String text) {
        Set<String> out = new Set<String>();
        if (String.isBlank(text)) {
            return out;
        }
        Set<String> stop = new Set<String>{
            'support',
            'services',
            'service',
            'program',
            'contract',
            'with',
            'from',
            'that',
            'this',
            'sample',
            'data'
        };
        for (String w : text.toLowerCase().split('[^a-z0-9]+')) {
            if (w.length() >= 4 && !stop.contains(w)) {
                out.add(w);
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ who wins here, related

    private static List<Leader> leaders(NXP_Gov_Forecast__c f) {
        List<Leader> out = new List<Leader>();
        if (f.Agency__c == null) {
            return out;
        }
        Date since = Date.today().addYears(-5);
        Id agencyId = f.Agency__c;
        String naics = f.NAICS_Code__c;
        String soql =
            'SELECT Vendor__c vendorId, Vendor__r.Name vendorName, COUNT(Id) awardCount, SUM(Obligated_Amount__c) total' +
            ' FROM NXP_Award_Summary__c WHERE Agency__c = :agencyId AND Vendor__c != NULL AND Period_Start__c >= :since' +
            (String.isBlank(naics) ? '' : ' AND NAICS_Code__c = :naics') +
            ' GROUP BY Vendor__c, Vendor__r.Name ORDER BY COUNT(Id) DESC LIMIT 5';
        for (
            AggregateResult r : (List<AggregateResult>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'agencyId' => agencyId, 'since' => since, 'naics' => naics },
                AccessLevel.USER_MODE
            )
        ) {
            Leader l = new Leader();
            l.vendorId = (Id) r.get('vendorId');
            l.vendorName = (String) r.get('vendorName');
            l.awards = (Integer) r.get('awardCount');
            l.obligated = (Decimal) r.get('total');
            out.add(l);
        }
        return out;
    }

    private static List<NXP_Gov_Forecast__c> related(NXP_Gov_Forecast__c f) {
        if (f.Agency__c == null) {
            return new List<NXP_Gov_Forecast__c>();
        }
        Id agencyId = f.Agency__c;
        Id selfId = f.Id;
        String naics = f.NAICS_Code__c;
        String soql =
            'SELECT Id, Name, Estimated_Solicitation_Date__c, Estimated_Value__c, NAICS_Code__c FROM NXP_Gov_Forecast__c' +
            ' WHERE Agency__c = :agencyId AND Id != :selfId' +
            ' AND (Estimated_Solicitation_Date__c = NULL OR Estimated_Solicitation_Date__c >= TODAY)' +
            (String.isBlank(naics) ? '' : ' AND NAICS_Code__c = :naics') +
            ' ORDER BY Estimated_Solicitation_Date__c ASC NULLS LAST LIMIT 5';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'agencyId' => agencyId, 'selfId' => selfId, 'naics' => naics },
            AccessLevel.USER_MODE
        );
    }

    private static AuraHandledException handled(Exception e) {
        String message = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
        AuraHandledException a = new AuraHandledException(message);
        a.setMessage(message);
        return a;
    }
}
