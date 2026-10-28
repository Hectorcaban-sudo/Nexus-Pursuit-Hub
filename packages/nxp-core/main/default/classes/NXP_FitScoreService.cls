/**
 * Rules-based fit score (0-100) for Gov Notices against the active Company Profile.
 * Weights come from NXP_Fit_Rule__mdt; each rule's points and reason are stored as JSON in
 * Fit_Breakdown__c so the UI and the assistant can explain the score.
 */
public inherited sharing class NXP_FitScoreService {
    public class RuleResult {
        @AuraEnabled
        public String rule;
        @AuraEnabled
        public Decimal weight;
        @AuraEnabled
        public Decimal points;
        @AuraEnabled
        public String reason;
    }

    @TestVisible
    private static NXP_Company_Profile__c profileOverride;
    @TestVisible
    private static List<NXP_Fit_Rule__mdt> rulesOverride;

    private final NXP_Company_Profile__c profile;
    private final List<NXP_Fit_Rule__mdt> rules;

    public NXP_FitScoreService() {
        this.profile = loadProfile();
        this.rules = loadRules();
    }

    public Boolean isConfigured() {
        return profile != null && !rules.isEmpty();
    }

    /** Sets Fit_Score__c and Fit_Breakdown__c on the given (in-memory) records. No DML. */
    public void score(List<NXP_Gov_Notice__c> notices) {
        if (!isConfigured()) {
            return;
        }
        for (NXP_Gov_Notice__c n : notices) {
            List<RuleResult> results = evaluate(n);
            Decimal total = 0;
            for (RuleResult r : results) {
                total += r.points;
            }
            n.Fit_Score__c = Math.min(100, total.setScale(0, RoundingMode.HALF_UP));
            n.Fit_Breakdown__c = JSON.serialize(results);
        }
    }

    public List<RuleResult> evaluate(NXP_Gov_Notice__c n) {
        List<RuleResult> results = new List<RuleResult>();
        for (NXP_Fit_Rule__mdt rule : rules) {
            results.add(evaluateRule(rule, n));
        }
        return results;
    }

    /** Plain-English explanation used by the assistant's Explain Fit Score action. */
    public static String explain(NXP_Gov_Notice__c n) {
        if (n == null || String.isBlank(n.Fit_Breakdown__c)) {
            return 'This notice has not been scored yet. Check that an active Company Profile and Fit Rules exist.';
        }
        List<RuleResult> results = (List<RuleResult>) JSON.deserialize(n.Fit_Breakdown__c, List<RuleResult>.class);
        List<String> lines = new List<String>{ 'Fit score ' + n.Fit_Score__c + ' out of 100:' };
        for (RuleResult r : results) {
            lines.add('- ' + r.rule + ': ' + r.points + ' of ' + r.weight + ' (' + r.reason + ')');
        }
        return String.join(lines, '\n');
    }

    private RuleResult evaluateRule(NXP_Fit_Rule__mdt rule, NXP_Gov_Notice__c n) {
        RuleResult r = new RuleResult();
        r.rule = rule.Rule_Type__c;
        r.weight = rule.Weight__c == null ? 0 : rule.Weight__c;
        r.points = 0;
        switch on rule.Rule_Type__c {
            when 'NAICS' {
                Boolean hit = NXP_Text.matchesCodeList(n.NAICS_Code__c, NXP_Text.splitList(profile.NAICS_Codes__c));
                award(
                    r,
                    hit ? 1 : 0,
                    hit ? 'NAICS ' + n.NAICS_Code__c + ' is in our profile' : 'NAICS not in our profile'
                );
            }
            when 'PSC' {
                Boolean hit = NXP_Text.matchesCodeList(n.PSC_Code__c, NXP_Text.splitList(profile.PSC_Codes__c));
                award(r, hit ? 1 : 0, hit ? 'PSC ' + n.PSC_Code__c + ' is in our profile' : 'PSC not in our profile');
            }
            when 'Agency' {
                String buyer =
                    (n.Agency_Path__c == null ? '' : n.Agency_Path__c) +
                    ' ' +
                    (n.Office__c == null ? '' : n.Office__c);
                Boolean hit = NXP_Text.containsAny(buyer, NXP_Text.splitList(profile.Target_Agency_Codes__c));
                award(r, hit ? 1 : 0, hit ? 'Target agency' : 'Not a target agency');
            }
            when 'Set-Aside' {
                List<String> ours = NXP_Text.splitList(profile.Set_Asides__c);
                if (String.isBlank(n.Set_Aside__c) || n.Set_Aside__c.containsIgnoreCase('none')) {
                    award(r, 0.5, 'Full and open competition');
                } else {
                    Boolean hit = NXP_Text.containsAny(n.Set_Aside__c, ours);
                    award(
                        r,
                        hit ? 1 : 0,
                        hit ? 'We qualify for ' + n.Set_Aside__c : 'We do not qualify for ' + n.Set_Aside__c
                    );
                }
            }
            when 'Keyword' {
                List<String> keywords = NXP_Text.splitList(profile.Keywords__c);
                String text = ((n.Title__c == null ? '' : n.Title__c) +
                    ' ' +
                    (n.Description__c == null ? '' : n.Description__c))
                    .toLowerCase();
                Integer hits = 0;
                List<String> found = new List<String>();
                for (String k : keywords) {
                    if (text.contains(k.toLowerCase())) {
                        hits++;
                        found.add(k);
                    }
                }
                // Three or more capability keywords earns full points.
                Decimal ratio = keywords.isEmpty() ? 0 : Math.min(1, hits / 3.0);
                award(r, ratio, hits == 0 ? 'No capability keywords found' : 'Found: ' + String.join(found, ', '));
            }
            when 'Value Range' {
                if (n.Estimated_Value__c == null) {
                    award(r, 0.5, 'Value not published');
                } else {
                    Boolean aboveMin = profile.Min_Value__c == null || n.Estimated_Value__c >= profile.Min_Value__c;
                    Boolean belowMax = profile.Max_Value__c == null || n.Estimated_Value__c <= profile.Max_Value__c;
                    award(
                        r,
                        aboveMin && belowMax ? 1 : 0,
                        aboveMin && belowMax ? 'Value in our range' : 'Value outside our range'
                    );
                }
            }
            when 'Vehicle' {
                Boolean hit = n.Contract_Vehicle__c != null && profile.Vehicle_Codes__c != null;
                award(r, hit ? 1 : 0, hit ? 'On a vehicle we hold' : 'No vehicle match');
            }
            when else {
                award(r, 0, 'Unknown rule type');
            }
        }
        return r;
    }

    private static void award(RuleResult r, Decimal fraction, String reason) {
        r.points = (r.weight * fraction).setScale(0, RoundingMode.HALF_UP);
        r.reason = reason;
    }

    private static NXP_Company_Profile__c loadProfile() {
        if (profileOverride != null) {
            return profileOverride;
        }
        List<NXP_Company_Profile__c> profiles = [
            SELECT
                Id,
                NAICS_Codes__c,
                PSC_Codes__c,
                Set_Asides__c,
                Target_Agency_Codes__c,
                Keywords__c,
                Vehicle_Codes__c,
                Min_Value__c,
                Max_Value__c
            FROM NXP_Company_Profile__c
            WHERE Active__c = TRUE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return profiles.isEmpty() ? null : profiles[0];
    }

    private static List<NXP_Fit_Rule__mdt> loadRules() {
        if (rulesOverride != null) {
            return rulesOverride;
        }
        List<NXP_Fit_Rule__mdt> active = new List<NXP_Fit_Rule__mdt>();
        for (NXP_Fit_Rule__mdt rule : NXP_Fit_Rule__mdt.getAll().values()) {
            if (rule.Active__c) {
                active.add(rule);
            }
        }
        return active;
    }
}
