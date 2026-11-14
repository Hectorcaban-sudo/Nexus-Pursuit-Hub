/**
 * Writes an AI analysis of one notice (Analyze this notice). Implemented by NXP_NoticeAnalysisAi in
 * nxp-agents and found with Type.forName, so this package doesn't depend on it.
 */
public interface NXP_NoticeAnalyzer {
    /** False when AI is off or the daily AI limit is used up. */
    Boolean isEnabled();
    /** The model's answer (JSON as asked in the question). Throws when the model can't answer. */
    String analyze(Id noticeId, String question, String facts);
}
