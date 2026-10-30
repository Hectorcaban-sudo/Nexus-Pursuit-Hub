/**
 * Adoption log: one NXP_Usage__c row per user per week they open a Nexus screen, counting views
 * and the screens used. Feeds the Adoption dashboard. Only the screen name is kept, never what the
 * user looked at. Writes in system mode so users need no access to the object; never throws.
 */
public without sharing class NXP_UsageService {
    public static final Set<String> SCREENS = new Set<String>{
        'Match Inbox',
        'My Searches',
        'Notice',
        'Forecasts',
        'Recompetes',
        'Vendor',
        'Agency',
        'Vehicle Portfolio',
        'Feed Console',
        'Inbound Emails'
    };

    public static void record(String screen) {
        if (!SCREENS.contains(screen)) {
            return;
        }
        try {
            Id me = UserInfo.getUserId();
            Date week = Date.today().toStartOfWeek();
            String key = String.valueOf(me).left(18) + ':' + String.valueOf(week);
            List<NXP_Usage__c> rows = [
                SELECT Id, Views__c, Screens__c
                FROM NXP_Usage__c
                WHERE Usage_Key__c = :key
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                Database.insert(
                    new NXP_Usage__c(
                        User__c = me,
                        OwnerId = me,
                        Week__c = week,
                        Usage_Key__c = key,
                        Views__c = 1,
                        Screens__c = screen,
                        Last_Screen__c = screen
                    ),
                    false // a parallel first view already inserted this week's row
                );
                return;
            }
            NXP_Usage__c u = rows[0];
            u.Views__c = (u.Views__c == null ? 0 : u.Views__c) + 1;
            Set<String> seen = new Set<String>(NXP_Text.splitList(u.Screens__c));
            if (!seen.contains(screen)) {
                u.Screens__c = NXP_Text.truncate(
                    String.isBlank(u.Screens__c) ? screen : u.Screens__c + ', ' + screen,
                    255
                );
            }
            u.Last_Screen__c = screen;
            update u;
        } catch (Exception e) {
            // Usage is best effort; it must never break a screen.
            System.debug(LoggingLevel.WARN, 'Usage not recorded: ' + e.getMessage());
        }
    }
}
