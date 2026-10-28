/**
 * Turns the structured, indexable parts of NXP_SearchCriteria into a SOQL WHERE clause with binds,
 * so previews and back-tests read a narrow slice; text filters (agency, set-aside, keywords)
 * are then applied in Apex by NXP_SearchCriteria.matches().
 */
public inherited sharing class NXP_SearchQueryBuilder {
    public String whereClause;
    public Map<String, Object> binds = new Map<String, Object>();

    /** forBacktest ignores status and due-date filters, which describe today, not history. */
    public NXP_SearchQueryBuilder(NXP_SearchCriteria c, Boolean forBacktest, Integer postedWithinDays) {
        List<String> clauses = new List<String>();
        if (!forBacktest) {
            clauses.add('Status__c IN :statuses');
            binds.put('statuses', c.effectiveStatuses());
            if (c.dueWithinDays != null) {
                clauses.add('Response_Due__c >= :now AND Response_Due__c <= :dueLimit');
                binds.put('now', Datetime.now());
                binds.put('dueLimit', Datetime.now().addDays(c.dueWithinDays));
            }
        }
        if (notEmpty(c.noticeTypes)) {
            clauses.add('Notice_Type__c IN :types');
            binds.put('types', c.noticeTypes);
        }
        if (notEmpty(c.markets)) {
            clauses.add('Market__c IN :markets');
            binds.put('markets', c.markets);
        }
        if (notEmpty(c.sources)) {
            clauses.add('Source_Feed__c IN :sources');
            binds.put('sources', c.sources);
        }
        addCodes(clauses, 'NAICS_Code__c', 'naics', c.naics);
        addCodes(clauses, 'PSC_Code__c', 'psc', c.psc);
        if (c.minFit != null) {
            clauses.add('Fit_Score__c >= :minFit');
            binds.put('minFit', c.minFit);
        }
        Boolean unknownOk = c.includeUnknownValue != false;
        if (c.minValue != null) {
            clauses.add('(Estimated_Value__c >= :minValue' + (unknownOk ? ' OR Estimated_Value__c = NULL)' : ')'));
            binds.put('minValue', c.minValue);
        }
        if (c.maxValue != null) {
            clauses.add('(Estimated_Value__c <= :maxValue' + (unknownOk ? ' OR Estimated_Value__c = NULL)' : ')'));
            binds.put('maxValue', c.maxValue);
        }
        Integer posted = postedWithinDays != null ? postedWithinDays : c.postedWithinDays;
        if (posted != null) {
            clauses.add('Posted_Date__c >= :postedFrom');
            binds.put('postedFrom', Date.today().addDays(-posted));
        }
        whereClause = String.join(clauses, ' AND ');
    }

    private void addCodes(List<String> clauses, String field, String bindPrefix, List<String> codes) {
        if (!notEmpty(codes)) {
            return;
        }
        List<String> exact = new List<String>();
        List<String> ors = new List<String>();
        Integer i = 0;
        for (String code : codes) {
            String c = code.trim().toUpperCase();
            if (c.endsWith('*')) {
                String name = bindPrefix + 'P' + i++;
                ors.add(field + ' LIKE :' + name);
                binds.put(name, c.removeEnd('*') + '%');
            } else {
                exact.add(c);
            }
        }
        if (!exact.isEmpty()) {
            ors.add(field + ' IN :' + bindPrefix + 'Exact');
            binds.put(bindPrefix + 'Exact', exact);
        }
        clauses.add('(' + String.join(ors, ' OR ') + ')');
    }

    private static Boolean notEmpty(List<String> values) {
        return values != null && !values.isEmpty();
    }
}
