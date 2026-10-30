/**
 * All Gov Notice queries. Callers choose the access level: USER_MODE for anything a person
 * sees (LWC controllers, agent actions), SYSTEM_MODE for ingestion and background jobs.
 */
public inherited sharing class NXP_GovNoticeSelector {
    public static final String FIELDS =
        'Id, Name, Notice_Id__c, Solicitation_Number__c, Title__c, Notice_Type__c, Status__c, Market__c, ' +
        'Agency__c, Agency_Path__c, Office__c, NAICS_Code__c, PSC_Code__c, Set_Aside__c, Estimated_Value__c, ' +
        'Posted_Date__c, Response_Due__c, Archive_Date__c, Days_To_Respond__c, Place_Of_Performance__c, ' +
        'Description__c, Needs_Description__c, Notice_URL__c, Source_Feed__c, Source_Lineage__c, Contract_Vehicle__c, ' +
        'Contract_Vehicle__r.Vehicle_Code__c, Contract_Vehicle_Code__c, Push_Details__c, Forecast__c, Predecessor_Award__c, Incumbent__c, Incumbent__r.Name, ' +
        'Fit_Score__c, Fit_Breakdown__c, AI_Summary__c, AI_Summary_Status__c, Last_Change_Type__c, ' +
        'Last_Changed__c, Version_Count__c, Pushed__c, Pushed_Record_Id__c, Content_Hash__c, CreatedDate';

    private final AccessLevel access;

    public NXP_GovNoticeSelector(AccessLevel access) {
        this.access = access;
    }

    public List<NXP_Gov_Notice__c> byIds(Set<Id> ids) {
        return Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM NXP_Gov_Notice__c WHERE Id IN :ids',
            new Map<String, Object>{ 'ids' => ids },
            access
        );
    }

    public NXP_Gov_Notice__c byId(Id noticeId) {
        List<NXP_Gov_Notice__c> rows = byIds(new Set<Id>{ noticeId });
        return rows.isEmpty() ? null : rows[0];
    }

    public List<NXP_Gov_Notice__c> byNoticeIds(Set<String> noticeIds) {
        return Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM NXP_Gov_Notice__c WHERE Notice_Id__c IN :keys',
            new Map<String, Object>{ 'keys' => noticeIds },
            access
        );
    }

    public List<NXP_Gov_Notice__c> bySolicitationNumbers(Set<String> numbers) {
        return Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM NXP_Gov_Notice__c WHERE Solicitation_Number__c IN :nums',
            new Map<String, Object>{ 'nums' => numbers },
            access
        );
    }

    /** Runs a WHERE clause built by NXP_SearchQueryBuilder with its bind map. */
    public List<NXP_Gov_Notice__c> whereClause(
        String whereSoql,
        Map<String, Object> binds,
        String orderBy,
        Integer maxRows
    ) {
        String soql =
            'SELECT ' +
            FIELDS +
            ' FROM NXP_Gov_Notice__c' +
            (String.isBlank(whereSoql) ? '' : ' WHERE ' + whereSoql) +
            ' ORDER BY ' +
            (String.isBlank(orderBy) ? 'Posted_Date__c DESC NULLS LAST' : orderBy) +
            ' LIMIT ' +
            maxRows;
        return Database.queryWithBinds(soql, binds == null ? new Map<String, Object>() : binds, access);
    }
}
