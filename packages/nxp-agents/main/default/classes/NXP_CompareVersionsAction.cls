/**
 * Agent action (Notice Briefing): what changed in the latest amendments of a notice.
 */
public with sharing class NXP_CompareVersionsAction {
    public class Request {
        @InvocableVariable(label='Gov Notice record Id' required=true)
        public Id noticeId;
        @InvocableVariable(label='How many recent versions' description='Default 3')
        public Integer versions;
    }

    public class Response {
        @InvocableVariable(label='Changes')
        public String changes;
    }

    @InvocableMethod(
        label='NXP Compare Versions'
        description='Lists what changed in the most recent amendments of a notice.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Integer n = r.versions == null ? 3 : Math.min(r.versions, 10);
            List<String> lines = new List<String>();
            for (NXP_Notice_Version__c v : [
                SELECT Version_Number__c, Change_Type__c, Diff_Summary__c, AI_Change_Summary__c, CreatedDate
                FROM NXP_Notice_Version__c
                WHERE Gov_Notice__c = :r.noticeId
                WITH USER_MODE
                ORDER BY Version_Number__c DESC
                LIMIT :n
            ]) {
                String label = v.Version_Number__c == 1 ? 'Original' : 'Amendment ' + (v.Version_Number__c - 1);
                lines.add(
                    label +
                        ' (' +
                        v.CreatedDate.format('MMM d, yyyy') +
                        ', ' +
                        v.Change_Type__c +
                        '):\n' +
                        (String.isNotBlank(v.AI_Change_Summary__c) ? v.AI_Change_Summary__c : v.Diff_Summary__c)
                );
            }
            Response res = new Response();
            res.changes = lines.isEmpty() ? 'No versions found for this notice.' : String.join(lines, '\n\n');
            out.add(res);
        }
        return out;
    }
}
