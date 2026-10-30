// Deploying the packages puts the shipped custom metadata values back (settings, fit rule weights).
// This saves again the last value each setting was given on the Settings tab, except the ones
// env-config sets on purpose (AI_Enabled, Org_Environment, feed switches). Safe to run again.
// Run as a user with the NXP_Admin permission set and Customize Application.
try {
    String jobId = NXP_SettingsController.reapplySettings();
    System.debug(
        jobId == null
            ? 'Settings tab: nothing to reapply.'
            : 'Settings tab: reapplying saved settings, deployment ' + jobId + '. Check Settings > Recent changes.'
    );
} catch (Exception e) {
    System.debug('Settings tab: could not reapply saved settings: ' + e.getMessage());
}
