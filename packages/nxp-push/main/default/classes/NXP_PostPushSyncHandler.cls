/**
 * Keeps pushed TechnoMile records current: on each notice change event, applies the Push Mapping
 * sync rules (update, alert only) to records pushed earlier.
 */
public without sharing class NXP_PostPushSyncHandler {
    public static void handle(List<NXP_Gov_Notice_Changed__e> events) {
        Set<Id> changed = new Set<Id>();
        for (NXP_Gov_Notice_Changed__e e : events) {
            if (!e.Is_New__c && String.isNotBlank(e.Notice_Record_Id__c)) {
                changed.add(Id.valueOf(e.Notice_Record_Id__c));
            }
        }
        if (!changed.isEmpty()) {
            try {
                NXP_PushService.syncAfterChange(changed);
            } catch (Exception ex) {
                NXP_Logger.error('NXP_PostPushSyncHandler', 'Post-push sync failed', ex, null);
                NXP_Logger.flush();
            }
        }
    }
}
