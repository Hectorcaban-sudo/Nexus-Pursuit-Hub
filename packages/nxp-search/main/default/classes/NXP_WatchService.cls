/**
 * Watching forecasts, awards and vendors (NXP_Follow__c rows with Forecast__c, Award__c or Vendor__c;
 * notices keep using Gov_Notice__c) and the alerts that watching produces:
 *   - a watched forecast is released: a new notice is linked to it (Notice.Forecast__c);
 *   - a possible follow-on to a watched award is posted: a new notice is linked to it as predecessor,
 *     or has the same agency and NAICS while the award ends within 18 months or ended in the last 12;
 *   - a watched vendor gets a new award.
 * The user-facing methods run in user mode. The alert methods run from the platform event subscriber
 * and the award trigger, so they read every watcher (without sharing) and never throw.
 */
public without sharing class NXP_WatchService {
    @TestVisible
    private static final Integer FOLLOW_ON_MONTHS_AHEAD = 18;
    @TestVisible
    private static final Integer FOLLOW_ON_MONTHS_BACK = 12;

    public static String key(Id userId, Id recordId) {
        return String.valueOf(userId) + '-' + String.valueOf(recordId);
    }

    /** Starts or stops watching a notice, forecast, award or vendor for the running user. */
    public static Boolean setWatch(Id recordId, Boolean watch) {
        if (recordId == null) {
            throw new IllegalArgumentException('Nothing to watch.');
        }
        String followKey = key(UserInfo.getUserId(), recordId);
        List<NXP_Follow__c> existing = [
            SELECT Id
            FROM NXP_Follow__c
            WHERE Follow_Key__c = :followKey
            WITH USER_MODE
        ];
        if (watch == true && existing.isEmpty()) {
            NXP_Follow__c f = new NXP_Follow__c(Follow_Key__c = followKey);
            SObjectType t = recordId.getSObjectType();
            if (t == NXP_Gov_Forecast__c.SObjectType) {
                f.Forecast__c = recordId;
            } else if (t == NXP_Award_Summary__c.SObjectType) {
                f.Award__c = recordId;
            } else if (t == NXP_Gov_Vendor__c.SObjectType) {
                f.Vendor__c = recordId;
            } else if (t == NXP_Gov_Notice__c.SObjectType) {
                f.Gov_Notice__c = recordId;
            } else {
                throw new IllegalArgumentException('Only notices, forecasts, awards and vendors can be watched.');
            }
            insert as user f;
        } else if (watch != true && !existing.isEmpty()) {
            delete as user existing;
        }
        return watch == true;
    }

    /** Which of these records the running user watches. */
    public static Set<Id> watchedByMe(Set<Id> recordIds) {
        Set<Id> out = new Set<Id>();
        if (recordIds == null || recordIds.isEmpty()) {
            return out;
        }
        Set<String> keys = new Set<String>();
        Map<String, Id> idByKey = new Map<String, Id>();
        for (Id recordId : recordIds) {
            String k = key(UserInfo.getUserId(), recordId);
            keys.add(k);
            idByKey.put(k, recordId);
        }
        for (NXP_Follow__c f : [
            SELECT Follow_Key__c
            FROM NXP_Follow__c
            WHERE Follow_Key__c IN :keys
            WITH USER_MODE
        ]) {
            out.add(idByKey.get(f.Follow_Key__c));
        }
        return out;
    }

    public static Integer countMyWatches(SObjectField lookupField) {
        Id me = UserInfo.getUserId();
        String field = lookupField.getDescribe().getName();
        return Database.countQueryWithBinds(
            'SELECT COUNT() FROM NXP_Follow__c WHERE OwnerId = :me AND ' + field + ' != NULL',
            new Map<String, Object>{ 'me' => me },
            AccessLevel.USER_MODE
        );
    }

    // ------------------------------------------------------------------------------------- alerts

    /** New notices: alert watchers of the forecast they came from and of awards they may follow on. */
    public static void noticesCreated(Set<Id> noticeIds) {
        try {
            if (noticeIds == null || noticeIds.isEmpty()) {
                return;
            }
            List<NXP_Gov_Notice__c> notices = [
                SELECT
                    Id,
                    Name,
                    Title__c,
                    Notice_Id__c,
                    Agency__c,
                    Agency_Path__c,
                    NAICS_Code__c,
                    Response_Due__c,
                    Fit_Score__c,
                    Forecast__c,
                    Forecast__r.Name,
                    Predecessor_Award__c
                FROM NXP_Gov_Notice__c
                WHERE Id IN :noticeIds
            ];
            alertForecastWatchers(notices);
            alertAwardWatchers(notices);
        } catch (Exception e) {
            NXP_Logger.warn('NXP_WatchService', 'Notice watch alerts failed: ' + e.getMessage());
            NXP_Logger.flush();
        }
    }

    /** New awards: alert watchers of the vendor that won them. */
    public static void awardsCreated(List<NXP_Award_Summary__c> awards) {
        try {
            Set<Id> vendorIds = new Set<Id>();
            for (NXP_Award_Summary__c a : awards) {
                if (a.Vendor__c != null) {
                    vendorIds.add(a.Vendor__c);
                }
            }
            if (vendorIds.isEmpty()) {
                return;
            }
            Map<Id, List<Id>> watchersByVendor = new Map<Id, List<Id>>();
            for (NXP_Follow__c f : [
                SELECT OwnerId, Vendor__c
                FROM NXP_Follow__c
                WHERE Vendor__c IN :vendorIds
                LIMIT 5000
            ]) {
                if (!watchersByVendor.containsKey(f.Vendor__c)) {
                    watchersByVendor.put(f.Vendor__c, new List<Id>());
                }
                watchersByVendor.get(f.Vendor__c).add(f.OwnerId);
            }
            if (watchersByVendor.isEmpty()) {
                return;
            }
            Map<Id, NXP_Gov_Vendor__c> vendors = new Map<Id, NXP_Gov_Vendor__c>(
                [SELECT Id, Name FROM NXP_Gov_Vendor__c WHERE Id IN :watchersByVendor.keySet()]
            );
            for (NXP_Award_Summary__c a : awards) {
                List<Id> owners = watchersByVendor.get(a.Vendor__c);
                if (owners == null) {
                    continue;
                }
                String vendorName = vendors.containsKey(a.Vendor__c)
                    ? vendors.get(a.Vendor__c).Name
                    : 'A watched vendor';
                String body =
                    (a.Name == null ? a.PIID__c : a.Name) +
                    (a.Obligated_Amount__c == null ? '' : ' · $' + a.Obligated_Amount__c.format()) +
                    (a.Period_End__c == null ? '' : ' · ends ' + a.Period_End__c.format());
                for (Id owner : owners) {
                    NXP_AlertService.notify(owner, 'Watched vendor won an award: ' + vendorName, body, a.Id);
                }
            }
        } catch (Exception e) {
            NXP_Logger.warn('NXP_WatchService', 'Vendor watch alerts failed: ' + e.getMessage());
            NXP_Logger.flush();
        }
    }

    private static void alertForecastWatchers(List<NXP_Gov_Notice__c> notices) {
        Map<Id, NXP_Gov_Notice__c> noticeByForecast = new Map<Id, NXP_Gov_Notice__c>();
        for (NXP_Gov_Notice__c n : notices) {
            if (n.Forecast__c != null) {
                noticeByForecast.put(n.Forecast__c, n);
            }
        }
        if (noticeByForecast.isEmpty()) {
            return;
        }
        for (NXP_Follow__c f : [
            SELECT OwnerId, Forecast__c
            FROM NXP_Follow__c
            WHERE Forecast__c IN :noticeByForecast.keySet()
            LIMIT 5000
        ]) {
            NXP_Gov_Notice__c n = noticeByForecast.get(f.Forecast__c);
            NXP_AlertService.notify(
                f.OwnerId,
                'Watched forecast released: ' + (n.Forecast__r == null ? '' : n.Forecast__r.Name),
                NXP_AlertService.summaryLine(n),
                n.Id
            );
        }
    }

    private static void alertAwardWatchers(List<NXP_Gov_Notice__c> notices) {
        Map<Id, List<Id>> watchersByAward = new Map<Id, List<Id>>();
        for (NXP_Follow__c f : [
            SELECT OwnerId, Award__c
            FROM NXP_Follow__c
            WHERE Award__c != NULL
            LIMIT 5000
        ]) {
            if (!watchersByAward.containsKey(f.Award__c)) {
                watchersByAward.put(f.Award__c, new List<Id>());
            }
            watchersByAward.get(f.Award__c).add(f.OwnerId);
        }
        if (watchersByAward.isEmpty()) {
            return;
        }
        List<NXP_Award_Summary__c> awards = [
            SELECT Id, Name, PIID__c, Agency__c, NAICS_Code__c, Period_End__c
            FROM NXP_Award_Summary__c
            WHERE Id IN :watchersByAward.keySet()
        ];
        for (NXP_Gov_Notice__c n : notices) {
            for (NXP_Award_Summary__c a : awards) {
                if (!isFollowOn(n, a)) {
                    continue;
                }
                for (Id owner : watchersByAward.get(a.Id)) {
                    NXP_AlertService.notify(
                        owner,
                        'Possible follow-on to watched award ' + (a.Name == null ? a.PIID__c : a.Name),
                        NXP_AlertService.summaryLine(n),
                        n.Id
                    );
                }
            }
        }
    }

    /** True when the notice names the award as predecessor, or looks like its follow-on. */
    public static Boolean isFollowOn(NXP_Gov_Notice__c n, NXP_Award_Summary__c a) {
        if (n.Predecessor_Award__c != null) {
            return n.Predecessor_Award__c == a.Id;
        }
        if (n.Agency__c == null || n.Agency__c != a.Agency__c) {
            return false;
        }
        if (String.isBlank(n.NAICS_Code__c) || n.NAICS_Code__c != a.NAICS_Code__c || a.Period_End__c == null) {
            return false;
        }
        Date today = Date.today();
        return a.Period_End__c >= today.addMonths(-FOLLOW_ON_MONTHS_BACK) &&
            a.Period_End__c <= today.addMonths(FOLLOW_ON_MONTHS_AHEAD);
    }
}
