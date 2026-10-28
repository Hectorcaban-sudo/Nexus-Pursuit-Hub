/**
 * Helpers to read values out of untyped JSON (Map<String, Object>) by dotted path,
 * and to coerce them to Salesforce types. Paths support list indexes: a.b[0].c
 */
public inherited sharing class NXP_Json {
    public static Map<String, Object> toMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
    }

    public static List<Object> toList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    public static Object getPath(Object root, String path) {
        if (root == null || String.isBlank(path)) {
            return null;
        }
        Object current = root;
        for (String segment : path.split('\\.')) {
            if (current == null) {
                return null;
            }
            String key = segment;
            Integer index = null;
            if (segment.endsWith(']') && segment.contains('[')) {
                key = segment.substringBefore('[');
                index = Integer.valueOf(segment.substringBetween('[', ']'));
            }
            if (String.isNotBlank(key)) {
                current = toMap(current).get(key);
            }
            if (index != null) {
                List<Object> items = toList(current);
                current = index < items.size() ? items[index] : null;
            }
        }
        return current;
    }

    public static String getString(Object root, String path) {
        Object v = getPath(root, path);
        return v == null ? null : String.valueOf(v);
    }

    public static Object coerce(Object value, String transform) {
        if (value == null) {
            return null;
        }
        String t = String.isBlank(transform) ? 'None' : transform;
        String s = String.valueOf(value).trim();
        if (String.isBlank(s)) {
            return null;
        }
        switch on t {
            when 'Date' {
                return toDate(s);
            }
            when 'DateTime' {
                return toDateTime(s);
            }
            when 'Number' {
                return toDecimal(s);
            }
            when 'Upper' {
                return s.toUpperCase();
            }
            when 'Truncate' {
                return NXP_Text.truncate(s, 255);
            }
            when else {
                return value;
            }
        }
    }

    /** Accepts yyyy-MM-dd, yyyy-MM-ddTHH:mm..., and MM/dd/yyyy. */
    public static Date toDate(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        try {
            if (s.contains('/')) {
                List<String> p = s.trim().split('/');
                return Date.newInstance(Integer.valueOf(p[2].left(4)), Integer.valueOf(p[0]), Integer.valueOf(p[1]));
            }
            return Date.valueOf(s.trim().left(10));
        } catch (Exception e) {
            return null;
        }
    }

    /** Accepts ISO 8601 with Z or an offset (e.g. 2026-11-09T14:00:00-05:00) or a plain date. */
    public static Datetime toDateTime(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        String v = s.trim();
        try {
            if (v.length() <= 10) {
                Date d = toDate(v);
                return d == null ? null : Datetime.newInstanceGmt(d, Time.newInstance(0, 0, 0, 0));
            }
            if (!v.endsWith('Z') && !Pattern.matches('.*[+-]\\d{2}:?\\d{2}$', v)) {
                v = v + 'Z';
            }
            return (Datetime) JSON.deserialize('"' + v + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    public static Decimal toDecimal(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        try {
            return Decimal.valueOf(s.replaceAll('[^0-9.\\-]', ''));
        } catch (Exception e) {
            return null;
        }
    }
}
