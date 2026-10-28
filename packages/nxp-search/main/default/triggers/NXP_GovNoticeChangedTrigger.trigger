/**
 * Saved-search matching for every new or amended notice, whichever channel loaded it.
 */
trigger NXP_GovNoticeChangedTrigger on NXP_Gov_Notice_Changed__e(after insert) {
    NXP_SearchMatchService.handleEvents(Trigger.new);
}
