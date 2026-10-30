// Sets the SAMPLE dates relative to today, so the samples never look stale: notices posted 1-10 days
// ago and due 9-45 days out; awards ending from 2 months ago to 20 months out (for Find Incumbent and
// Recompete Query); forecasts due from 10 days ago to 5 months out; vehicles expiring in 11 months to
// 4.5 years. Also links each forecast to the notice that points to it (the CSV load can't set both
// sides). Safe to run again: dates are set, not shifted. The Gov Notice trigger does not create
// versions or change events for this update.
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

// Awards: { months since start (negative), months until end (negative = already ended) }
Map<String, List<Integer>> awardMonths = new Map<String, List<Integer>>{
    'SAMPLE-PIID-0001' => new List<Integer>{ -54, 4 },
    'SAMPLE-PIID-0002' => new List<Integer>{ -40, 7 },
    'SAMPLE-PIID-0003' => new List<Integer>{ -48, 10 },
    'SAMPLE-PIID-0004' => new List<Integer>{ -50, 15 },
    'SAMPLE-PIID-0005' => new List<Integer>{ -36, 20 },
    'SAMPLE-PIID-0006' => new List<Integer>{ -60, -2 }
};
List<NXP_Award_Summary__c> awards = [
    SELECT Id, PIID__c
    FROM NXP_Award_Summary__c
    WHERE PIID__c IN :awardMonths.keySet()
];
for (NXP_Award_Summary__c a : awards) {
    List<Integer> m = awardMonths.get(a.PIID__c);
    a.Period_Start__c = today.addMonths(m[0]);
    a.Period_End__c = today.addMonths(m[1]);
}
update awards;

// Forecasts: days until the estimated solicitation date. Federal fiscal year starts on 1 October.
Map<String, Integer> forecastDays = new Map<String, Integer>{
    'SAMPLE-FC-0001' => -10,
    'SAMPLE-FC-0002' => 90,
    'SAMPLE-FC-0003' => 150
};
List<NXP_Gov_Forecast__c> forecasts = [
    SELECT Id, Forecast_Id__c
    FROM NXP_Gov_Forecast__c
    WHERE Forecast_Id__c IN :forecastDays.keySet()
];
Map<Id, NXP_Gov_Forecast__c> forecastById = new Map<Id, NXP_Gov_Forecast__c>(forecasts);
for (NXP_Gov_Forecast__c f : forecasts) {
    Date d = today.addDays(forecastDays.get(f.Forecast_Id__c));
    f.Estimated_Solicitation_Date__c = d;
    f.Fiscal_Year__c = 'FY' + (d.month() >= 10 ? d.year() + 1 : d.year());
}
for (NXP_Gov_Notice__c n : [
    SELECT Id, Forecast__c
    FROM NXP_Gov_Notice__c
    WHERE Notice_Id__c LIKE 'SAMPLE-%' AND Forecast__c IN :forecastById.keySet()
]) {
    forecastById.get(n.Forecast__c).Matched_Notice__c = n.Id;
}
update forecasts;
System.debug('Dates refreshed on ' + awards.size() + ' SAMPLE awards and ' + forecasts.size() + ' SAMPLE forecasts.');

// Contract vehicles: days until expiry (GSA MAS IT expires within 12 months, to show the warning).
Map<String, Integer> vehicleDays = new Map<String, Integer>{ 'OASIS+' => 1650, 'GSA-MAS-IT' => 330, 'CIO-SP4' => 1100 };
List<NXP_Contract_Vehicle__c> vehicles = [
    SELECT Id, Vehicle_Code__c
    FROM NXP_Contract_Vehicle__c
    WHERE Vehicle_Code__c IN :vehicleDays.keySet() AND Name LIKE '%(sample)'
];
for (NXP_Contract_Vehicle__c v : vehicles) {
    v.Expiry_Date__c = today.addDays(vehicleDays.get(v.Vehicle_Code__c));
}
update vehicles;
System.debug('Expiry dates refreshed on ' + vehicles.size() + ' SAMPLE contract vehicles.');

// GovWin sample alerts: alerted 2 to 9 days ago.
List<NXP_GovWin_Alert__c> govwin = [SELECT Id, GovWin_Id__c FROM NXP_GovWin_Alert__c WHERE GovWin_Id__c LIKE 'SAMPLE-GW-%'];
for (NXP_GovWin_Alert__c g : govwin) {
    g.Alert_Date__c = today.addDays(-2 - Integer.valueOf(g.GovWin_Id__c.right(1)));
}
update govwin;
