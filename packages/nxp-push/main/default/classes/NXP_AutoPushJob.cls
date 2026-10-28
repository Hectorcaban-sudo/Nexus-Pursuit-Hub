/**
 * Pushes auto-push matches, grouped by saved-search owner, outside the platform event transaction.
 */
public without sharing class NXP_AutoPushJob implements Queueable {
    private final Map<Id, Set<Id>> noticesByOwner;

    public NXP_AutoPushJob(Map<Id, Set<Id>> noticesByOwner) {
        this.noticesByOwner = noticesByOwner;
    }

    public void execute(QueueableContext context) {
        for (Id ownerId : noticesByOwner.keySet()) {
            List<Id> ids = new List<Id>(noticesByOwner.get(ownerId));
            // 200 per push keeps one DML statement per chunk.
            for (Integer i = 0; i < ids.size(); i += 200) {
                List<Id> chunk = new List<Id>();
                for (Integer j = i; j < Math.min(i + 200, ids.size()); j++) {
                    chunk.add(ids[j]);
                }
                NXP_PushService.push(chunk, ownerId, NXP_PushService.MODE_AUTO, true);
            }
        }
    }
}
