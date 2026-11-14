// Read-only profile of the Opportunity history, to set up pursuit / bid / win prediction.
// Changes nothing. Prints lines starting with "NXP|".
// Run (PowerShell):
//   sf apex run --file scripts/apex/profile-opportunities.apex --target-org staging | Select-String "NXP\|"
// Counts are over all Opportunities you can see. Aggregate queries count every row they read, so
// with more than about 45,000 Opportunities set YEARS lower.
Integer YEARS = 6;
Date since = Date.today().addYears(-YEARS);

Map<String, Schema.SObjectField> oppFields = Schema.SObjectType.Opportunity.fields.getMap();
Map<String, Schema.SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();

// ---- totals
Integer total = [SELECT COUNT() FROM Opportunity WHERE CreatedDate >= :since];
System.debug('NXP|TOTAL|Opportunities created in the last ' + YEARS + ' years: ' + total);
for (AggregateResult r : [
    SELECT CALENDAR_YEAR(CreatedDate) y, COUNT(Id) n
    FROM Opportunity
    WHERE CreatedDate >= :since
    GROUP BY CALENDAR_YEAR(CreatedDate)
    ORDER BY CALENDAR_YEAR(CreatedDate)
]) {
    System.debug('NXP|YEAR|' + r.get('y') + '|' + r.get('n'));
}
for (RecordTypeInfo rt : Schema.SObjectType.Opportunity.getRecordTypeInfos()) {
    if (rt.isAvailable() && !rt.isMaster()) {
        System.debug('NXP|RECORDTYPE|' + rt.getDeveloperName() + '|' + rt.getName());
    }
}

// ---- stages now
for (AggregateResult r : [
    SELECT StageName s, COUNT(Id) n
    FROM Opportunity
    WHERE CreatedDate >= :since
    GROUP BY StageName
    ORDER BY COUNT(Id) DESC
]) {
    System.debug('NXP|STAGE_NOW|' + r.get('s') + '|' + r.get('n'));
}
for (Schema.PicklistEntry e : Opportunity.StageName.getDescribe().getPicklistValues()) {
    System.debug('NXP|STAGE_PICKLIST|' + e.getValue() + '|active=' + e.isActive());
}

// ---- furthest stage reached (stage history)
try {
    for (AggregateResult r : [
        SELECT StageName s, COUNT_DISTINCT(OpportunityId) n
        FROM OpportunityHistory
        WHERE CreatedDate >= :since
        GROUP BY StageName
    ]) {
        System.debug(
            'NXP|STAGE_EVER|' + r.get('s') + '|' + r.get('n') + ' opportunities were in this stage at some point'
        );
    }
} catch (Exception e) {
    System.debug('NXP|STAGE_EVER|not available: ' + e.getMessage());
}

// ---- Status field(s): any Opportunity field labelled like "Status"
List<String> statusFields = new List<String>();
for (String name : oppFields.keySet()) {
    Schema.DescribeFieldResult d = oppFields.get(name).getDescribe();
    if (d.getLabel().containsIgnoreCase('status') && d.isFilterable() && d.isGroupable()) {
        statusFields.add(d.getName());
        System.debug('NXP|STATUS_FIELD|' + d.getName() + '|label=' + d.getLabel() + '|type=' + d.getType());
    }
}
for (String f : statusFields) {
    for (
        AggregateResult r : Database.query(
            'SELECT ' +
                f +
                ' v, COUNT(Id) n FROM Opportunity WHERE CreatedDate >= :since GROUP BY ' +
                f +
                ' ORDER BY COUNT(Id) DESC LIMIT 30'
        )
    ) {
        System.debug('NXP|STATUS_VALUES|' + f + '|' + r.get('v') + '|' + r.get('n'));
    }
    // Status by stage: how phases and status combine (e.g. Phase 2B + Won / Lost / Pending).
    for (
        AggregateResult r : Database.query(
            'SELECT StageName s, ' +
                f +
                ' v, COUNT(Id) n FROM Opportunity WHERE CreatedDate >= :since GROUP BY StageName, ' +
                f +
                ' ORDER BY StageName LIMIT 200'
        )
    ) {
        System.debug('NXP|STAGE_X_STATUS|' + f + '|' + r.get('s') + '|' + r.get('v') + '|' + r.get('n'));
    }
}
for (AggregateResult r : [
    SELECT IsClosed c, IsWon w, COUNT(Id) n
    FROM Opportunity
    WHERE CreatedDate >= :since
    GROUP BY IsClosed, IsWon
]) {
    System.debug('NXP|CLOSED_WON|IsClosed=' + r.get('c') + '|IsWon=' + r.get('w') + '|' + r.get('n'));
}

