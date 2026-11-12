/**
 * Likely to Pursue: a small, explainable model of which notices BD pursues.
 *
 * It learns from decisions already in Nexus: a notice that was pushed to Opportunity counts as pursued;
 * a notice dismissed from the Match Inbox (and never pushed) counts as passed. For each factor of a
 * notice (department, sub-agency, NAICS group, notice type, set-aside, source, vehicle, value band, fit
 * band) it counts how often notices with that value were pursued or passed. A notice's likelihood
 * combines those counts (naive Bayes with add-one smoothing), and the factors that moved it most are
 * kept so users can see why, the same way fit reasons are shown.
 *
 * It is not a win probability. It learns what BD chose before, so it sits beside the fit score.
 */
public with sharing class NXP_PursuitModel {
    /** Factor groups, in the order shown to users, with their labels. */
    public static final Map<String, String> GROUPS = new Map<String, String>{
        'dept' => 'Department',
        'agency' => 'Agency',
        'naics' => 'NAICS group',
        'type' => 'Notice type',
        'setaside' => 'Set-aside',
        'source' => 'Source',
        'vehicle' => 'Vehicle',
        'value' => 'Estimated value',
        'fit' => 'Fit'
    };

    public class Factor {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public Integer pursued;
        @AuraEnabled
        public Integer decided;
        /** up or down: whether this factor raised or lowered the likelihood. */
        @AuraEnabled
        public String direction;
        public Double weight;
    }

    public class Score {
        public Integer likelihood;
        public List<Factor> factors = new List<Factor>();
    }

    /** group -> value -> [pursued, passed]; plus totals. Serialized into NXP_Pursuit_Model__c.Model_Json__c. */
    public Map<String, Map<String, List<Integer>>> counts = new Map<String, Map<String, List<Integer>>>();
    public Integer pursued = 0;
    public Integer passed = 0;

    // ------------------------------------------------------------------ features

    /** The factor values of a notice. vehicleHeld: null when the notice has no vehicle. */
    public static Map<String, String> features(NXP_Gov_Notice__c n, Boolean vehicleHeld) {
        Map<String, String> f = new Map<String, String>();
        List<String> path = String.isBlank(n.Agency_Path__c)
            ? new List<String>()
            : n.Agency_Path__c.replace('>', '›').split('›');
        f.put('dept', path.isEmpty() ? 'Unknown' : path[0].trim());
        f.put('agency', path.size() < 2 ? '(Department level)' : path[1].trim());
        f.put('naics', String.isBlank(n.NAICS_Code__c) ? 'Unknown' : n.NAICS_Code__c.left(4) + '*');
        f.put('type', String.isBlank(n.Notice_Type__c) ? 'Unknown' : n.Notice_Type__c);
        f.put('setaside', setAside(n.Set_Aside__c));
        f.put('source', String.isBlank(n.Source__c) ? 'Other' : n.Source__c);
        f.put(
            'vehicle',
            vehicleHeld == null ? 'No vehicle' : (vehicleHeld ? 'Vehicle we hold' : 'Vehicle we don\'t hold')
        );
        f.put('value', valueBand(n.Estimated_Value__c));
        f.put('fit', fitBand(n.Fit_Score__c));
        return f;
    }

    private static String setAside(String s) {
        if (String.isBlank(s)) {
            return 'None';
        }
        String l = s.toLowerCase();
        if (l == 'none' || l.contains('full and open') || l.contains('no set aside') || l.contains('no set-aside')) {
            return 'None';
        }
        return s;
    }

    private static String valueBand(Decimal v) {
        if (v == null) {
            return 'Not published';
        }
        if (v < 1000000) {
            return 'Under $1M';
        }
        if (v < 10000000) {
            return '$1M-$10M';
        }
        if (v < 50000000) {
            return '$10M-$50M';
        }
        return '$50M and up';
    }

    private static String fitBand(Decimal fit) {
        if (fit == null) {
            return 'Not scored';
        }
        if (fit >= 75) {
            return '75-100';
        }
        if (fit >= 60) {
            return '60-74';
        }
        if (fit >= 40) {
            return '40-59';
        }
        return 'Under 40';
    }

    /** Vehicle held (true/false) for each vehicle Id; notices without a vehicle are not in the map. */
    public static Map<Id, Boolean> vehiclesHeld(List<NXP_Gov_Notice__c> notices) {
        Set<Id> ids = new Set<Id>();
        for (NXP_Gov_Notice__c n : notices) {
            if (n.Contract_Vehicle__c != null) {
                ids.add(n.Contract_Vehicle__c);
            }
        }
        Map<Id, Boolean> out = new Map<Id, Boolean>();
        if (!ids.isEmpty()) {
            for (NXP_Contract_Vehicle__c v : [
                SELECT Id, We_Hold__c
                FROM NXP_Contract_Vehicle__c
                WHERE Id IN :ids
                WITH SYSTEM_MODE
            ]) {
                out.put(v.Id, v.We_Hold__c);
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ learning and scoring

    public void learn(Map<String, String> f, Boolean wasPursued) {
        if (wasPursued) {
            pursued++;
        } else {
            passed++;
        }
        for (String g : f.keySet()) {
            Map<String, List<Integer>> byValue = counts.get(g);
            if (byValue == null) {
                byValue = new Map<String, List<Integer>>();
                counts.put(g, byValue);
            }
            List<Integer> c = byValue.get(f.get(g));
            if (c == null) {
                c = new List<Integer>{ 0, 0 };
                byValue.put(f.get(g), c);
            }
            c[wasPursued ? 0 : 1]++;
        }
    }

    /** Log-odds of pursuit (naive Bayes, add-one smoothing) and each factor's part in it. */
    public Score score(Map<String, String> f) {
        Score s = new Score();
        Double logit = Math.log((pursued + 1.0) / (passed + 1.0));
        for (String g : GROUPS.keySet()) {
            if (!f.containsKey(g)) {
                continue;
            }
            Map<String, List<Integer>> byValue = counts.containsKey(g)
                ? counts.get(g)
                : new Map<String, List<Integer>>();
            Integer kinds = byValue.size() + 1;
            List<Integer> c = byValue.containsKey(f.get(g)) ? byValue.get(f.get(g)) : new List<Integer>{ 0, 0 };
            Double w = Math.log((c[0] + 1.0) / (pursued + kinds)) - Math.log((c[1] + 1.0) / (passed + kinds));
            logit += w;
            Factor x = new Factor();
            x.label = GROUPS.get(g);
            x.value = f.get(g);
            x.pursued = c[0];
            x.decided = c[0] + c[1];
            x.weight = w;
            x.direction = w >= 0 ? 'up' : 'down';
            s.factors.add(x);
        }
        Double p = 1.0 / (1.0 + Math.exp(-logit));
        s.likelihood = Math.max(1, Math.min(99, Math.round(p * 100)));
        // The factors that moved it most, with enough history to mean something.
        List<Factor> strong = new List<Factor>();
        for (Factor x : s.factors) {
            if (x.decided >= 3 && Math.abs(x.weight) >= 0.2) {
                strong.add(x);
            }
        }
        for (Integer i = 0; i < strong.size(); i++) {
            for (Integer j = i + 1; j < strong.size(); j++) {
                if (Math.abs(strong[j].weight) > Math.abs(strong[i].weight)) {
                    Factor t = strong[i];
                    strong[i] = strong[j];
                    strong[j] = t;
                }
            }
        }
        s.factors = new List<Factor>();
        for (Integer i = 0; i < strong.size() && i < 4; i++) {
            s.factors.add(strong[i]);
        }
        return s;
    }

    /**
     * How well scores rank pursued above passed notices (AUC): 0.5 is chance, 1.0 perfect.
     * Null when either side is empty.
     */
    public static Decimal auc(List<Double> pursuedScores, List<Double> passedScores) {
        if (pursuedScores.isEmpty() || passedScores.isEmpty()) {
            return null;
        }
        Double wins = 0;
        for (Double a : pursuedScores) {
            for (Double b : passedScores) {
                wins += a > b ? 1.0 : (a == b ? 0.5 : 0.0);
            }
        }
        return Decimal.valueOf(wins / (pursuedScores.size() * passedScores.size())).setScale(3);
    }

    public String toJson() {
        return JSON.serialize(new Map<String, Object>{ 'pursued' => pursued, 'passed' => passed, 'counts' => counts });
    }

    public static NXP_PursuitModel fromJson(String s) {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(s);
        NXP_PursuitModel model = new NXP_PursuitModel();
        model.pursued = (Integer) m.get('pursued');
        model.passed = (Integer) m.get('passed');
        Map<String, Object> groups = (Map<String, Object>) m.get('counts');
        for (String g : groups.keySet()) {
            Map<String, List<Integer>> byValue = new Map<String, List<Integer>>();
            Map<String, Object> values = (Map<String, Object>) groups.get(g);
            for (String v : values.keySet()) {
                List<Object> c = (List<Object>) values.get(v);
                byValue.put(v, new List<Integer>{ (Integer) c[0], (Integer) c[1] });
            }
            model.counts.put(g, byValue);
        }
        return model;
    }

    /** The active model, or null when none has been trained with enough decisions. */
    public static NXP_PursuitModel active() {
        List<NXP_Pursuit_Model__c> rows = [
            SELECT Model_Json__c
            FROM NXP_Pursuit_Model__c
            WHERE Status__c = 'Active'
            WITH SYSTEM_MODE
            ORDER BY Trained__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() || String.isBlank(rows[0].Model_Json__c) ? null : fromJson(rows[0].Model_Json__c);
    }

    /** Scores notices with the model and writes the likelihood and its factors on them. */
    public static void apply(NXP_PursuitModel model, List<NXP_Gov_Notice__c> notices) {
        Map<Id, Boolean> held = vehiclesHeld(notices);
        List<NXP_Gov_Notice__c> updates = new List<NXP_Gov_Notice__c>();
        Datetime now = Datetime.now();
        for (NXP_Gov_Notice__c n : notices) {
            Score s = model.score(features(n, n.Contract_Vehicle__c == null ? null : held.get(n.Contract_Vehicle__c)));
            updates.add(
                new NXP_Gov_Notice__c(
                    Id = n.Id,
                    Pursuit_Likelihood__c = s.likelihood,
                    Pursuit_Factors__c = JSON.serialize(s.factors).left(4000),
                    Pursuit_Scored__c = now
                )
            );
        }
        // Only the prediction fields change: skip the notice trigger (no re-scoring or matching).
        NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
    }

    /** Query fields every pursuit batch needs. */
    public static final String NOTICE_FIELDS =
        'Id, Agency_Path__c, NAICS_Code__c, Notice_Type__c, Set_Aside__c, Source__c, Contract_Vehicle__c, ' +
        'Estimated_Value__c, Fit_Score__c, Pushed__c, Posted_Date__c, CreatedDate';
}
