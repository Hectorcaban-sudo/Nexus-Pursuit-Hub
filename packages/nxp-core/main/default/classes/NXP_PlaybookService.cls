/**
 * Playbooks: short next steps for a notice, picked by rules (NXP_Playbook__mdt) from what Nexus already
 * knows: notice type, source, set-aside, vehicle held and fit. The first active rule, by Order, whose
 * conditions fit the notice gives its steps. Ticks are NXP_Playbook_Step__c rows, shared by the team.
 * The playbook ends at the decision: push, watch or dismiss. Capture happens in Opportunity.
 */
public with sharing class NXP_PlaybookService {
    public class Step {
        @AuraEnabled
        public Integer stepNumber;
        @AuraEnabled
        public String text;
        @AuraEnabled
        public Date due;
        @AuraEnabled
        public Boolean done = false;
        @AuraEnabled
        public String doneBy;
        @AuraEnabled
        public Datetime doneOn;
        @AuraEnabled
        public Boolean overdue = false;
    }

    public class Plan {
        @AuraEnabled
        public String playbook;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        /** Why this playbook: the conditions that matched, in words. */
        @AuraEnabled
        public List<String> reasons = new List<String>();
        @AuraEnabled
        public List<Step> steps = new List<Step>();
        @AuraEnabled
        public Integer doneCount = 0;
        /** Due date of the last dated step: when to decide. */
        @AuraEnabled
        public Date decideBy;
        /** First step not done (null when all are done). */
        @AuraEnabled
        public Step nextStep;
        @AuraEnabled
        public Boolean overdue = false;
    }

    /** One parsed line of Steps__c. */
    public class StepDef {
        public String text;
        /** Days before the response is due (when afterPosted is false) or after it was posted. */
        public Integer offset;
        public Boolean afterPosted = false;
    }

    @TestVisible
    private static List<NXP_Playbook__mdt> rulesOverride;

    public static List<NXP_Playbook__mdt> rules() {
        if (rulesOverride != null) {
            return rulesOverride;
        }
        List<NXP_Playbook__mdt> out = new List<NXP_Playbook__mdt>();
        for (NXP_Playbook__mdt r : [
            SELECT
                DeveloperName,
                MasterLabel,
                Active__c,
                Order__c,
                Description__c,
                Notice_Types__c,
                Sources__c,
                Set_Aside__c,
                Vehicle_Held__c,
                Min_Fit__c,
                Steps__c
            FROM NXP_Playbook__mdt
            WHERE Active__c = TRUE
            ORDER BY Order__c ASC NULLS LAST, MasterLabel
        ]) {
            out.add(r);
        }
        return out;
    }

    /** The plan for one notice, or null when no playbook fits. */
    public static Plan planFor(NXP_Gov_Notice__c n) {
        return plansFor(new List<NXP_Gov_Notice__c>{ n }).get(n.Id);
    }

    /** Plans for many notices (Match Inbox), with the team's ticks. Notices no rule fits are left out. */
    public static Map<Id, Plan> plansFor(List<NXP_Gov_Notice__c> notices) {
        Map<Id, Plan> out = new Map<Id, Plan>();
        List<NXP_Playbook__mdt> rules = rules();
        if (notices == null || notices.isEmpty() || rules.isEmpty()) {
            return out;
        }
        Set<Id> vehicleIds = new Set<Id>();
        for (NXP_Gov_Notice__c n : notices) {
            if (n.Contract_Vehicle__c != null) {
                vehicleIds.add(n.Contract_Vehicle__c);
            }
        }
        Set<Id> held = new Set<Id>();
        if (!vehicleIds.isEmpty()) {
            for (NXP_Contract_Vehicle__c v : [
                SELECT Id
                FROM NXP_Contract_Vehicle__c
                WHERE Id IN :vehicleIds AND We_Hold__c = TRUE
                WITH SYSTEM_MODE
            ]) {
                held.add(v.Id);
            }
        }
        Map<Id, NXP_Playbook__mdt> chosen = new Map<Id, NXP_Playbook__mdt>();
        for (NXP_Gov_Notice__c n : notices) {
            NXP_Playbook__mdt r = match(n, held.contains(n.Contract_Vehicle__c), rules);
            if (r != null) {
                chosen.put(n.Id, r);
            }
        }
        if (chosen.isEmpty()) {
            return out;
        }
        Map<String, NXP_Playbook_Step__c> ticks = new Map<String, NXP_Playbook_Step__c>();
        Set<Id> noticeIds = chosen.keySet();
        for (NXP_Playbook_Step__c s : [
            SELECT Gov_Notice__c, Playbook__c, Step_Number__c, Done__c, Done_By__r.Name, Done_On__c
            FROM NXP_Playbook_Step__c
            WHERE Gov_Notice__c IN :noticeIds AND Done__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            ticks.put(s.Gov_Notice__c + ':' + s.Playbook__c + ':' + s.Step_Number__c.intValue(), s);
        }
        Date today = Date.today();
        for (NXP_Gov_Notice__c n : notices) {
            NXP_Playbook__mdt r = chosen.get(n.Id);
            if (r == null) {
                continue;
            }
            Plan p = new Plan();
            p.playbook = r.DeveloperName;
            p.label = r.MasterLabel;
            p.description = r.Description__c;
            p.reasons = reasons(n, r);
            Integer i = 0;
            for (StepDef d : parseSteps(r.Steps__c)) {
                i++;
                Step s = new Step();
                s.stepNumber = i;
                s.text = d.text;
                s.due = dueDate(n, d);
                NXP_Playbook_Step__c t = ticks.get(n.Id + ':' + r.DeveloperName + ':' + i);
                if (t != null) {
                    s.done = true;
                    s.doneBy = t.Done_By__r == null ? null : t.Done_By__r.Name;
                    s.doneOn = t.Done_On__c;
                    p.doneCount++;
                }
                s.overdue = !s.done && s.due != null && s.due < today;
                if (s.due != null) {
                    p.decideBy = s.due;
                }
                if (!s.done && p.nextStep == null) {
                    p.nextStep = s;
                }
                p.overdue = p.overdue || s.overdue;
                p.steps.add(s);
            }
            if (!p.steps.isEmpty()) {
                out.put(n.Id, p);
            }
        }
        return out;
    }

    /** The first rule whose conditions all fit the notice. */
    public static NXP_Playbook__mdt match(NXP_Gov_Notice__c n, Boolean vehicleHeld, List<NXP_Playbook__mdt> rules) {
        for (NXP_Playbook__mdt r : rules) {
            if (r.Active__c == false || String.isBlank(r.Steps__c)) {
                continue;
            }
            if (!inList(r.Notice_Types__c, n.Notice_Type__c)) {
                continue;
            }
            String source = String.isNotBlank(n.Source__c)
                ? n.Source__c
                : NXP_GovNoticeTriggerHandler.sourceFor(n.Source_Feed__c);
            if (!inList(r.Sources__c, source)) {
                continue;
            }
            if (r.Min_Fit__c != null && r.Min_Fit__c > 0 && (n.Fit_Score__c == null || n.Fit_Score__c < r.Min_Fit__c)) {
                continue;
            }
            String held = r.Vehicle_Held__c == null ? '' : r.Vehicle_Held__c.trim().toLowerCase();
            if ((held == 'yes' && vehicleHeld != true) || (held == 'no' && vehicleHeld == true)) {
                continue;
            }
            String aside = r.Set_Aside__c == null ? '' : r.Set_Aside__c.trim().toLowerCase();
            Boolean isSetAside = isSetAside(n.Set_Aside__c);
            if ((aside == 'set-aside only' && !isSetAside) || (aside == 'full and open only' && isSetAside)) {
                continue;
            }
            return r;
        }
        return null;
    }

    /** A set-aside other than none or full and open. */
    public static Boolean isSetAside(String setAside) {
        if (String.isBlank(setAside)) {
            return false;
        }
        String s = setAside.toLowerCase();
        return !(s == 'none' ||
        s.contains('full and open') ||
        s.contains('no set aside') ||
        s.contains('no set-aside'));
    }

    private static Boolean inList(String csv, String value) {
        if (String.isBlank(csv)) {
            return true;
        }
        if (String.isBlank(value)) {
            return false;
        }
        for (String part : csv.split(',')) {
            if (part.trim().equalsIgnoreCase(value.trim())) {
                return true;
            }
        }
        return false;
    }

    private static List<String> reasons(NXP_Gov_Notice__c n, NXP_Playbook__mdt r) {
        List<String> out = new List<String>();
        if (String.isNotBlank(r.Notice_Types__c)) {
            out.add('Notice type: ' + n.Notice_Type__c);
        }
        if (String.isNotBlank(r.Sources__c)) {
            out.add('Source: ' + (String.isNotBlank(n.Source__c) ? n.Source__c : n.Source_Feed__c));
        }
        if (r.Vehicle_Held__c != null && r.Vehicle_Held__c.trim().equalsIgnoreCase('yes')) {
            out.add('On a vehicle we hold');
        }
        if (r.Set_Aside__c != null && r.Set_Aside__c.trim().equalsIgnoreCase('set-aside only')) {
            out.add('Set-aside: ' + n.Set_Aside__c);
        }
        if (r.Min_Fit__c != null) {
            out.add('Fit ' + (n.Fit_Score__c == null ? 0 : n.Fit_Score__c.intValue()));
        }
        if (n.Response_Due__c != null) {
            Integer days = Date.today().daysBetween(n.Response_Due__c.date());
            out.add(days >= 0 ? days + ' days left' : 'Response date passed');
        }
        return out;
    }

    /** Steps__c lines: "Step text", "Step text | 10" (days before due) or "Step text | +2" (days after posted). */
    public static List<StepDef> parseSteps(String steps) {
        List<StepDef> out = new List<StepDef>();
        if (String.isBlank(steps)) {
            return out;
        }
        for (String line : steps.split('\n')) {
            String text = line.substringBefore('|').trim();
            if (String.isBlank(text)) {
                continue;
            }
            StepDef d = new StepDef();
            d.text = text.left(255);
            String rule = line.contains('|') ? line.substringAfter('|').trim() : '';
            if (rule.startsWith('+')) {
                d.afterPosted = true;
                rule = rule.substring(1).trim();
            }
            if (rule.isNumeric()) {
                d.offset = Integer.valueOf(rule);
            }
            out.add(d);
        }
        return out;
    }

    private static Date dueDate(NXP_Gov_Notice__c n, StepDef d) {
        if (d.offset == null) {
            return null;
        }
        if (d.afterPosted) {
            Date posted = n.Posted_Date__c != null ? n.Posted_Date__c : n.CreatedDate?.date();
            return posted == null ? null : posted.addDays(d.offset);
        }
        if (n.Response_Due__c == null) {
            return null;
        }
        Date due = n.Response_Due__c.date().addDays(-d.offset);
        // A step whose date is before the notice was posted is due when it arrives.
        Date posted = n.Posted_Date__c != null ? n.Posted_Date__c : n.CreatedDate?.date();
        return posted != null && due < posted ? posted : due;
    }

    /** Ticks or unticks one step for the team. Returns the updated plan. */
    public static Plan setDone(Id noticeId, Integer stepNumber, Boolean done) {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            throw new PlaybookException('Notice not found or not visible to you.');
        }
        Plan p = planFor(n);
        if (p == null || stepNumber == null || stepNumber < 1 || stepNumber > p.steps.size()) {
            throw new PlaybookException('That step is no longer in the playbook. Refresh the page.');
        }
        NXP_Playbook_Step__c row = new NXP_Playbook_Step__c(
            Key__c = noticeId + ':' + p.playbook + ':' + stepNumber,
            Gov_Notice__c = noticeId,
            Playbook__c = p.playbook,
            Step_Number__c = stepNumber,
            Step__c = p.steps[stepNumber - 1].text,
            Done__c = done == true,
            Done_By__c = done == true ? UserInfo.getUserId() : null,
            Done_On__c = done == true ? Datetime.now() : null
        );
        Database.upsert(row, NXP_Playbook_Step__c.Key__c, true, AccessLevel.USER_MODE);
        return planFor(n);
    }

    /** The playbook as text for the Opportunity a push creates: what was done and what is left. */
    public static String pushText(NXP_Gov_Notice__c n) {
        Plan p = planFor(n);
        if (p == null) {
            return null;
        }
        List<String> lines = new List<String>{ 'Nexus playbook: ' + p.label };
        for (Step s : p.steps) {
            String mark = s.done ? '[x] ' : '[ ] ';
            String who = s.done
                ? ' (' +
                  (s.doneBy == null ? '' : s.doneBy + ', ') +
                  (s.doneOn == null ? '' : s.doneOn.format('MMM d')) +
                  ')'
                : (s.due == null
                      ? ''
                      : ' (due ' + Datetime.newInstance(s.due, Time.newInstance(12, 0, 0, 0)).format('MMM d') + ')');
            lines.add(mark + s.text + who);
        }
        return String.join(lines, '\n');
    }

    public class PlaybookException extends Exception {
    }
}