// ---- candidate input fields on Opportunity: how often each is filled in
List<String> hints = new List<String>{
    'solicitation',
    'sol ',
    'naics',
    'psc',
    'set aside',
    'set-aside',
    'setaside',
    'vehicle',
    'contract type',
    'agency',
    'customer',
    'value',
    'amount',
    'price',
    'incumbent',
    'notice',
    'govwin',
    'sam',
    'competition',
    'pwin',
    'win',
    'loss',
    'reason',
    'no bid',
    'bid'
};
Map<String, String> candidates = new Map<String, String>();
for (String name : oppFields.keySet()) {
    Schema.DescribeFieldResult d = oppFields.get(name).getDescribe();
    String label = ' ' + d.getLabel().toLowerCase() + ' ';
    String api = d.getName().toLowerCase();
    for (String h : hints) {
        if (label.contains(h) || api.contains(h.trim().replace(' ', '_'))) {
            candidates.put(d.getName(), d.getLabel() + '|' + d.getType());
            break;
        }
    }
}
candidates.put('Amount', 'Amount|CURRENCY');
Integer checked = 0;
for (String f : candidates.keySet()) {
    if (++checked > 60) {
        System.debug('NXP|OPP_FIELD|… more candidate fields not counted (query limit)');
        break;
    }
    Schema.DescribeFieldResult d = oppFields.get(f.toLowerCase()).getDescribe();
    if (!d.isFilterable() || d.getType() == Schema.DisplayType.TEXTAREA) {
        System.debug('NXP|OPP_FIELD|' + f + '|' + candidates.get(f) + '|filled=? (long text, not countable)');
        continue;
    }
    Integer filled = Database.countQuery(
        'SELECT COUNT() FROM Opportunity WHERE CreatedDate >= :since AND ' + f + ' != null'
    );
    System.debug('NXP|OPP_FIELD|' + f + '|' + candidates.get(f) + '|filled=' + filled + ' of ' + total);
}

// ---- Account: where the agency lives
Integer withAccount = [SELECT COUNT() FROM Opportunity WHERE CreatedDate >= :since AND AccountId != NULL];
System.debug('NXP|ACCOUNT|Opportunities with an Account: ' + withAccount + ' of ' + total);
for (AggregateResult r : [
    SELECT Account.Name a, COUNT(Id) n
    FROM Opportunity
    WHERE CreatedDate >= :since AND AccountId != NULL
    GROUP BY Account.Name
    ORDER BY COUNT(Id) DESC
    LIMIT 25
]) {
    System.debug('NXP|ACCOUNT_TOP|' + r.get('a') + '|' + r.get('n'));
}
for (String name : accFields.keySet()) {
    Schema.DescribeFieldResult d = accFields.get(name).getDescribe();
    String label = d.getLabel().toLowerCase();
    if (
        label.contains('agency') ||
        label.contains('department') ||
        label.contains('parent') ||
        label.contains('naics') ||
        label.contains('type') ||
        label.contains('code') ||
        label.contains('sub')
    ) {
        System.debug('NXP|ACCOUNT_FIELD|' + d.getName() + '|' + d.getLabel() + '|' + d.getType());
    }
}
Integer accountsWithParent = [SELECT COUNT() FROM Account WHERE ParentId != NULL];
System.debug('NXP|ACCOUNT|Accounts with a parent account (agency hierarchy): ' + accountsWithParent);
Integer govAgencies = [SELECT COUNT() FROM NXP_Gov_Agency__c];
System.debug('NXP|ACCOUNT|Nexus Gov Agencies loaded (to match account names): ' + govAgencies);

// ---- link to Gov Notices by solicitation number (sample of 2,000)
for (String f : candidates.keySet()) {
    if (!f.containsIgnoreCase('sol') || !oppFields.get(f.toLowerCase()).getDescribe().isFilterable()) {
        continue;
    }
    Set<String> sols = new Set<String>();
    for (
        Opportunity o : Database.query(
            'SELECT ' +
                f +
                ' FROM Opportunity WHERE CreatedDate >= :since AND ' +
                f +
                ' != null ORDER BY CreatedDate DESC LIMIT 2000'
        )
    ) {
        sols.add(String.valueOf(o.get(f)).trim());
    }
    Integer matched = sols.isEmpty()
        ? 0
        : [SELECT COUNT() FROM NXP_Gov_Notice__c WHERE Solicitation_Number__c IN :sols];
    System.debug(
        'NXP|NOTICE_MATCH|' + f + '|' + matched + ' Gov Notices match ' + sols.size() + ' recent solicitation numbers'
    );
}
System.debug('NXP|DONE|Read-only: nothing was changed.');
