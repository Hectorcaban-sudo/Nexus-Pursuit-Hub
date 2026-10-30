/**
 * Registers Files attached to Gov Notices for document analysis (NXP_DocumentService).
 * Bypass with NXP_Setting Bypass_NXP_DocumentService = true.
 */
trigger NXP_ContentDocumentLinkTrigger on ContentDocumentLink(after insert) {
    NXP_DocumentService.onLinksInserted(Trigger.new);
}
