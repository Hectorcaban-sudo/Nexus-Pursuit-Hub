// Moves the SAMPLE notices' posted and due dates so they are relative to today (posted 1-10 days
// ago, due 9-45 days from now). The CSV files carry fixed dates; without this the samples would
// look past due a few weeks after they were written. Safe to run again: the dates are set, not shifted.
// The Gov Notice trigger does not create versions or change events for this update.
Map<String, List<Integer>> offsets = new Map<String, List<Integer>>{
    // Notice Id   => { posted N days ago, due in N days }
    'SAMPLE-0001' => new List<Integer>{ 1, 12 },
    'SAMPLE-0002' => new List<Integer>{ 2, 34 },
    'SAMPLE-0003' => new List<Integer>{ 3, 21 },
    'SAMPLE-0004' => new List<Integer>{ 4, 9 },
    'SAMPLE-0005' => new List<Integer>{ 5, 18 },
    'SAMPLE-0006' => new List<Integer>{ 6, 40 },
    'SAMPLE-0007' => new List<Integer>{ 7, 15 },
    'SAMPLE-0008' => new List<Integer>{ 8, 45 },
    'SAMPLE-0009' => new List<Integer>{ 9, 25 },
    'SAMPLE-0010' => new List<Integer>{ 10, 30 }
};
List<NXP_Gov_Notice__c> notices = [
    SELECT Id, Notice_Id__c
    FROM NXP_Gov_Notice__c
    WHERE Notice_Id__c IN :offsets.keySet()
];
Date today = Date.today();
for (NXP_Gov_Notice__c n : notices) {
    List<Integer> o = offsets.get(n.Notice_Id__c);
    Date due = today.addDays(o[1]);
    n.Posted_Date__c = today.addDays(-o[0]);
    n.Response_Due__c = Datetime.newInstanceGmt(due.year(), due.month(), due.day(), 18, 0, 0);
}
update notices;
System.debug('Dates refreshed on ' + notices.size() + ' SAMPLE notices.');
