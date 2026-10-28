/**
 * Reads NXP_Setting__mdt key/value records with typed accessors and defaults.
 * Tests can override values with setForTest().
 */
public inherited sharing class NXP_Settings {
    private static final Map<String, String> OVERRIDES = new Map<String, String>();

    @TestVisible
    private static void setForTest(String key, String value) {
        OVERRIDES.put(key, value);
    }

    public static String getString(String key, String defaultValue) {
        if (OVERRIDES.containsKey(key)) {
            return OVERRIDES.get(key);
        }
        NXP_Setting__mdt setting = NXP_Setting__mdt.getInstance(key);
        return setting == null || String.isBlank(setting.Value__c) ? defaultValue : setting.Value__c;
    }

    public static Integer getInteger(String key, Integer defaultValue) {
        String value = getString(key, null);
        try {
            return value == null ? defaultValue : Integer.valueOf(value.trim());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public static Decimal getDecimal(String key, Decimal defaultValue) {
        String value = getString(key, null);
        try {
            return value == null ? defaultValue : Decimal.valueOf(value.trim());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public static Boolean getBoolean(String key, Boolean defaultValue) {
        String value = getString(key, null);
        return value == null ? defaultValue : value.trim().equalsIgnoreCase('true');
    }

    /** True when the named trigger handler or process is switched off for this org. */
    public static Boolean isBypassed(String name) {
        return getBoolean('Bypass_' + name, false);
    }
}
