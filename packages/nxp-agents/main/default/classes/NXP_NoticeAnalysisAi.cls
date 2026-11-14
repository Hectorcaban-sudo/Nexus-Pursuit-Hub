/** Analyze this notice: one call to the NXP_Notice_Analysis prompt template with the question and the facts. */
public with sharing class NXP_NoticeAnalysisAi implements NXP_NoticeAnalyzer {
    public Boolean isEnabled() {
        return NXP_AiService.isEnabled() && !NXP_AiService.limitReached();
    }

    public String analyze(Id noticeId, String question, String facts) {
        try {
            return NXP_AiService.generate(
                NXP_Settings.getString('Notice_Analysis_Template', 'NXP_Notice_Analysis'),
                new Map<String, Object>{
                    'Input:Notice' => noticeId,
                    'Input:Question' => question,
                    'Input:Facts' => facts
                }
            );
        } finally {
            NXP_AiService.flushUsage();
        }
    }
}
