/**
 * Optional AI step for eBuy e-mails. NXP_EbuyExtractJob looks for an implementation named
 * NXP_EbuyAiExtract (nxp-agents package) and, when it exists and AI is on, merges its JSON into the
 * rule-based result. Ingestion does not depend on the agents package.
 */
public interface NXP_EbuyAiExtractor {
    /** True when AI calls are switched on in this org. */
    Boolean isEnabled();

    /**
     * Returns the template's JSON text for the e-mail record and up to one attached File
     * (ContentDocument Id, may be null).
     */
    String extract(Id emailId, Id attachmentDocumentId);
}
