/**
 * Small, dependency-free text and value helpers shared by every package.
 */
public inherited sharing class NXP_Text {
    public static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.left(maxLength);
    }

    /** Splits a comma, semicolon or newline separated list into trimmed, non-blank values. */
    public static List<String> splitList(String value) {
        List<String> result = new List<String>();
        if (String.isBlank(value)) {
            return result;
        }
        for (String part : value.split('[,;\\n]')) {
            if (String.isNotBlank(part)) {
                result.add(part.trim());
            }
        }
        return result;
    }

    public static Set<String> lowerSet(List<String> values) {
        Set<String> result = new Set<String>();
        if (values == null) {
            return result;
        }
        for (String v : values) {
            if (String.isNotBlank(v)) {
                result.add(v.trim().toLowerCase());
            }
        }
        return result;
    }

    /** True when code matches any pattern; a pattern ending in * matches a prefix. */
    public static Boolean matchesCodeList(String code, List<String> patterns) {
        if (String.isBlank(code) || patterns == null || patterns.isEmpty()) {
            return false;
        }
        String c = code.trim().toUpperCase();
        for (String p : patterns) {
            if (String.isBlank(p)) {
                continue;
            }
            String pattern = p.trim().toUpperCase();
            if (pattern.endsWith('*')) {
                if (c.startsWith(pattern.removeEnd('*'))) {
                    return true;
                }
            } else if (c == pattern) {
                return true;
            }
        }
        return false;
    }

    /** True when any of the terms appears (case-insensitive) in the text. */
    public static Boolean containsAny(String text, List<String> terms) {
        if (String.isBlank(text) || terms == null) {
            return false;
        }
        String lower = text.toLowerCase();
        for (String t : terms) {
            if (String.isNotBlank(t) && lower.contains(t.trim().toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    public static String sha256(String value) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value));
        return EncodingUtil.convertToHex(digest);
    }

    public static String valueToString(Object value) {
        if (value == null) {
            return '';
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        if (value instanceof Date) {
            return String.valueOf((Date) value);
        }
        if (value instanceof Decimal) {
            // 20000000 and 20000000.00 (as read back from a currency field) must compare equal.
            return ((Decimal) value).stripTrailingZeros().toPlainString();
        }
        return String.valueOf(value);
    }
}
