/**
 * A saved search's criteria, stored as JSON in NXP_Saved_Search__c.Criteria_JSON__c.
 * The JSON shape is documented in docs/design/search-and-alerts.md. Every filter is optional;
 * an empty criteria object matches every active notice.
 */
public inherited sharing class NXP_SearchCriteria {
    public class MatchResult {
        public Boolean matched = false;
        public List<String> terms = new List<String>();
        /**
         * Everything matched except the keywords, and the keywords may be in the description, which
         * is still only a SAM.gov link: fetch the text and match again.
         */
        public Boolean needsDescription = false;
    }

    @AuraEnabled
    public String keywords;
    /** title, description (default both). */
    @AuraEnabled
    public List<String> searchIn;
    /** Matched (contains, case-insensitive) against the agency path and office. */
    @AuraEnabled
    public List<String> agencies;
    @AuraEnabled
    public List<String> excludeAgencies;
    /** Exact codes or prefixes ending in *. */
    @AuraEnabled
    public List<String> naics;
    @AuraEnabled
    public List<String> psc;
    /** Matched (contains) against the notice set-aside description. */
    @AuraEnabled
    public List<String> setAsides;
    @AuraEnabled
    public List<String> noticeTypes;
    /** Defaults to Active. */
    @AuraEnabled
    public List<String> statuses;
    @AuraEnabled
    public List<String> markets;
    @AuraEnabled
    public List<String> sources;
    @AuraEnabled
    public List<String> places;
    @AuraEnabled
    public List<String> vehicles;
    @AuraEnabled
    public Decimal minValue;
    @AuraEnabled
    public Decimal maxValue;
    /** When a value filter is set, also match notices that publish no value (default true). */
    @AuraEnabled
    public Boolean includeUnknownValue;
    @AuraEnabled
    public Integer dueWithinDays;
    @AuraEnabled
    public Integer postedWithinDays;
    @AuraEnabled
    public Decimal minFit;

    private transient NXP_KeywordExpression parsed;

    public static NXP_SearchCriteria parse(String json) {
        if (String.isBlank(json)) {
            return new NXP_SearchCriteria();
        }
        NXP_SearchCriteria c = (NXP_SearchCriteria) System.JSON.deserialize(json, NXP_SearchCriteria.class);
        return c == null ? new NXP_SearchCriteria() : c;
    }

    public String toJson() {
        return System.JSON.serialize(this, true);
    }

    /** Throws NXP_KeywordExpression.ParseException with a readable message if keywords are invalid. */
    public void validate() {
        expression();
        if (minValue != null && maxValue != null && minValue > maxValue) {
            throw new IllegalArgumentException('Minimum value is greater than maximum value.');
        }
    }

    public List<String> effectiveStatuses() {
        return statuses == null || statuses.isEmpty() ? new List<String>{ 'Active' } : statuses;
    }

    public MatchResult matches(NXP_Gov_Notice__c n) {
        MatchResult r = new MatchResult();
        if (
            !inList(n.Status__c, effectiveStatuses()) ||
            !inList(n.Notice_Type__c, noticeTypes) ||
            !inList(n.Market__c, markets) ||
            !inList(n.Source_Feed__c, sources)
        ) {
            return r;
        }
        if (notEmpty(naics) && !NXP_Text.matchesCodeList(n.NAICS_Code__c, naics)) {
            return r;
        }
        if (notEmpty(psc) && !NXP_Text.matchesCodeList(n.PSC_Code__c, psc)) {
            return r;
        }
        String buyer =
            (n.Agency_Path__c == null ? '' : n.Agency_Path__c) +
            ' ' +
            (n.Office__c == null ? '' : n.Office__c);
        if (notEmpty(agencies) && !NXP_Text.containsAny(buyer, agencies)) {
            return r;
        }
        if (notEmpty(excludeAgencies) && NXP_Text.containsAny(buyer, excludeAgencies)) {
            return r;
        }
        if (notEmpty(setAsides) && !NXP_Text.containsAny(n.Set_Aside__c, setAsides)) {
            return r;
        }
        if (notEmpty(places) && !NXP_Text.containsAny(n.Place_Of_Performance__c, places)) {
            return r;
        }
        if (notEmpty(vehicles)) {
            String vehicle = n.Contract_Vehicle__r == null ? null : n.Contract_Vehicle__r.Vehicle_Code__c;
            if (!NXP_Text.containsAny(vehicle, vehicles)) {
                return r;
            }
        }
        if (!valueOk(n.Estimated_Value__c)) {
            return r;
        }
        if (minFit != null && (n.Fit_Score__c == null || n.Fit_Score__c < minFit)) {
            return r;
        }
        if (dueWithinDays != null) {
            if (
                n.Response_Due__c == null ||
                n.Response_Due__c < Datetime.now() ||
                n.Response_Due__c > Datetime.now().addDays(dueWithinDays)
            ) {
                return r;
            }
        }
        if (
            postedWithinDays != null &&
            (n.Posted_Date__c == null ||
            n.Posted_Date__c < Date.today().addDays(-postedWithinDays))
        ) {
            return r;
        }
        NXP_KeywordExpression expr = expression();
        Set<String> hits = new Set<String>();
        if (!expr.isEmpty()) {
            String text = '';
            if (searchIn == null || searchIn.isEmpty() || searchIn.contains('title')) {
                text += ' ' + (n.Title__c == null ? '' : n.Title__c);
            }
            if (searchIn == null || searchIn.isEmpty() || searchIn.contains('description')) {
                text += ' ' + (n.Description__c == null ? '' : n.Description__c);
            }
            if (!expr.evaluate(NXP_KeywordExpression.normalize(text), hits)) {
                r.needsDescription =
                    (searchIn == null ||
                    searchIn.isEmpty() ||
                    searchIn.contains('description')) &&
                    n.Needs_Description__c == true &&
                    n.Description__c != null &&
                    n.Description__c.startsWithIgnoreCase('http');
                return r;
            }
        }
        r.matched = true;
        r.terms.addAll(hits);
        if (notEmpty(naics)) {
            r.terms.add(n.NAICS_Code__c);
        }
        if (notEmpty(setAsides) && n.Set_Aside__c != null) {
            r.terms.add(n.Set_Aside__c);
        }
        return r;
    }

    /** One-line, human-readable description used in alerts and by the assistant. */
    public String describe() {
        List<String> parts = new List<String>();
        if (String.isNotBlank(keywords)) {
            parts.add('keywords: ' + keywords);
        }
        addPart(parts, 'buyer', agencies);
        addPart(parts, 'NAICS', naics);
        addPart(parts, 'PSC', psc);
        addPart(parts, 'set-aside', setAsides);
        addPart(parts, 'type', noticeTypes);
        if (minValue != null) {
            parts.add('value ≥ $' + minValue.format());
        }
        if (maxValue != null) {
            parts.add('value ≤ $' + maxValue.format());
        }
        if (dueWithinDays != null) {
            parts.add('due within ' + dueWithinDays + ' days');
        }
        if (minFit != null) {
            parts.add('fit ≥ ' + minFit);
        }
        return parts.isEmpty() ? 'all active notices' : String.join(parts, '; ');
    }

    private NXP_KeywordExpression expression() {
        if (parsed == null) {
            parsed = new NXP_KeywordExpression(keywords);
        }
        return parsed;
    }

    private Boolean valueOk(Decimal value) {
        if (minValue == null && maxValue == null) {
            return true;
        }
        if (value == null) {
            return includeUnknownValue != false;
        }
        return (minValue == null || value >= minValue) && (maxValue == null || value <= maxValue);
    }

    private static Boolean inList(String value, List<String> allowed) {
        if (allowed == null || allowed.isEmpty()) {
            return true;
        }
        return value != null && NXP_Text.lowerSet(allowed).contains(value.toLowerCase());
    }

    private static Boolean notEmpty(List<String> values) {
        return values != null && !values.isEmpty();
    }

    private static void addPart(List<String> parts, String label, List<String> values) {
        if (notEmpty(values)) {
            parts.add(label + ': ' + String.join(values, ', '));
        }
    }
}
