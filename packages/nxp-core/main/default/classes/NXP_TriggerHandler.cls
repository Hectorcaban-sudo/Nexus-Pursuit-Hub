/**
 * Base trigger handler. One trigger per object calls new XxxHandler().run().
 * Handlers can be bypassed in code (bypass/clearBypass) or per org with an
 * NXP_Setting__mdt record named Bypass_<HandlerName> = true.
 */
public virtual inherited sharing class NXP_TriggerHandler {
    private static final Set<String> BYPASSED = new Set<String>();

    public static void bypass(String handlerName) {
        BYPASSED.add(handlerName);
    }

    public static void clearBypass(String handlerName) {
        BYPASSED.remove(handlerName);
    }

    public static Boolean isBypassed(String handlerName) {
        return BYPASSED.contains(handlerName) || NXP_Settings.isBypassed(handlerName);
    }

    protected virtual String handlerName() {
        return String.valueOf(this).substringBefore(':');
    }

    public void run() {
        if (!Trigger.isExecuting || isBypassed(handlerName())) {
            return;
        }
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                beforeInsert(Trigger.new);
            }
            when BEFORE_UPDATE {
                beforeUpdate(Trigger.new, Trigger.oldMap);
            }
            when AFTER_INSERT {
                afterInsert(Trigger.new);
            }
            when AFTER_UPDATE {
                afterUpdate(Trigger.new, Trigger.oldMap);
            }
            when BEFORE_DELETE {
                beforeDelete(Trigger.old);
            }
            when AFTER_DELETE {
                afterDelete(Trigger.old);
            }
            when else {
                return;
            }
        }
    }

    protected virtual void beforeInsert(List<SObject> newRecords) {
    }
    protected virtual void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
    }
    protected virtual void afterInsert(List<SObject> newRecords) {
    }
    protected virtual void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
    }
    protected virtual void beforeDelete(List<SObject> oldRecords) {
    }
    protected virtual void afterDelete(List<SObject> oldRecords) {
    }
}
