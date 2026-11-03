/** AI summary of one notice, on request from the notice page (same prompt template as the Notice Analyst). */
public with sharing class NXP_NoticeSummaryAi implements NXP_SummaryGenerator {
    public Boolean isEnabled() {
        return NXP_AiService.isEnabled() && !NXP_AiService.limitReached();
    }

    public String summarize(Id noticeId) {
        try {
            return NXP_AiService.generate(
                NXP_Settings.getString('AI_Summary_Template', 'NXP_Solicitation_Summary'),
                new Map<String, Object>{ 'Input:Notice' => noticeId }
            );
        } finally {
            NXP_AiService.flushUsage();
        }
    }
}
