/**
 * Writes the AI summary of one notice on request (the notice page's Generate AI summary). Implemented
 * by NXP_NoticeSummaryAi in nxp-agents and found with Type.forName, so this package doesn't depend on it.
 */
public interface NXP_SummaryGenerator {
    /** False when AI is off or the daily AI limit is used up. */
    Boolean isEnabled();
    /** The summary text. Throws when the model can't write one. */
    String summarize(Id noticeId);
}
