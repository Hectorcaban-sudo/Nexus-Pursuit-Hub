/**
 * Push to TechnoMile: preview, duplicate check, create or link, document links, Push Log,
 * and post-push sync when the government amends a pushed notice.
 * Manual and agent pushes run in user mode (the user must be able to create the target record);
 * auto-push, retry and sync run in system mode as background jobs.
 */
public without sharing class NXP_PushService {
    public static final String MODE_MANUAL = 'Manual';
    public static final String MODE_AUTO = 'Auto';
    public static final String MODE_AGENT = 'Agent';
    public static final String MODE_SYNC = 'Sync';

    public class PushPreview {
        @AuraEnabled
        public Id noticeId;
        @AuraEnabled
        public String noticeTitle;
        @AuraEnabled
        public String targetObject;
        @AuraEnabled
        public List<NXP_PushFieldPreview> fields;
        @AuraEnabled
        public Boolean alreadyPushed = false;
        @AuraEnabled
        public Id existingRecordId;
        @AuraEnabled
        public String existingRecordName;
        @AuraEnabled
        public Integer documentCount = 0;
        @AuraEnabled
        public String token;
    }

    public class PushResult {
        @AuraEnabled
        public Id noticeId;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Id targetId;
        @AuraEnabled
        public String message;
    }

    @TestVisible
    private static NXP_PushTarget targetOverride;

    public static NXP_PushTarget target() {
        return targetOverride != null ? targetOverride : new NXP_TechnoMilePushTarget();
    }

    public static PushPreview preview(Id noticeId) {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            throw new IllegalArgumentException('Notice not found or not visible to you.');
        }
        NXP_PushTarget t = target();
        PushPreview p = new PushPreview();
        p.noticeId = n.Id;
        p.noticeTitle = n.Title__c == null ? n.Name : n.Title__c;
        p.targetObject = t.targetObject();
        p.fields = t.preview(n);
        p.alreadyPushed = String.isNotBlank(n.Pushed_Record_Id__c);
        if (p.alreadyPushed) {
            p.existingRecordId = n.Pushed_Record_Id__c;
        } else {
            SObject existing = t.findExisting(new List<NXP_Gov_Notice__c>{ n }).get(n.Id);
            if (existing != null) {
                p.existingRecordId = existing.Id;
                p.existingRecordName = String.valueOf(existing.get('Name'));
            }
        }
        p.documentCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :n.Id];
        p.token = NXP_PreviewToken.issue('push', String.valueOf(n.Id));
        return p;
    }

    /** Agent path: refuses to push unless Preview Push ran for this notice and user today. */
    public static PushResult pushWithToken(Id noticeId, String token, Id ownerId) {
        if (!NXP_PreviewToken.verify('push', String.valueOf(noticeId), token)) {
            PushResult r = new PushResult();
            r.noticeId = noticeId;
            r.status = 'Failed';
            r.message = 'Run Preview Push for this notice and confirm with the user before pushing.';
            return r;
        }
        return push(new List<Id>{ noticeId }, ownerId, MODE_AGENT, true)[0];
    }

    public static List<PushResult> push(List<Id> noticeIds, Id ownerId, String mode, Boolean includeDocuments) {
        Boolean asUser = mode == MODE_MANUAL || mode == MODE_AGENT;
        AccessLevel access = asUser ? AccessLevel.USER_MODE : AccessLevel.SYSTEM_MODE;
        List<NXP_Gov_Notice__c> notices = new NXP_GovNoticeSelector(access).byIds(new Set<Id>(noticeIds));
        Map<Id, PushResult> results = new Map<Id, PushResult>();
        List<NXP_Push_Log__c> logs = new List<NXP_Push_Log__c>();
        Map<Id, Id> pushedTargets = new Map<Id, Id>();
        Id pusher = ownerId == null ? UserInfo.getUserId() : ownerId;

        NXP_PushTarget t;
        try {
            t = target();
        } catch (Exception e) {
            for (NXP_Gov_Notice__c n : notices) {
                results.put(n.Id, result(n.Id, 'Failed', null, e.getMessage()));
                logs.add(log(n.Id, null, null, 'Failed', mode, pusher, e.getMessage()));
            }
            insert as system logs;
            return results.values();
        }

        List<NXP_Gov_Notice__c> toCreate = new List<NXP_Gov_Notice__c>();
        Map<Id, SObject> existing = t.findExisting(notices);
        for (NXP_Gov_Notice__c n : notices) {
            if (String.isNotBlank(n.Pushed_Record_Id__c)) {
                results.put(n.Id, result(n.Id, 'Linked Existing', n.Pushed_Record_Id__c, 'Already pushed.'));
            } else if (existing.containsKey(n.Id)) {
                Id targetId = existing.get(n.Id).Id;
                results.put(
                    n.Id,
                    result(
                        n.Id,
                        'Linked Existing',
                        targetId,
                        'Found an existing ' + t.targetObject() + ' record; linked instead of creating a duplicate.'
                    )
                );
                logs.add(log(n.Id, t.targetObject(), targetId, 'Linked Existing', mode, pusher, null));
                pushedTargets.put(n.Id, targetId);
            } else {
                toCreate.add(n);
            }
        }

        if (!toCreate.isEmpty()) {
            List<SObject> rows = new List<SObject>();
            List<NXP_Gov_Notice__c> built = new List<NXP_Gov_Notice__c>();
            for (NXP_Gov_Notice__c n : toCreate) {
                try {
                    rows.addAll(t.build(new List<NXP_Gov_Notice__c>{ n }, ownerId));
                    built.add(n);
                } catch (Exception e) {
                    results.put(n.Id, result(n.Id, 'Failed', null, e.getMessage()));
                    logs.add(
                        log(
                            n.Id,
                            t.targetObject(),
                            null,
                            mode == MODE_AUTO ? 'Retry Pending' : 'Failed',
                            mode,
                            pusher,
                            e.getMessage()
                        )
                    );
                }
            }
            Database.SaveResult[] saved = Database.insert(rows, false, access);
            for (Integer i = 0; i < saved.size(); i++) {
                NXP_Gov_Notice__c n = built[i];
                if (saved[i].isSuccess()) {
                    results.put(
                        n.Id,
                        result(n.Id, 'Success', saved[i].getId(), 'Created ' + t.targetObject() + ' record.')
                    );
                    logs.add(log(n.Id, t.targetObject(), saved[i].getId(), 'Success', mode, pusher, null));
                    pushedTargets.put(n.Id, saved[i].getId());
                } else {
                    String message = errorText(saved[i].getErrors());
                    results.put(n.Id, result(n.Id, 'Failed', null, message));
                    logs.add(
                        log(
                            n.Id,
                            t.targetObject(),
                            null,
                            mode == MODE_AUTO ? 'Retry Pending' : 'Failed',
                            mode,
                            pusher,
                            message
                        )
                    );
                }
            }
        }

        markPushed(pushedTargets, pusher);
        if (includeDocuments != false) {
            linkDocuments(pushedTargets);
        }
        if (!logs.isEmpty()) {
            insert as system logs;
        }
        NXP_Logger.flush();
        return results.values();
    }

    /** Applies Push Mapping sync rules to records pushed earlier when their notice is amended. */
    public static void syncAfterChange(Set<Id> noticeIds) {
        List<NXP_Gov_Notice__c> pushed = new List<NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byIds(noticeIds)) {
            if (String.isNotBlank(n.Pushed_Record_Id__c)) {
                pushed.add(n);
            }
        }
        if (pushed.isEmpty()) {
            return;
        }
        Set<Id> pushedIds = new Map<Id, NXP_Gov_Notice__c>(pushed).keySet();
        Map<Id, NXP_Notice_Version__c> latest = new Map<Id, NXP_Notice_Version__c>();
        for (NXP_Notice_Version__c v : [
            SELECT Gov_Notice__c, Version_Number__c, Changed_Fields__c, Diff_Summary__c, Change_Type__c
            FROM NXP_Notice_Version__c
            WHERE Gov_Notice__c IN :pushedIds
            ORDER BY Version_Number__c DESC
        ]) {
            if (!latest.containsKey(v.Gov_Notice__c)) {
                latest.put(v.Gov_Notice__c, v);
            }
        }
        NXP_PushTarget t = target();
        List<SObject> updates = new List<SObject>();
        List<FeedItem> posts = new List<FeedItem>();
        List<NXP_Push_Log__c> logs = new List<NXP_Push_Log__c>();
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(t.targetObject());
        for (NXP_Gov_Notice__c n : pushed) {
            NXP_Notice_Version__c v = latest.get(n.Id);
            if (v == null || v.Version_Number__c == 1) {
                continue;
            }
            Set<String> changed = new Set<String>(NXP_Text.splitList(v.Changed_Fields__c));
            Map<String, Object> values = t.syncValues(n, changed);
            Id targetId = n.Pushed_Record_Id__c;
            if (!values.isEmpty()) {
                SObject row = targetType.newSObject(targetId);
                for (String f : values.keySet()) {
                    row.put(f, values.get(f));
                }
                updates.add(row);
            }
            List<String> alertOnly = t.alertOnlyChanges(changed);
            String body =
                'Nexus Pursuit Hub: the government amended this notice (' +
                v.Change_Type__c +
                ').\n' +
                v.Diff_Summary__c;
            if (!alertOnly.isEmpty()) {
                body += '\nReview: ' + String.join(alertOnly, ', ') + ' (not changed automatically).';
            }
            posts.add(new FeedItem(ParentId = targetId, Body = NXP_Text.truncate(body, 10000)));
            logs.add(log(n.Id, t.targetObject(), targetId, 'Success', MODE_SYNC, null, NXP_Text.truncate(body, 32768)));
        }
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        try {
            // Feed tracking can be off on the target object; posting is best effort.
            Database.insert(posts, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            NXP_Logger.warn('NXP_PushService', 'Could not post sync updates to the feed: ' + e.getMessage());
        }
        notifyOwners(pushed, latest, t);
        insert as system logs;
        NXP_Logger.flush();
    }

    private static void notifyOwners(
        List<NXP_Gov_Notice__c> pushed,
        Map<Id, NXP_Notice_Version__c> latest,
        NXP_PushTarget t
    ) {
        Set<String> ids = new Set<String>();
        for (NXP_Gov_Notice__c n : pushed) {
            ids.add(n.Pushed_Record_Id__c);
        }
        if (!Schema.getGlobalDescribe().get(t.targetObject()).getDescribe().fields.getMap().containsKey('ownerid')) {
            return;
        }
        Map<Id, SObject> targets = new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT Id, OwnerId FROM ' + t.targetObject() + ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.SYSTEM_MODE
            )
        );
        for (NXP_Gov_Notice__c n : pushed) {
            SObject row = targets.get(n.Pushed_Record_Id__c);
            NXP_Notice_Version__c v = latest.get(n.Id);
            if (row != null && v != null && v.Version_Number__c > 1) {
                NXP_AlertService.notify(
                    (Id) row.get('OwnerId'),
                    'Pushed notice amended: ' + v.Change_Type__c,
                    NXP_AlertService.summaryLine(n),
                    row.Id
                );
            }
        }
    }

    private static void markPushed(Map<Id, Id> targets, Id pusher) {
        if (targets.isEmpty()) {
            return;
        }
        List<NXP_Gov_Notice__c> notices = new List<NXP_Gov_Notice__c>();
        for (Id noticeId : targets.keySet()) {
            notices.add(
                new NXP_Gov_Notice__c(Id = noticeId, Pushed__c = true, Pushed_Record_Id__c = targets.get(noticeId))
            );
        }
        NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
        Database.update(notices, false, AccessLevel.SYSTEM_MODE);
        NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');

        Set<Id> noticeIds = targets.keySet();
        List<NXP_Search_Match__c> matches = [
            SELECT Id
            FROM NXP_Search_Match__c
            WHERE Gov_Notice__c IN :noticeIds AND Saved_Search__r.OwnerId = :pusher AND User_Action__c != 'Pushed'
        ];
        for (NXP_Search_Match__c m : matches) {
            m.User_Action__c = 'Pushed';
        }
        Database.update(matches, false, AccessLevel.SYSTEM_MODE);
    }

    private static void linkDocuments(Map<Id, Id> targets) {
        if (targets.isEmpty()) {
            return;
        }
        Set<Id> noticeIds = targets.keySet();
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :noticeIds
        ]) {
            links.add(
                new ContentDocumentLink(
                    ContentDocumentId = l.ContentDocumentId,
                    LinkedEntityId = targets.get(l.LinkedEntityId),
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                )
            );
        }
        Database.insert(links, false, AccessLevel.SYSTEM_MODE);
    }

    private static PushResult result(Id noticeId, String status, Id targetId, String message) {
        PushResult r = new PushResult();
        r.noticeId = noticeId;
        r.status = status;
        r.targetId = targetId;
        r.message = message;
        return r;
    }

    private static NXP_Push_Log__c log(
        Id noticeId,
        String targetObject,
        Id targetId,
        String status,
        String mode,
        Id pusher,
        String error
    ) {
        return new NXP_Push_Log__c(
            Gov_Notice__c = noticeId,
            Target_Object__c = targetObject,
            Target_Record_Id__c = targetId,
            Status__c = status,
            Mode__c = mode,
            Pushed_By__c = pusher,
            Attempts__c = 1,
            Error__c = status == 'Success' || status == 'Linked Existing' ? null : NXP_Text.truncate(error, 32768),
            Payload__c = status == 'Success' && mode == MODE_SYNC ? error : null
        );
    }

    private static String errorText(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error e : errors) {
            parts.add(e.getMessage());
        }
        return String.join(parts, '; ');
    }
}
