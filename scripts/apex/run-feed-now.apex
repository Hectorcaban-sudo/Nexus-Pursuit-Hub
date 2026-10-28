// Starts one feed immediately. Change the feed name (an NXP_Feed_Config__mdt DeveloperName).
Id runId = NXP_FeedScheduler.runNow('SAM_Opportunities');
System.debug('Feed run started: ' + runId);
