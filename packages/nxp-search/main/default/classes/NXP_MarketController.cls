/**
 * Data for the market screens: Forecasts board (nxpForecastBoard), Recompetes timeline
 * (nxpRecompeteTimeline), Vendor profile (nxpVendorProfile) and Agency profile (nxpAgencyProfile),
 * plus Watch and Refresh from SAM.gov.
 * Reads run in user mode; the company profile (configuration) is read in system mode.
 */
public with sharing class NXP_MarketController {
    // ------------------------------------------------------------------------------- shapes

    public class ForecastCard {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String agency;
        @AuraEnabled
        public String naics;
        @AuraEnabled
        public String setAside;
        @AuraEnabled
        public Decimal value;
        @AuraEnabled
        public Date solicitationDate;
        @AuraEnabled
        public Integer daysUntil;
        @AuraEnabled
        public String fiscalYear;
        @AuraEnabled
        public Boolean profileMatch = false;
        @AuraEnabled
        public String profileNote;
        @AuraEnabled
        public Boolean released = false;
        @AuraEnabled
        public Id noticeId;
        @AuraEnabled
        public String noticeKey;
        @AuraEnabled
        public Date noticePosted;
        @AuraEnabled
        public Boolean watching = false;
    }

    public class ForecastColumn {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public List<ForecastCard> cards = new List<ForecastCard>();
        public ForecastColumn(String key, String label) {
            this.key = key;
            this.label = label;
        }
    }

    public class ForecastBoard {
        @AuraEnabled
        public List<ForecastColumn> columns = new List<ForecastColumn>();
        @AuraEnabled
        public Integer tracked = 0;
        @AuraEnabled
        public Integer next90 = 0;
        @AuraEnabled
        public Decimal next90Value = 0;
        @AuraEnabled
        public Integer released = 0;
        @AuraEnabled
        public Integer watched = 0;
        @AuraEnabled
        public List<String> fiscalYears = new List<String>();
    }

    public class AwardRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String piid;
        @AuraEnabled
        public String agency;
        @AuraEnabled
        public String naics;
        @AuraEnabled
        public String psc;
        @AuraEnabled
        public Id vendorId;
        @AuraEnabled
        public String vendorName;
        @AuraEnabled
        public Decimal obligated;
        @AuraEnabled
        public Decimal ceiling;
        @AuraEnabled
        public Date periodStart;
        @AuraEnabled
        public Date periodEnd;
        @AuraEnabled
        public Integer monthsLeft;
        /** notice | forecast | none */
        @AuraEnabled
        public String followOnKind = 'none';
        @AuraEnabled
        public String followOnLabel = 'Nothing yet';
        @AuraEnabled
        public Id followOnId;
        /** true when the notice names this award as its predecessor; false for a likely match */
        @AuraEnabled
        public Boolean followOnConfirmed = false;
        @AuraEnabled
        public Boolean watching = false;
    }

    public class Overlap {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String note;
        public Overlap(String label, String value, String note) {
            this.label = label;
            this.value = value;
            this.note = note;
        }
    }

    public class OpenNotice {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String noticeKey;
        @AuraEnabled
        public String noticeType;
        @AuraEnabled
        public String agency;
        @AuraEnabled
        public Datetime responseDue;
        @AuraEnabled
        public Decimal fitScore;
        @AuraEnabled
        public String reason;
    }

    public class VendorProfile {
        @AuraEnabled
        public NXP_Gov_Vendor__c vendor;
        @AuraEnabled
        public Integer awardCount = 0;
        @AuraEnabled
        public Decimal totalObligated = 0;
        @AuraEnabled
        public Integer endingSoon = 0;
        @AuraEnabled
        public List<String> agencies = new List<String>();
        @AuraEnabled
        public List<AwardRow> awards = new List<AwardRow>();
        @AuraEnabled
        public List<Overlap> overlap = new List<Overlap>();
        @AuraEnabled
        public List<OpenNotice> openNotices = new List<OpenNotice>();
        @AuraEnabled
        public Boolean watching = false;
        @AuraEnabled
        public Boolean canRefresh = false;
    }

    @TestVisible
    private static final Integer ENDING_SOON_MONTHS = 18;

    public class ComingItem implements Comparable {
        /** notice | forecast | award */
        @AuraEnabled
        public String kind;
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public Date onDate;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Decimal fitScore;

        public Integer compareTo(Object other) {
            Date mine = onDate;
            Date theirs = ((ComingItem) other).onDate;
            if (mine == theirs) {
                return 0;
            }
            if (mine == null) {
                return 1;
            }
            if (theirs == null) {
                return -1;
            }
            return mine < theirs ? -1 : 1;
        }
    }

    public class Incumbent {
        @AuraEnabled
        public Id vendorId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer awards;
        @AuraEnabled
        public Decimal total;
    }

    public class NaicsSpend {
        @AuraEnabled
        public String code;
        @AuraEnabled
        public Decimal total;
        @AuraEnabled
        public Decimal pct;
        @AuraEnabled
        public Boolean inProfile = false;
    }

    public class AgencyContact {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String phone;
        @AuraEnabled
        public Id noticeId;
        @AuraEnabled
        public String noticeKey;
    }

    public class AgencyRef {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String code;
        public AgencyRef(Id id, String name, String code) {
            this.id = id;
            this.name = name;
            this.code = code;
        }
    }

    public class AgencyProfile {
        @AuraEnabled
        public NXP_Gov_Agency__c agency;
        @AuraEnabled
        public Boolean targetAgency = false;
        @AuraEnabled
        public Boolean watching = false;
        @AuraEnabled
        public Integer openNotices = 0;
        @AuraEnabled
        public Integer dueIn30 = 0;
        @AuraEnabled
        public Integer forecasts = 0;
        @AuraEnabled
        public Decimal forecastValue = 0;
        @AuraEnabled
        public Integer endingSoon = 0;
        @AuraEnabled
        public Decimal endingSoonValue = 0;
        @AuraEnabled
        public List<ComingItem> coming = new List<ComingItem>();
        @AuraEnabled
        public List<Incumbent> incumbents = new List<Incumbent>();
        @AuraEnabled
        public List<NaicsSpend> naics = new List<NaicsSpend>();
        @AuraEnabled
        public List<AgencyContact> contacts = new List<AgencyContact>();
        @AuraEnabled
        public List<String> offices = new List<String>();
        @AuraEnabled
        public List<AgencyRef> children = new List<AgencyRef>();
        @AuraEnabled
        public List<String> coveringSearches = new List<String>();
        @AuraEnabled
        public Integer broadSearches = 0;
        @AuraEnabled
        public Integer pushed = 0;
        @AuraEnabled
        public Integer followed = 0;
    }

    // ------------------------------------------------------------------------------- Forecasts

    @AuraEnabled
    public static ForecastBoard getForecastBoard(
        String agency,
        String naics,
        String setAside,
        String fiscalYear,
        Boolean profileOnly
    ) {
        try {
            List<String> clauses = new List<String>();
            Map<String, Object> binds = new Map<String, Object>();
            addLike(clauses, binds, 'Agency__r.Full_Path__c', 'agencyLike', agency, true);
            addLike(
                clauses,
                binds,
                'NAICS_Code__c',
                'naicsLike',
                naics == null ? null : naics.trim().removeEnd('*'),
                false
            );
            addLike(clauses, binds, 'Set_Aside__c', 'setAsideLike', setAside, true);
            if (String.isNotBlank(fiscalYear)) {
                clauses.add('Fiscal_Year__c = :fy');
                binds.put('fy', fiscalYear.trim());
            }
            String soql =
                'SELECT Id, Name, Agency__r.Name, Agency__r.Full_Path__c, NAICS_Code__c, Set_Aside__c, ' +
                'Estimated_Value__c, Estimated_Solicitation_Date__c, Fiscal_Year__c, Matched_Notice__c, ' +
                'Matched_Notice__r.Notice_Id__c, Matched_Notice__r.Posted_Date__c FROM NXP_Gov_Forecast__c' +
                (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ')) +
                ' ORDER BY Estimated_Solicitation_Date__c ASC NULLS LAST LIMIT 500';
            List<NXP_Gov_Forecast__c> rows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);

            ProfileMatcher profile = new ProfileMatcher();
            Set<Id> ids = new Map<Id, NXP_Gov_Forecast__c>(rows).keySet();
            Set<Id> watched = NXP_WatchService.watchedByMe(ids);

            ForecastBoard board = new ForecastBoard();
            ForecastColumn next90 = new ForecastColumn('next90', 'Next 90 days');
            ForecastColumn next180 = new ForecastColumn('next180', '3 to 6 months');
            ForecastColumn next365 = new ForecastColumn('next365', '6 to 12 months');
            ForecastColumn later = new ForecastColumn('later', 'Later or no date');
            ForecastColumn released = new ForecastColumn('released', 'Released as notices');
            Date today = Date.today();
            for (NXP_Gov_Forecast__c f : rows) {
                ForecastCard c = new ForecastCard();
                c.id = f.Id;
                c.title = f.Name;
                c.agency = f.Agency__r == null ? null : f.Agency__r.Full_Path__c;
                c.naics = f.NAICS_Code__c;
                c.setAside = f.Set_Aside__c;
                c.value = f.Estimated_Value__c;
                c.solicitationDate = f.Estimated_Solicitation_Date__c;
                c.daysUntil = c.solicitationDate == null ? null : today.daysBetween(c.solicitationDate);
                c.fiscalYear = f.Fiscal_Year__c;
                c.watching = watched.contains(f.Id);
                profile.describe(c.naics, c.agency, c.setAside);
                c.profileMatch = profile.lastMatch;
                c.profileNote = profile.lastNote;
                if (profileOnly == true && !c.profileMatch) {
                    continue;
                }
                board.tracked++;
                if (c.watching) {
                    board.watched++;
                }
                if (f.Matched_Notice__c != null) {
                    c.released = true;
                    c.noticeId = f.Matched_Notice__c;
                    c.noticeKey = f.Matched_Notice__r.Notice_Id__c;
                    c.noticePosted = f.Matched_Notice__r.Posted_Date__c;
                    released.cards.add(c);
                    board.released++;
                } else if (c.daysUntil == null || c.daysUntil > 365) {
                    later.cards.add(c);
                } else if (c.daysUntil > 180) {
                    next365.cards.add(c);
                } else if (c.daysUntil > 90) {
                    next180.cards.add(c);
                } else {
                    next90.cards.add(c);
                    board.next90++;
                    board.next90Value += c.value == null ? 0 : c.value;
                }
            }
            board.columns = new List<ForecastColumn>{ next90, next180, next365, later, released };
            for (AggregateResult ar : [
                SELECT Fiscal_Year__c fy
                FROM NXP_Gov_Forecast__c
                WHERE Fiscal_Year__c != NULL
                WITH USER_MODE
                GROUP BY Fiscal_Year__c
                ORDER BY Fiscal_Year__c
                LIMIT 20
            ]) {
                board.fiscalYears.add((String) ar.get('fy'));
            }
            return board;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------------------- Recompetes

    /** Awards ending within monthsAhead (and those that ended in the last 12 months), soonest first. */
    @AuraEnabled
    public static List<AwardRow> getRecompetes(String agency, String naics, Integer monthsAhead, Decimal minValue) {
        try {
            Integer months = monthsAhead == null || monthsAhead <= 0 ? ENDING_SOON_MONTHS : Math.min(monthsAhead, 60);
            Date today = Date.today();
            List<String> clauses = new List<String>{ 'Period_End__c >= :fromDate', 'Period_End__c <= :toDate' };
            Map<String, Object> binds = new Map<String, Object>{
                'fromDate' => today.addMonths(-12),
                'toDate' => today.addMonths(months)
            };
            addLike(clauses, binds, 'Agency__r.Full_Path__c', 'agencyLike', agency, true);
            addLike(
                clauses,
                binds,
                'NAICS_Code__c',
                'naicsLike',
                naics == null ? null : naics.trim().removeEnd('*'),
                false
            );
            if (minValue != null && minValue > 0) {
                clauses.add('Obligated_Amount__c >= :minValue');
                binds.put('minValue', minValue);
            }
            String soql =
                'SELECT ' +
                AWARD_FIELDS +
                ' FROM NXP_Award_Summary__c WHERE ' +
                String.join(clauses, ' AND ') +
                ' ORDER BY Period_End__c ASC LIMIT 200';
            return toRows(Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------------------- Vendor profile

    @AuraEnabled
    public static VendorProfile getVendorProfile(Id vendorId) {
        try {
            List<NXP_Gov_Vendor__c> vendors = [
                SELECT
                    Id,
                    Name,
                    UEI__c,
                    CAGE_Code__c,
                    Business_Size__c,
                    Socio_Economic__c,
                    City__c,
                    State__c,
                    Last_Synced__c
                FROM NXP_Gov_Vendor__c
                WHERE Id = :vendorId
                WITH USER_MODE
            ];
            if (vendors.isEmpty()) {
                throw new AuraHandledException('Vendor not found or not visible to you.');
            }
            VendorProfile p = new VendorProfile();
            p.vendor = vendors[0];
            p.watching = NXP_WatchService.watchedByMe(new Set<Id>{ vendorId }).contains(vendorId);
            p.canRefresh = String.isNotBlank(p.vendor.UEI__c) && FeatureManagement.checkPermission('NXP_Admin_Access');

            List<NXP_Award_Summary__c> awards = Database.queryWithBinds(
                'SELECT ' +
                    AWARD_FIELDS +
                    ' FROM NXP_Award_Summary__c WHERE Vendor__c = :vendorId ORDER BY Period_End__c DESC NULLS LAST LIMIT 200',
                new Map<String, Object>{ 'vendorId' => vendorId },
                AccessLevel.USER_MODE
            );
            p.awards = toRows(awards);
            Date today = Date.today();
            Set<String> agencyNames = new Set<String>();
            Set<String> naicsCodes = new Set<String>();
            Set<String> agencyPaths = new Set<String>();
            Set<Id> recentAgencyIds = new Set<Id>();
            Set<String> recentNaics = new Set<String>();
            for (NXP_Award_Summary__c a : awards) {
                p.awardCount++;
                p.totalObligated += a.Obligated_Amount__c == null ? 0 : a.Obligated_Amount__c;
                if (
                    a.Period_End__c != null &&
                    a.Period_End__c >= today &&
                    a.Period_End__c <= today.addMonths(ENDING_SOON_MONTHS)
                ) {
                    p.endingSoon++;
                }
                if (a.Agency__r != null) {
                    agencyNames.add(a.Agency__r.Name);
                    agencyPaths.add(a.Agency__r.Full_Path__c);
                }
                if (String.isNotBlank(a.NAICS_Code__c)) {
                    naicsCodes.add(a.NAICS_Code__c);
                }
                if (
                    a.Period_End__c != null &&
                    a.Agency__c != null &&
                    String.isNotBlank(a.NAICS_Code__c) &&
                    a.Period_End__c >= today.addMonths(-12) &&
                    a.Period_End__c <= today.addMonths(ENDING_SOON_MONTHS)
                ) {
                    recentAgencyIds.add(a.Agency__c);
                    recentNaics.add(a.NAICS_Code__c);
                }
            }
            p.agencies = new List<String>(agencyNames);
            p.agencies.sort();
            p.overlap = buildOverlap(p.vendor, naicsCodes, agencyPaths);
            p.openNotices = findOpenNotices(vendorId, recentAgencyIds, recentNaics);
            return p;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------------------- Agency profile

    @TestVisible
    private static final Integer COMING_LIMIT = 15;

    /** Everything Nexus links to an agency and its direct sub-agencies, for nxpAgencyProfile. */
    @AuraEnabled
    public static AgencyProfile getAgencyProfile(Id agencyId) {
        try {
            List<NXP_Gov_Agency__c> agencies = [
                SELECT
                    Id,
                    Name,
                    Agency_Code__c,
                    Level__c,
                    Full_Path__c,
                    Parent_Agency__c,
                    Parent_Agency__r.Name,
                    Parent_Agency__r.Agency_Code__c
                FROM NXP_Gov_Agency__c
                WHERE Id = :agencyId
                WITH USER_MODE
            ];
            if (agencies.isEmpty()) {
                throw new AuraHandledException('Agency not found or not visible to you.');
            }
            AgencyProfile p = new AgencyProfile();
            p.agency = agencies[0];
            String path = String.isBlank(p.agency.Full_Path__c) ? p.agency.Name : p.agency.Full_Path__c;
            p.targetAgency = new ProfileMatcher().agencyMatches(path);
            p.watching = NXP_WatchService.watchedByMe(new Set<Id>{ agencyId }).contains(agencyId);

            Set<Id> scope = new Set<Id>{ agencyId };
            for (NXP_Gov_Agency__c child : [
                SELECT Id, Name, Agency_Code__c
                FROM NXP_Gov_Agency__c
                WHERE Parent_Agency__c = :agencyId
                WITH USER_MODE
                ORDER BY Name
                LIMIT 200
            ]) {
                p.children.add(new AgencyRef(child.Id, child.Name, child.Agency_Code__c));
                scope.add(child.Id);
            }

            Date today = Date.today();
            Datetime now = Datetime.now();
            Date forecastFrom = today.addDays(-30);
            Date awardsTo = today.addMonths(ENDING_SOON_MONTHS);
            List<ComingItem> coming = new List<ComingItem>();

            for (NXP_Gov_Notice__c n : [
                SELECT Id, Title__c, Name, Notice_Id__c, Notice_Type__c, NAICS_Code__c, Response_Due__c, Fit_Score__c
                FROM NXP_Gov_Notice__c
                WHERE
                    Agency__c IN :scope
                    AND Status__c = 'Active'
                    AND (Response_Due__c >= :now
                    OR Response_Due__c = NULL)
                WITH USER_MODE
                ORDER BY Response_Due__c ASC NULLS LAST
                LIMIT 200
            ]) {
                p.openNotices++;
                if (n.Response_Due__c != null && n.Response_Due__c <= now.addDays(30)) {
                    p.dueIn30++;
                }
                ComingItem c = new ComingItem();
                c.kind = 'notice';
                c.recordId = n.Id;
                c.title = n.Title__c == null ? n.Name : n.Title__c;
                c.onDate = n.Response_Due__c == null ? null : n.Response_Due__c.date();
                c.detail = joinParts(new List<String>{ n.Notice_Type__c, n.Notice_Id__c, naicsLabel(n.NAICS_Code__c) });
                c.fitScore = n.Fit_Score__c;
                coming.add(c);
            }

            for (NXP_Gov_Forecast__c f : [
                SELECT Id, Name, NAICS_Code__c, Fiscal_Year__c, Estimated_Value__c, Estimated_Solicitation_Date__c
                FROM NXP_Gov_Forecast__c
                WHERE
                    Agency__c IN :scope
                    AND Matched_Notice__c = NULL
                    AND (Estimated_Solicitation_Date__c >= :forecastFrom
                    OR Estimated_Solicitation_Date__c = NULL)
                WITH USER_MODE
                ORDER BY Estimated_Solicitation_Date__c ASC NULLS LAST
                LIMIT 200
            ]) {
                p.forecasts++;
                p.forecastValue += f.Estimated_Value__c == null ? 0 : f.Estimated_Value__c;
                ComingItem c = new ComingItem();
                c.kind = 'forecast';
                c.recordId = f.Id;
                c.title = f.Name;
                c.onDate = f.Estimated_Solicitation_Date__c;
                c.detail = joinParts(
                    new List<String>{ 'Expected solicitation', f.Fiscal_Year__c, naicsLabel(f.NAICS_Code__c) }
                );
                c.amount = f.Estimated_Value__c;
                coming.add(c);
            }

            for (NXP_Award_Summary__c a : [
                SELECT Id, Name, PIID__c, NAICS_Code__c, Vendor__r.Name, Obligated_Amount__c, Period_End__c
                FROM NXP_Award_Summary__c
                WHERE Agency__c IN :scope AND Period_End__c >= :today AND Period_End__c <= :awardsTo
                WITH USER_MODE
                ORDER BY Period_End__c ASC
                LIMIT 200
            ]) {
                p.endingSoon++;
                p.endingSoonValue += a.Obligated_Amount__c == null ? 0 : a.Obligated_Amount__c;
                ComingItem c = new ComingItem();
                c.kind = 'award';
                c.recordId = a.Id;
                c.title = a.Name;
                c.onDate = a.Period_End__c;
                c.detail = joinParts(
                    new List<String>{
                        a.Vendor__r == null ? null : a.Vendor__r.Name,
                        a.PIID__c,
                        naicsLabel(a.NAICS_Code__c)
                    }
                );
                c.amount = a.Obligated_Amount__c;
                coming.add(c);
            }
            coming.sort();
            for (Integer i = 0; i < coming.size() && i < COMING_LIMIT; i++) {
                p.coming.add(coming[i]);
            }

            for (AggregateResult ar : [
                SELECT Vendor__c vendorId, Vendor__r.Name vendorName, COUNT(Id) awards, SUM(Obligated_Amount__c) total
                FROM NXP_Award_Summary__c
                WHERE Agency__c IN :scope AND Vendor__c != NULL
                WITH USER_MODE
                GROUP BY Vendor__c, Vendor__r.Name
                ORDER BY SUM(Obligated_Amount__c) DESC NULLS LAST
                LIMIT 5
            ]) {
                Incumbent inc = new Incumbent();
                inc.vendorId = (Id) ar.get('vendorId');
                inc.name = (String) ar.get('vendorName');
                inc.awards = (Integer) ar.get('awards');
                inc.total = (Decimal) ar.get('total');
                p.incumbents.add(inc);
            }

            ProfileMatcher profile = new ProfileMatcher();
            Decimal naicsTotal = 0;
            for (AggregateResult ar : [
                SELECT NAICS_Code__c code, SUM(Obligated_Amount__c) total
                FROM NXP_Award_Summary__c
                WHERE Agency__c IN :scope AND NAICS_Code__c != NULL
                WITH USER_MODE
                GROUP BY NAICS_Code__c
                ORDER BY SUM(Obligated_Amount__c) DESC NULLS LAST
                LIMIT 8
            ]) {
                NaicsSpend ns = new NaicsSpend();
                ns.code = (String) ar.get('code');
                ns.total = ar.get('total') == null ? 0 : (Decimal) ar.get('total');
                ns.inProfile = profile.naicsMatches(ns.code);
                naicsTotal += ns.total;
                p.naics.add(ns);
            }
            for (NaicsSpend ns : p.naics) {
                ns.pct = naicsTotal == 0 ? 0 : (ns.total * 100 / naicsTotal).setScale(0, RoundingMode.HALF_UP);
            }

            Set<String> seen = new Set<String>();
            for (NXP_Gov_Contact__c c : [
                SELECT Id, Name, Role__c, Email__c, Phone__c, Gov_Notice__c, Gov_Notice__r.Notice_Id__c
                FROM NXP_Gov_Contact__c
                WHERE Agency__c IN :scope OR Gov_Notice__r.Agency__c IN :scope
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 50
            ]) {
                String who = (String.isBlank(c.Email__c) ? c.Name : c.Email__c).toLowerCase();
                if (!seen.add(who) || p.contacts.size() >= 8) {
                    continue;
                }
                AgencyContact ac = new AgencyContact();
                ac.id = c.Id;
                ac.name = c.Name;
                ac.role = c.Role__c;
                ac.email = c.Email__c;
                ac.phone = c.Phone__c;
                ac.noticeId = c.Gov_Notice__c;
                ac.noticeKey = c.Gov_Notice__r == null ? null : c.Gov_Notice__r.Notice_Id__c;
                p.contacts.add(ac);
            }

            for (AggregateResult ar : [
                SELECT Office__c office
                FROM NXP_Gov_Notice__c
                WHERE Agency__c IN :scope AND Office__c != NULL
                WITH USER_MODE
                GROUP BY Office__c
                ORDER BY COUNT(Id) DESC
                LIMIT 8
            ]) {
                p.offices.add((String) ar.get('office'));
            }

            Id me = UserInfo.getUserId();
            for (NXP_Saved_Search__c s : [
                SELECT Name, Criteria_JSON__c
                FROM NXP_Saved_Search__c
                WHERE OwnerId = :me AND Active__c = TRUE
                WITH USER_MODE
                ORDER BY Name
                LIMIT 200
            ]) {
                NXP_SearchCriteria c;
                try {
                    c = NXP_SearchCriteria.parse(s.Criteria_JSON__c);
                } catch (Exception e) {
                    continue;
                }
                if (c.agencies == null || c.agencies.isEmpty()) {
                    p.broadSearches++;
                } else if (NXP_Text.containsAny(path, c.agencies)) {
                    p.coveringSearches.add(s.Name);
                }
            }
            p.pushed = [
                SELECT COUNT()
                FROM NXP_Gov_Notice__c
                WHERE Agency__c IN :scope AND Pushed__c = TRUE
                WITH USER_MODE
            ];
            p.followed = [
                SELECT COUNT()
                FROM NXP_Follow__c
                WHERE OwnerId = :me AND Gov_Notice__r.Agency__c IN :scope
                WITH USER_MODE
            ];
            return p;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static String naicsLabel(String code) {
        return String.isBlank(code) ? null : 'NAICS ' + code;
    }

    private static String joinParts(List<String> parts) {
        List<String> kept = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                kept.add(part);
            }
        }
        return String.join(kept, ' · ');
    }

    // ------------------------------------------------------------------------------- actions

    @AuraEnabled
    public static Boolean watch(Id recordId, Boolean watch) {
        try {
            return NXP_WatchService.setWatch(recordId, watch);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Re-reads the vendor's registration from SAM.gov (SAM_Entity feed settings). Admins only. */
    @AuraEnabled
    public static String refreshVendor(Id vendorId) {
        if (!FeatureManagement.checkPermission('NXP_Admin_Access')) {
            throw new AuraHandledException('Only Nexus admins can refresh vendors from SAM.gov.');
        }
        try {
            NXP_Gov_Vendor__c v = [SELECT Id, UEI__c FROM NXP_Gov_Vendor__c WHERE Id = :vendorId WITH USER_MODE];
            if (String.isBlank(v.UEI__c)) {
                return 'This vendor has no UEI, so it cannot be looked up in SAM.gov.';
            }
            NXP_IngestRecord rec = NXP_SamEntityConnector.lookup(v.UEI__c);
            if (rec == null) {
                return 'SAM.gov has no active registration for UEI ' + v.UEI__c + '.';
            }
            NXP_IngestionService.Result r = NXP_IngestionService.ingest(new List<NXP_IngestRecord>{ rec });
            if (r.rejected > 0) {
                return 'SAM.gov returned the registration, but it could not be saved: ' + String.join(r.errors, '; ');
            }
            return 'Updated from SAM.gov.';
        } catch (Exception e) {
            NXP_Logger.error('NXP_MarketController', 'Vendor refresh failed', e, vendorId);
            NXP_Logger.flush();
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------------------- helpers

    private static final String AWARD_FIELDS =
        'Id, Name, PIID__c, Agency__c, Agency__r.Name, Agency__r.Full_Path__c, NAICS_Code__c, PSC_Code__c, ' +
        'Vendor__c, Vendor__r.Name, Obligated_Amount__c, Ceiling__c, Period_Start__c, Period_End__c';

    @TestVisible
    private static List<AwardRow> toRows(List<NXP_Award_Summary__c> awards) {
        List<AwardRow> rows = new List<AwardRow>();
        if (awards.isEmpty()) {
            return rows;
        }
        Set<Id> awardIds = new Map<Id, NXP_Award_Summary__c>(awards).keySet();
        Set<Id> agencyIds = new Set<Id>();
        Set<String> naicsCodes = new Set<String>();
        for (NXP_Award_Summary__c a : awards) {
            if (a.Agency__c != null && String.isNotBlank(a.NAICS_Code__c)) {
                agencyIds.add(a.Agency__c);
                naicsCodes.add(a.NAICS_Code__c);
            }
        }
        // 1. Notices that name the award as predecessor.
        Map<Id, NXP_Gov_Notice__c> confirmed = new Map<Id, NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : [
            SELECT Id, Notice_Id__c, Notice_Type__c, Predecessor_Award__c
            FROM NXP_Gov_Notice__c
            WHERE Predecessor_Award__c IN :awardIds
            WITH USER_MODE
            ORDER BY Posted_Date__c DESC NULLS LAST
            LIMIT 500
        ]) {
            if (!confirmed.containsKey(n.Predecessor_Award__c)) {
                confirmed.put(n.Predecessor_Award__c, n);
            }
        }
        // 2. Likely follow-ons: recent active notices, then open forecasts, with the same agency and NAICS.
        Map<String, NXP_Gov_Notice__c> likelyNotice = new Map<String, NXP_Gov_Notice__c>();
        Map<String, NXP_Gov_Forecast__c> likelyForecast = new Map<String, NXP_Gov_Forecast__c>();
        if (!agencyIds.isEmpty()) {
            for (NXP_Gov_Notice__c n : [
                SELECT Id, Notice_Id__c, Notice_Type__c, Agency__c, NAICS_Code__c
                FROM NXP_Gov_Notice__c
                WHERE
                    Agency__c IN :agencyIds
                    AND NAICS_Code__c IN :naicsCodes
                    AND Status__c = 'Active'
                    AND Posted_Date__c = LAST_N_DAYS:365
                WITH USER_MODE
                ORDER BY Posted_Date__c DESC
                LIMIT 500
            ]) {
                String k = n.Agency__c + '|' + n.NAICS_Code__c;
                if (!likelyNotice.containsKey(k)) {
                    likelyNotice.put(k, n);
                }
            }
            for (NXP_Gov_Forecast__c f : [
                SELECT Id, Name, Agency__c, NAICS_Code__c
                FROM NXP_Gov_Forecast__c
                WHERE Matched_Notice__c = NULL AND Agency__c IN :agencyIds AND NAICS_Code__c IN :naicsCodes
                WITH USER_MODE
                ORDER BY Estimated_Solicitation_Date__c ASC NULLS LAST
                LIMIT 500
            ]) {
                String k = f.Agency__c + '|' + f.NAICS_Code__c;
                if (!likelyForecast.containsKey(k)) {
                    likelyForecast.put(k, f);
                }
            }
        }
        Set<Id> watched = NXP_WatchService.watchedByMe(awardIds);
        Date today = Date.today();
        for (NXP_Award_Summary__c a : awards) {
            AwardRow r = new AwardRow();
            r.id = a.Id;
            r.title = a.Name;
            r.piid = a.PIID__c;
            r.agency = a.Agency__r == null ? null : a.Agency__r.Full_Path__c;
            r.naics = a.NAICS_Code__c;
            r.psc = a.PSC_Code__c;
            r.vendorId = a.Vendor__c;
            r.vendorName = a.Vendor__r == null ? null : a.Vendor__r.Name;
            r.obligated = a.Obligated_Amount__c;
            r.ceiling = a.Ceiling__c;
            r.periodStart = a.Period_Start__c;
            r.periodEnd = a.Period_End__c;
            r.monthsLeft = a.Period_End__c == null ? null : today.monthsBetween(a.Period_End__c);
            r.watching = watched.contains(a.Id);
            String k = a.Agency__c + '|' + a.NAICS_Code__c;
            if (confirmed.containsKey(a.Id)) {
                NXP_Gov_Notice__c n = confirmed.get(a.Id);
                r.followOnKind = 'notice';
                r.followOnConfirmed = true;
                r.followOnId = n.Id;
                r.followOnLabel = n.Notice_Type__c + ': ' + n.Notice_Id__c;
            } else if (likelyNotice.containsKey(k)) {
                NXP_Gov_Notice__c n = likelyNotice.get(k);
                r.followOnKind = 'notice';
                r.followOnId = n.Id;
                r.followOnLabel = 'Likely ' + n.Notice_Type__c + ': ' + n.Notice_Id__c;
            } else if (likelyForecast.containsKey(k)) {
                NXP_Gov_Forecast__c f = likelyForecast.get(k);
                r.followOnKind = 'forecast';
                r.followOnId = f.Id;
                r.followOnLabel = 'Forecast: ' + f.Name;
            }
            rows.add(r);
        }
        return rows;
    }

    private static List<Overlap> buildOverlap(NXP_Gov_Vendor__c v, Set<String> naicsCodes, Set<String> agencyPaths) {
        ProfileMatcher profile = new ProfileMatcher();
        List<Overlap> out = new List<Overlap>();
        List<String> sharedNaics = new List<String>();
        for (String code : naicsCodes) {
            if (profile.naicsMatches(code)) {
                sharedNaics.add(code);
            }
        }
        sharedNaics.sort();
        out.add(
            sharedNaics.isEmpty()
                ? new Overlap('NAICS overlap', 'None', 'None of their award NAICS codes are in your company profile')
                : new Overlap('NAICS overlap', String.join(sharedNaics, ', '), 'In your company profile')
        );
        List<String> sharedAgencies = new List<String>();
        for (String path : agencyPaths) {
            if (profile.agencyMatches(path)) {
                sharedAgencies.add(path.substringAfterLast('›').trim());
            }
        }
        sharedAgencies.sort();
        out.add(
            sharedAgencies.isEmpty()
                ? new Overlap('Agency overlap', 'None', 'None of their agencies are target agencies in your profile')
                : new Overlap('Agency overlap', String.join(sharedAgencies, ', '), 'Target agencies in your profile')
        );
        if (v.Business_Size__c == 'Small') {
            out.add(
                new Overlap(
                    'Set-aside eligibility',
                    'Can bid small-business set-asides',
                    String.isBlank(v.Socio_Economic__c) ? 'Small' : v.Socio_Economic__c
                )
            );
        } else if (v.Business_Size__c == 'Other than small') {
            out.add(new Overlap('Set-aside eligibility', 'Can\'t bid small-business set-asides', 'Other than small'));
        } else {
            out.add(new Overlap('Set-aside eligibility', 'Unknown', 'Business size not on file; refresh from SAM.gov'));
        }
        return out;
    }

    private static List<OpenNotice> findOpenNotices(Id vendorId, Set<Id> agencyIds, Set<String> naicsCodes) {
        Map<Id, OpenNotice> byId = new Map<Id, OpenNotice>();
        Datetime now = Datetime.now();
        for (NXP_Gov_Notice__c n : [
            SELECT Id, Title__c, Name, Notice_Id__c, Notice_Type__c, Agency_Path__c, Response_Due__c, Fit_Score__c
            FROM NXP_Gov_Notice__c
            WHERE
                Status__c = 'Active'
                AND (Response_Due__c >= :now
                OR Response_Due__c = NULL)
                AND (Incumbent__c = :vendorId
                OR Predecessor_Award__r.Vendor__c = :vendorId)
            WITH USER_MODE
            ORDER BY Response_Due__c ASC NULLS LAST
            LIMIT 10
        ]) {
            byId.put(n.Id, toOpenNotice(n, 'Named as incumbent'));
        }
        if (!agencyIds.isEmpty()) {
            for (NXP_Gov_Notice__c n : [
                SELECT Id, Title__c, Name, Notice_Id__c, Notice_Type__c, Agency_Path__c, Response_Due__c, Fit_Score__c
                FROM NXP_Gov_Notice__c
                WHERE
                    Status__c = 'Active'
                    AND (Response_Due__c >= :now
                    OR Response_Due__c = NULL)
                    AND Agency__c IN :agencyIds
                    AND NAICS_Code__c IN :naicsCodes
                WITH USER_MODE
                ORDER BY Response_Due__c ASC NULLS LAST
                LIMIT 10
            ]) {
                if (!byId.containsKey(n.Id)) {
                    byId.put(n.Id, toOpenNotice(n, 'Same agency and NAICS as one of their awards ending soon'));
                }
            }
        }
        return byId.values();
    }

    private static OpenNotice toOpenNotice(NXP_Gov_Notice__c n, String reason) {
        OpenNotice o = new OpenNotice();
        o.id = n.Id;
        o.title = n.Title__c == null ? n.Name : n.Title__c;
        o.noticeKey = n.Notice_Id__c;
        o.noticeType = n.Notice_Type__c;
        o.agency = n.Agency_Path__c;
        o.responseDue = n.Response_Due__c;
        o.fitScore = n.Fit_Score__c;
        o.reason = reason;
        return o;
    }

    private static void addLike(
        List<String> clauses,
        Map<String, Object> binds,
        String field,
        String bindName,
        String value,
        Boolean contains
    ) {
        if (String.isBlank(value)) {
            return;
        }
        clauses.add(field + ' LIKE :' + bindName);
        binds.put(bindName, (contains ? '%' : '') + value.trim() + '%');
    }

    private static Exception handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return e;
        }
        AuraHandledException a = new AuraHandledException(e.getMessage());
        a.setMessage(e.getMessage());
        return a;
    }

    /** Compares NAICS, agencies and set-asides with the active Company Profile. */
    @TestVisible
    private class ProfileMatcher {
        private List<String> naics = new List<String>();
        private List<String> agencies = new List<String>();
        private List<String> setAsides = new List<String>();
        public Boolean lastMatch = false;
        public String lastNote;

        public ProfileMatcher() {
            List<NXP_Company_Profile__c> profiles = [
                SELECT NAICS_Codes__c, Target_Agency_Codes__c, Set_Asides__c
                FROM NXP_Company_Profile__c
                WHERE Active__c = TRUE
                WITH SYSTEM_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!profiles.isEmpty()) {
                naics = NXP_Text.splitList(profiles[0].NAICS_Codes__c);
                agencies = NXP_Text.splitList(profiles[0].Target_Agency_Codes__c);
                setAsides = NXP_Text.splitList(profiles[0].Set_Asides__c);
            }
        }

        public Boolean naicsMatches(String code) {
            return String.isNotBlank(code) && NXP_Text.matchesCodeList(code, naics);
        }

        public Boolean agencyMatches(String path) {
            return String.isNotBlank(path) && NXP_Text.containsAny(path, agencies);
        }

        public Boolean setAsideMatches(String setAside) {
            return String.isNotBlank(setAside) && NXP_Text.containsAny(setAside, setAsides);
        }

        /** Sets lastMatch (NAICS or agency matches) and a short note listing what matched. */
        public void describe(String code, String agencyPath, String setAside) {
            List<String> hits = new List<String>();
            if (naicsMatches(code)) {
                hits.add('NAICS');
            }
            if (agencyMatches(agencyPath)) {
                hits.add('target agency');
            }
            if (setAsideMatches(setAside)) {
                hits.add('set-aside');
            }
            lastMatch = hits.contains('NAICS') || hits.contains('target agency');
            lastNote = hits.isEmpty() ? 'No match with your company profile' : 'Matches ' + String.join(hits, ', ');
        }
    }
}
