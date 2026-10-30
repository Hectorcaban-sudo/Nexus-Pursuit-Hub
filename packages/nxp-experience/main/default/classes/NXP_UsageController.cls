/**
 * Records that the user opened a Nexus screen (NXP_UsageService), for the Adoption dashboard.
 */
public with sharing class NXP_UsageController {
    @AuraEnabled
    public static void logView(String screen) {
        NXP_UsageService.record(screen);
    }
}
