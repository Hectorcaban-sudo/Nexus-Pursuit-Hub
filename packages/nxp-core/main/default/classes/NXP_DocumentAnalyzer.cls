/**
 * Runs document analyses in the background. The implementation, NXP_DocumentAnalysisJob, ships in
 * nxp-agents (it calls the AI service); NXP_DocumentService finds it by name, so the core package
 * does not depend on the agents package.
 */
public interface NXP_DocumentAnalyzer {
    /** True when AI and document analysis are both switched on. */
    Boolean isEnabled();

    /** Queues analysis of these NXP_Document_Analysis__c rows (Pending). */
    void enqueue(Set<Id> analysisIds);
}
