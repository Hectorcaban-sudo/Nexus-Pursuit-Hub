/**
 * AI step for GSA eBuy e-mails (found by name by NXP_EbuyExtractJob in nxp-ingestion).
 * Calls the NXP_Ebuy_RFQ_Extract prompt template (name from the Ebuy_AI_Template setting) with the
 * Inbound Email record and, when given, one attached PDF. The template must answer with JSON only;
 * NXP_EbuyEmailParser.mergeAi checks every value before it is used. The model only fills in fields:
 * it cannot create, change or send anything.
 */
public without sharing class NXP_EbuyAiExtract implements NXP_EbuyAiExtractor {
    public Boolean isEnabled() {
        return NXP_AiService.isEnabled();
    }

    public String extract(Id emailId, Id attachmentDocumentId) {
        Map<String, Object> inputs = new Map<String, Object>{ 'Input:Email' => emailId };
        if (attachmentDocumentId != null) {
            inputs.put('Input:Attachment', attachmentDocumentId);
        }
        return NXP_AiService.generate(NXP_Settings.getString('Ebuy_AI_Template', 'NXP_Ebuy_RFQ_Extract'), inputs);
    }
}
