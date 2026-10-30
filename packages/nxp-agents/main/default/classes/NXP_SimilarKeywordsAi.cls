/**
 * AI step for Find similar (found by name by NXP_SimilarSearchService in nxp-search). Calls the
 * NXP_Similar_Keywords prompt template (name from the Similar_Keywords_Template setting) with the
 * notice and returns its keyword expression. The caller checks it parses before using it; the model
 * can't save or change anything.
 */
public without sharing class NXP_SimilarKeywordsAi implements NXP_KeywordSuggester {
    public Boolean isEnabled() {
        return NXP_AiService.isEnabled() && !NXP_AiService.limitReached();
    }

    public String suggest(Id noticeId) {
        try {
            return NXP_AiService.generate(
                NXP_Settings.getString('Similar_Keywords_Template', 'NXP_Similar_Keywords'),
                new Map<String, Object>{ 'Input:Notice' => noticeId }
            );
        } finally {
            NXP_AiService.flushUsage();
        }
    }
}
