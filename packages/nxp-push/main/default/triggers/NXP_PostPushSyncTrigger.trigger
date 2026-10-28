/**
 * Post-push sync: amendments to notices already pushed to TechnoMile.
 */
trigger NXP_PostPushSyncTrigger on NXP_Gov_Notice_Changed__e(after insert) {
    NXP_PostPushSyncHandler.handle(Trigger.new);
}
