/**
 * Agent action (Market Intel): awards expiring in the next N months, filtered by agency text and NAICS.
 */
public with sharing class NXP_RecompeteQueryAction {
    public class Request {
        @InvocableVariable(label='Agency' description='Agency name or part of it, e.g. Veterans Affairs')
        public String agency;
        @InvocableVariable(label='NAICS' description='NAICS code or prefix ending in *')
        public String naics;
        @InvocableVariable(label='Months ahead' description='Default 18')
        public Integer monthsAhead;
        @InvocableVariable(label='Minimum value')
        public Decimal minValue;
    }

    public class Response {
        @InvocableVariable(label='Recompetes')
        public String recompetes;
    }

    @InvocableMethod(
        label='NXP Recompete Query'
        description='Lists contract awards expiring soon (recompete candidates) from award data.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Integer months = r.monthsAhead == null ? 18 : r.monthsAhead;
            Date today = Date.today();
            Date until = today.addMonths(months);
            String agencyLike = String.isBlank(r.agency) ? '%' : '%' + r.agency.trim() + '%';
            String naicsLike = String.isBlank(r.naics) ? '%' : r.naics.trim().removeEnd('*') + '%';
            Decimal minValue = r.minValue == null ? 0 : r.minValue;
            List<String> lines = new List<String>();
            for (NXP_Award_Summary__c a : [
                SELECT
                    PIID__c,
                    Name,
                    Agency__r.Full_Path__c,
                    Vendor__r.Name,
                    Obligated_Amount__c,
                    Period_End__c,
                    NAICS_Code__c
                FROM NXP_Award_Summary__c
                WHERE
                    Period_End__c >= :today
                    AND Period_End__c <= :until
                    AND Agency__r.Full_Path__c LIKE :agencyLike
                    AND (NAICS_Code__c LIKE :naicsLike
                    OR NAICS_Code__c = NULL)
                    AND Obligated_Amount__c >= :minValue
                WITH USER_MODE
                ORDER BY Period_End__c ASC
                LIMIT 15
            ]) {
                lines.add(
                    '- ' +
                        a.PIID__c +
                        ' · ' +
                        a.Agency__r.Full_Path__c +
                        ' · ' +
                        (a.Vendor__r == null ? 'unknown vendor' : a.Vendor__r.Name) +
                        ' · $' +
                        (a.Obligated_Amount__c == null ? 'n/a' : a.Obligated_Amount__c.format()) +
                        ' · ends ' +
                        String.valueOf(a.Period_End__c)
                );
            }
            Response res = new Response();
            res.recompetes = lines.isEmpty()
                ? 'No awards match in the next ' + months + ' months (award data in Nexus Pursuit Hub).'
                : 'Awards ending in the next ' +
                  months +
                  ' months (award data in Nexus Pursuit Hub):\n' +
                  String.join(lines, '\n');
            out.add(res);
        }
        return out;
    }
}
