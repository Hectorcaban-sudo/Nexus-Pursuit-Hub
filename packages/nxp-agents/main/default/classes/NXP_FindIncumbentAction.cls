/**
 * Agent action (Market Intel): incumbent and predecessor award for a notice. Uses the linked
 * predecessor award when known; otherwise awards at the same agency and NAICS ending within a year.
 */
public with sharing class NXP_FindIncumbentAction {
    public class Request {
        @InvocableVariable(label='Gov Notice record Id' required=true)
        public Id noticeId;
    }

    public class Response {
        @InvocableVariable(label='Answer')
        public String answer;
    }

    @InvocableMethod(
        label='NXP Find Incumbent'
        description='Finds the incumbent vendor and predecessor award for a notice from award data.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        NXP_GovNoticeSelector selector = new NXP_GovNoticeSelector(AccessLevel.USER_MODE);
        for (Request r : requests) {
            Response res = new Response();
            NXP_Gov_Notice__c n = selector.byId(r.noticeId);
            if (n == null) {
                res.answer = 'Notice not found or not visible to you.';
            } else if (n.Predecessor_Award__c != null) {
                NXP_Award_Summary__c a = [
                    SELECT PIID__c, Vendor__r.Name, Obligated_Amount__c, Period_End__c
                    FROM NXP_Award_Summary__c
                    WHERE Id = :n.Predecessor_Award__c
                    WITH USER_MODE
                ];
                res.answer =
                    'Predecessor award ' +
                    a.PIID__c +
                    ' held by ' +
                    (a.Vendor__r == null ? 'an unknown vendor' : a.Vendor__r.Name) +
                    ', ends ' +
                    String.valueOf(a.Period_End__c) +
                    '. Source: award data in Nexus Pursuit Hub.';
            } else {
                Date fromDate = Date.today().addMonths(-12);
                Date toDate = Date.today().addMonths(12);
                List<String> lines = new List<String>();
                for (NXP_Award_Summary__c a : [
                    SELECT PIID__c, Vendor__r.Name, Obligated_Amount__c, Period_End__c
                    FROM NXP_Award_Summary__c
                    WHERE
                        Agency__c = :n.Agency__c
                        AND NAICS_Code__c = :n.NAICS_Code__c
                        AND Period_End__c >= :fromDate
                        AND Period_End__c <= :toDate
                    WITH USER_MODE
                    ORDER BY Obligated_Amount__c DESC NULLS LAST
                    LIMIT 5
                ]) {
                    lines.add(
                        '- ' +
                            a.PIID__c +
                            ' · ' +
                            (a.Vendor__r == null ? 'unknown vendor' : a.Vendor__r.Name) +
                            ' · ends ' +
                            String.valueOf(a.Period_End__c)
                    );
                }
                res.answer = lines.isEmpty()
                    ? 'No predecessor award is linked and no awards at this agency and NAICS end within a year (award data window: last 12 to next 12 months).'
                    : 'No predecessor is linked. Likely candidates (same agency and NAICS, ending within a year):\n' +
                      String.join(lines, '\n');
            }
            out.add(res);
        }
        return out;
    }
}
