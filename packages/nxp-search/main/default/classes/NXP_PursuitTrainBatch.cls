/**
 * Trains the Likely to Pursue model from decisions in Nexus, then scores the open notices.
 *
 * A notice counts as pursued when it was pushed to Opportunity, and as passed when someone dismissed it
 * in the Match Inbox and it was never pushed. Everything else (not decided yet) is left out.
 * The newest 20% of decisions are held out to measure how well the model ranks (AUC); the saved model
 * then learns from all of them. With fewer decisions than Pursuit_Min_Decisions (default 200), or under
 * 20 on either side, the model is saved as Collecting and no notice is scored.
 */
public with sharing class NXP_PursuitTrainBatch implements Database.Batchable<SObject>, Database.Stateful {
    private class Decision {
        Datetime decidedOn;
        Map<String, String> features;
        Boolean pursued;
    }

    private final List<Decision> decisions = new List<Decision>();
    private static final Integer MAX_DECISIONS = 20000;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT ' + NXP_PursuitModel.NOTICE_FIELDS + ' FROM NXP_Gov_Notice__c ORDER BY CreatedDate',
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext bc, List<NXP_Gov_Notice__c> scope) {
        Set<Id> ids = new Map<Id, NXP_Gov_Notice__c>(scope).keySet();
        Set<Id> dismissed = new Set<Id>();
        for (NXP_Search_Match__c m : [
            SELECT Gov_Notice__c
            FROM NXP_Search_Match__c
            WHERE Gov_Notice__c IN :ids AND User_Action__c = 'Dismissed'
            WITH SYSTEM_MODE
        ]) {
            dismissed.add(m.Gov_Notice__c);
        }
        Map<Id, Boolean> held = NXP_PursuitModel.vehiclesHeld(scope);
        for (NXP_Gov_Notice__c n : scope) {
            Boolean pursued = n.Pushed__c == true;
            if (!pursued && !dismissed.contains(n.Id)) {
                continue;
            }
            if (decisions.size() >= MAX_DECISIONS) {
                decisions.remove(0);
            }
            Decision d = new Decision();
            d.pursued = pursued;
            d.decidedOn = n.Posted_Date__c != null
                ? Datetime.newInstance(n.Posted_Date__c, Time.newInstance(0, 0, 0, 0))
                : n.CreatedDate;
            d.features = NXP_PursuitModel.features(
                n,
                n.Contract_Vehicle__c == null ? null : held.get(n.Contract_Vehicle__c)
            );
            decisions.add(d);
        }
    }

    public void finish(Database.BatchableContext bc) {
        NXP_Pursuit_Model__c row = train();
        insert as system row;
        if (row.Status__c == 'Active' && !Test.isRunningTest()) {
            Database.executeBatch(new NXP_PursuitScoreBatch(false), 500);
        }
    }

    @TestVisible
    private NXP_Pursuit_Model__c train() {
        Integer pursuedCount = 0;
        for (Decision d : decisions) {
            pursuedCount += d.pursued ? 1 : 0;
        }
        Integer passedCount = decisions.size() - pursuedCount;
        Integer minDecisions = NXP_Settings.getInteger('Pursuit_Min_Decisions', 200);
        NXP_Pursuit_Model__c row = new NXP_Pursuit_Model__c(
            Trained__c = Datetime.now(),
            Decisions__c = decisions.size(),
            Pursued__c = pursuedCount
        );
        if (decisions.size() < minDecisions || pursuedCount < 20 || passedCount < 20) {
            row.Status__c = 'Collecting';
            row.Detail__c =
                'Not enough decisions yet: ' +
                decisions.size() +
                ' of ' +
                minDecisions +
                ' (' +
                pursuedCount +
                ' pushed, ' +
                passedCount +
                ' dismissed; at least 20 of each are needed). Keep pushing and dismissing with reasons.';
            return row;
        }

        // Hold out the newest 20% to see how well it ranks decisions it hasn't seen.
        List<Decision> ordered = sortByDate(decisions);
        Integer cut = (Integer) Math.floor(ordered.size() * 0.8);
        NXP_PursuitModel trial = new NXP_PursuitModel();
        for (Integer i = 0; i < cut; i++) {
            trial.learn(ordered[i].features, ordered[i].pursued);
        }
        List<Double> pursuedScores = new List<Double>();
        List<Double> passedScores = new List<Double>();
        for (Integer i = cut; i < ordered.size(); i++) {
            Double s = trial.score(ordered[i].features).likelihood;
            if (ordered[i].pursued) {
                pursuedScores.add(s);
            } else {
                passedScores.add(s);
            }
        }
        row.AUC__c = NXP_PursuitModel.auc(pursuedScores, passedScores);

        NXP_PursuitModel model = new NXP_PursuitModel();
        for (Decision d : ordered) {
            model.learn(d.features, d.pursued);
        }
        row.Model_Json__c = model.toJson();
        row.Status__c = 'Active';
        row.Detail__c =
            'Learned from ' +
            decisions.size() +
            ' decisions (' +
            pursuedCount +
            ' pushed, ' +
            passedCount +
            ' dismissed). ' +
            (row.AUC__c == null
                ? 'Too few recent decisions to measure accuracy.'
                : 'On the newest ' +
                  (ordered.size() - cut) +
                  ' decisions it ranked a pushed notice above a dismissed one ' +
                  (row.AUC__c * 100).setScale(0) +
                  '% of the time (50% = chance).');
        return row;
    }

    private static List<Decision> sortByDate(List<Decision> input) {
        Map<Long, List<Decision>> byTime = new Map<Long, List<Decision>>();
        for (Decision d : input) {
            Long t = d.decidedOn == null ? 0 : d.decidedOn.getTime();
            if (!byTime.containsKey(t)) {
                byTime.put(t, new List<Decision>());
            }
            byTime.get(t).add(d);
        }
        List<Long> times = new List<Long>(byTime.keySet());
        times.sort();
        List<Decision> out = new List<Decision>();
        for (Long t : times) {
            out.addAll(byTime.get(t));
        }
        return out;
    }

    /** Adds one decision directly (tests). */
    @TestVisible
    private void add(Map<String, String> features, Boolean pursued, Datetime decidedOn) {
        Decision d = new Decision();
        d.features = features;
        d.pursued = pursued;
        d.decidedOn = decidedOn;
        decisions.add(d);
    }
}
