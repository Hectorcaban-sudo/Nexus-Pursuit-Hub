/**
 * Where pushed notices go. NXP_OpportunityPushTarget is the only implementation that knows the
 * target object (configured in NXP_Push_Mapping__mdt), so moving to another object or org
 * touches one class or only configuration.
 */
public interface NXP_PushTarget {
    String targetObject();

    /** Mapped values shown in the push dialog before anything is created. */
    List<NXP_PushFieldPreview> preview(NXP_Gov_Notice__c notice);

    /** Existing target records for these notices (dedupe), keyed by notice Id. */
    Map<Id, SObject> findExisting(List<NXP_Gov_Notice__c> notices);

    /** Builds unsaved target records. ownerId may be null (running user). */
    List<SObject> build(List<NXP_Gov_Notice__c> notices, Id ownerId);

    /** Values to write to an already-pushed record after an amendment (Sync Behavior = Update). */
    Map<String, Object> syncValues(NXP_Gov_Notice__c notice, Set<String> changedNoticeFields);

    /** Labels of changed fields that should only alert the owner (Sync Behavior = Alert Only). */
    List<String> alertOnlyChanges(Set<String> changedNoticeFields);
}
