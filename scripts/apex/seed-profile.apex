// Creates the SAMPLE company profile used for fit scoring, unless an active profile already exists.
// Run before the sample notices are loaded so they are scored as they are inserted.
Integer active = [SELECT COUNT() FROM NXP_Company_Profile__c WHERE Active__c = TRUE];
if (active > 0) {
    System.debug('An active Company Profile already exists; the sample profile was not created.');
} else {
    insert new NXP_Company_Profile__c(
        Name = 'Our company (sample)',
        Active__c = true,
        NAICS_Codes__c = '541512, 541519, 5415*',
        PSC_Codes__c = 'DA01, DJ01',
        Set_Asides__c = 'Small Business; 8(a)',
        Target_Agency_Codes__c = 'Homeland Security; Army; Veterans',
        Keywords__c = 'cyber, zero trust, identity, cloud, ICAM, SOC',
        Min_Value__c = 1000000,
        Max_Value__c = 100000000
    );
    System.debug('Sample Company Profile created.');
}
