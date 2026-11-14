/**
 * Agent action (Market Intel): which vendors win the most in a NAICS (and optionally at an agency),
 * from the award data in Nexus. No AI.
 */
public with sharing class NXP_MarketLeadersAction {
    public class Request {
        @InvocableVariable(
            label='NAICS'
            description='A NAICS code, or a prefix ending in * such as 5415*. Required: ask the user if they did not give one.'
            required=true
        )
        public String naics;
        @InvocableVariable(
            label='Agency'
            description='Agency name or part of it, for example Homeland Security. Leave empty for all agencies.'
        )
        public String agency;
        @InvocableVariable(
            label='Years back'
            description='How many years of awards to count. Use the user\'s number; otherwise leave empty for 5.'
        )
        public Integer yearsBack;
    }

    public class Response {
        @InvocableVariable(
            label='Leaders'
            description='Up to 10 vendors, one per line, with their number of awards and total obligated dollars, and the data window used. Always repeat the data window. Do not add vendors that are not in it.'
        )
        public String leaders;
    }

    @InvocableMethod(
        label='NXP Market Leaders'
        description='Use when the user asks who wins most, who the main competitors are, or who holds the most work in a NAICS, optionally at one agency.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            Integer years = r.yearsBack == null || r.yearsBack < 1 ? 5 : r.yearsBack;
            Date since = Date.today().addYears(-years);
            String naicsLike = String.isBlank(r.naics) ? '%' : r.naics.trim().removeEnd('*') + '%';
            String agencyLike = String.isBlank(r.agency) ? '%' : '%' + r.agency.trim() + '%';
            List<String> lines = new List<String>();
            for (AggregateResult a : [
                SELECT Vendor__r.Name vendorName, COUNT(Id) awardCount, SUM(Obligated_Amount__c) obligated
                FROM NXP_Award_Summary__c
                WHERE
                    NAICS_Code__c LIKE :naicsLike
                    AND Agency__r.Full_Path__c LIKE :agencyLike
                    AND Vendor__c != NULL
                    AND Period_Start__c >= :since
                WITH USER_MODE
                GROUP BY Vendor__r.Name
                ORDER BY SUM(Obligated_Amount__c) DESC NULLS LAST
                LIMIT 10
            ]) {
                Decimal total = (Decimal) a.get('obligated');
                lines.add(
                    '- ' +
                        a.get('vendorName') +
                        ': ' +
                        a.get('awardCount') +
                        ' awards' +
                        (total == null ? '' : ', $' + total.setScale(0).format() + ' obligated')
                );
            }
            String window =
                'Data window: awards starting since ' +
                since.format() +
                ', NAICS ' +
                (String.isBlank(r.naics) ? 'any' : r.naics.trim()) +
                (String.isBlank(r.agency) ? '' : ', agency containing "' + r.agency.trim() + '"') +
                '. Source: award data in Nexus Pursuit Hub.';
            res.leaders = lines.isEmpty() ? 'No awards found. ' + window : String.join(lines, '\n') + '\n' + window;
            out.add(res);
        }
        return out;
    }
}
