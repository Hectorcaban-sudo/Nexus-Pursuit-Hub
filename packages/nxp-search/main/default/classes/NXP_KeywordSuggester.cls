/**
 * Optional AI step for Find similar: suggests keywords that describe what a notice is about.
 * Implemented in nxp-agents (NXP_SimilarKeywordsAi) and found by name, so nxp-search doesn't
 * depend on the AI package. The answer is untrusted: NXP_SimilarSearchService parses it as a
 * keyword expression and falls back to words from the title when it isn't valid.
 */
public interface NXP_KeywordSuggester {
    Boolean isEnabled();

    /** A keyword expression (AND, OR, NOT, "phrases", word*) for notices like this one. */
    String suggest(Id noticeId);
}
