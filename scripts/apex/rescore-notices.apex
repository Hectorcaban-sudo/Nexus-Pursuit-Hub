// Re-scores active notices after a Company Profile or Fit Rule change (up to 10,000 per run).
// The Gov Notice trigger scores on update; touching a scored field is not needed, so score directly.
List<NXP_Gov_Notice__c> notices = Database.query('SELECT ' + NXP_GovNoticeSelector.FIELDS + ' FROM NXP_Gov_Notice__c WHERE Status__c = \'Active\' LIMIT 10000');
new NXP_FitScoreService().score(notices);
NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
update notices;
System.debug('Re-scored ' + notices.size() + ' notices.');
