/**
 * Analyses tab (nxpAnalysisLibrary): the analysis playbook library and editor.
 * See NXP_AnalysisPlaybookService. Running a published playbook on a notice goes through
 * NXP_NoticeController.analyzeNotice with the key "pb:<Key__c>".
 */
public with sharing class NXP_AnalysisPlaybookController {
    public class Library {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<NXP_AnalysisPlaybookService.Definition> playbooks;
        @AuraEnabled
        public List<NXP_NoticeAnalysisService.Kind> defaults;
        @AuraEnabled
        public List<String> sources;
        @AuraEnabled
        public Integer maxSteps;
    }

    @AuraEnabled
    public static Library getLibrary() {
        try {
            Library l = new Library();
            l.canEdit = NXP_AnalysisPlaybookService.canEdit();
            l.playbooks = NXP_AnalysisPlaybookService.library();
            l.defaults = NXP_NoticeAnalysisService.defaultKinds();
            l.sources = NXP_AnalysisPlaybookService.SOURCES;
            l.maxSteps = NXP_AnalysisPlaybookService.MAX_STEPS;
            return l;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static List<NXP_AnalysisPlaybookService.VersionNote> getVersions(Id playbookId) {
        try {
            return NXP_AnalysisPlaybookService.versions(playbookId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Saves the playbook on screen (JSON of a Definition); publish = true publishes a new version. */
    @AuraEnabled
    public static NXP_AnalysisPlaybookService.Definition savePlaybook(
        String definitionJson,
        Boolean publish,
        String changeNote
    ) {
        try {
            return NXP_AnalysisPlaybookService.save(parse(definitionJson), publish == true, changeNote);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Draft (unpublish) or Retired. */
    @AuraEnabled
    public static NXP_AnalysisPlaybookService.Definition setStatus(Id playbookId, String status) {
        try {
            return NXP_AnalysisPlaybookService.setStatus(playbookId, status);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** A new draft from a Nexus analysis key (brief, swot, ...) or a playbook Id. */
    @AuraEnabled
    public static NXP_AnalysisPlaybookService.Definition copyPlaybook(String source) {
        try {
            return NXP_AnalysisPlaybookService.copy(source);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Runs the playbook on screen against a notice without saving it (one AI call). */
    @AuraEnabled
    public static NXP_NoticeAnalysisService.Analysis testPlaybook(Id noticeId, String definitionJson) {
        try {
            return NXP_AnalysisPlaybookService.testRun(noticeId, parse(definitionJson));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static NXP_AnalysisPlaybookService.Definition parse(String definitionJson) {
        if (String.isBlank(definitionJson)) {
            throw new NXP_AnalysisPlaybookService.PlaybookException('Nothing to save.');
        }
        return (NXP_AnalysisPlaybookService.Definition) JSON.deserialize(
            definitionJson,
            NXP_AnalysisPlaybookService.Definition.class
        );
    }

    private static AuraHandledException handled(Exception e) {
        String message = e instanceof NXP_AnalysisPlaybookService.PlaybookException ||
            e instanceof NXP_NoticeAnalysisService.AnalysisException
            ? e.getMessage()
            : (e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage());
        AuraHandledException a = new AuraHandledException(message);
        a.setMessage(message);
        return a;
    }
}
