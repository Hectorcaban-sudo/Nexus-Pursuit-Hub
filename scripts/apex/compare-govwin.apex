// GovWin parallel run: compares every loaded GovWin alert with Nexus (notice by solicitation number,
// and whether a saved search matched it) and sets Result__c. Runs in the background; the Adoption
// dashboard shows the results. Run after loading a GovWin export (scripts/load-govwin-export).
Id jobId = Database.executeBatch(new NXP_GovWinCompareBatch(), 200);
System.debug('GovWin comparison queued: ' + jobId);
