/**
 * Checks the JSON the NXP_Document_Analysis prompt template returns for one document. Only known
 * keys are kept; text is cleaned and shortened, lists are capped, dates must be ISO 8601. Then
 * compares the document with the notice and adds "checks" where they disagree (due date, NAICS,
 * set-aside), because a solicitation document is often more current than the notice text.
 * The document is untrusted: nothing here acts on its content, it only stores values.
 */
public inherited sharing class NXP_DocumentAnalysisParser {
    public class AnalysisException extends Exception {
    }

    private static final Map<String, Integer> TEXT_FIELDS = new Map<String, Integer>{
        'summary' => 1500,
        'documentType' => 40,
        'periodOfPerformance' => 255,
        'placeOfPerformance' => 255,
        'clearance' => 255,
        'contractType' => 120,
        'setAside' => 255,
        'naics' => 6
    };
    private static final Map<String, Integer> LIST_FIELDS = new Map<String, Integer>{
        'requirements' => 12,
        'deliverables' => 10,
        'evaluationFactors' => 10,
        'risks' => 8
    };
    private static final Set<String> DOCUMENT_TYPES = new Set<String>{
        'SOW',
        'PWS',
        'SOO',
        'RFP',
        'RFQ',
        'RFI',
        'Amendment',
        'Q&A',
        'Pricing',
        'Other'
    };

    /** Returns the checked fields; throws AnalysisException when the text is not a JSON object. */
    public static Map<String, Object> parse(String aiText, NXP_Gov_Notice__c notice) {
        Map<String, Object> raw;
        try {
            String text = aiText == null ? '' : aiText.trim();
            if (text.startsWith('```')) {
                text = text.substringAfter('\n').substringBeforeLast('```');
            }
            raw = (Map<String, Object>) JSON.deserializeUntyped(text);
        } catch (Exception e) {
            throw new AnalysisException('The model did not return a JSON object.');
        }
        Map<String, Object> out = new Map<String, Object>();
        for (String key : TEXT_FIELDS.keySet()) {
            String v = clean(raw.get(key), TEXT_FIELDS.get(key));
            if (v != null) {
                out.put(key, v);
            }
        }
        if (out.containsKey('documentType') && !DOCUMENT_TYPES.contains((String) out.get('documentType'))) {
            out.put('documentType', 'Other');
        }
        if (out.containsKey('naics') && !Pattern.matches('\\d{6}', (String) out.get('naics'))) {
            out.remove('naics');
        }
        for (String key : LIST_FIELDS.keySet()) {
            List<String> items = cleanList(raw.get(key), LIST_FIELDS.get(key));
            if (!items.isEmpty()) {
                out.put(key, items);
            }
        }

        List<Object> dates = new List<Object>();
        for (Object o : NXP_Json.toList(raw.get('keyDates'))) {
            if (!(o instanceof Map<String, Object>) || dates.size() >= 10) {
                continue;
            }
            Map<String, Object> m = (Map<String, Object>) o;
            String label = clean(m.get('label'), 120);
            String day = isoDate(m.get('date'));
            if (label != null && day != null) {
                dates.add(new Map<String, Object>{ 'label' => label, 'date' => day });
            }
        }
        if (!dates.isEmpty()) {
            out.put('keyDates', dates);
        }

        Map<String, Object> submission = new Map<String, Object>();
        if (raw.get('submission') instanceof Map<String, Object>) {
            Map<String, Object> s = (Map<String, Object>) raw.get('submission');
            putIf(submission, 'dueDate', isoDate(s.get('dueDate')));
            putIf(submission, 'questionsDue', isoDate(s.get('questionsDue')));
            putIf(submission, 'pageLimit', clean(s.get('pageLimit'), 255));
            putIf(submission, 'format', clean(s.get('format'), 255));
            putIf(submission, 'method', clean(s.get('method'), 255));
        }
        if (!submission.isEmpty()) {
            out.put('submission', submission);
        }

        List<String> checks = compare(out, notice);
        if (!checks.isEmpty()) {
            out.put('checks', checks);
        }
        return out;
    }

    /** Where the document and the notice disagree, in plain words. */
    @TestVisible
    private static List<String> compare(Map<String, Object> doc, NXP_Gov_Notice__c n) {
        List<String> checks = new List<String>();
        if (n == null) {
            return checks;
        }
        Map<String, Object> submission = (Map<String, Object>) doc.get('submission');
        String due = submission == null ? null : (String) submission.get('dueDate');
        if (due != null && n.Response_Due__c != null) {
            Date docDue = Date.valueOf(due.left(10));
            Date noticeDue = n.Response_Due__c.dateGmt();
            if (Math.abs(docDue.daysBetween(noticeDue)) > 1) {
                checks.add(
                    'The document says responses are due ' +
                        due.left(10) +
                        '; the notice says ' +
                        String.valueOf(noticeDue) +
                        '.'
                );
            }
        } else if (due != null && n.Response_Due__c == null) {
            checks.add('The notice has no due date; the document says ' + due.left(10) + '.');
        }
        String naics = (String) doc.get('naics');
        if (naics != null && String.isNotBlank(n.NAICS_Code__c) && naics != n.NAICS_Code__c) {
            checks.add('The document names NAICS ' + naics + '; the notice has ' + n.NAICS_Code__c + '.');
        }
        String setAside = (String) doc.get('setAside');
        if (setAside != null && String.isBlank(n.Set_Aside__c) && !setAside.containsIgnoreCase('none')) {
            checks.add('The document mentions a set-aside (' + setAside.left(80) + '); the notice has none.');
        }
        if (doc.containsKey('clearance') && !((String) doc.get('clearance')).containsIgnoreCase('none')) {
            checks.add('Clearance requirement: ' + ((String) doc.get('clearance')).left(120) + '.');
        }
        return checks;
    }

    private static void putIf(Map<String, Object> m, String key, Object value) {
        if (value != null) {
            m.put(key, value);
        }
    }

    /** YYYY-MM-DD, or YYYY-MM-DDThh:mm[:ss][Z|±hh:mm]; returned as given when valid. */
    private static String isoDate(Object value) {
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value).trim();
        if (!Pattern.matches('\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?(Z|[+-]\\d{2}:?\\d{2})?)?', s)) {
            return null;
        }
        try {
            Date.valueOf(s.left(10));
            return s;
        } catch (Exception e) {
            return null;
        }
    }

    private static String clean(Object value, Integer maxLength) {
        if (value == null || value instanceof Map<String, Object> || value instanceof List<Object>) {
            return null;
        }
        String s = String.valueOf(value).replaceAll('[\\x00-\\x1F\\x7F]', ' ').normalizeSpace();
        return String.isBlank(s) ? null : s.left(maxLength);
    }

    private static List<String> cleanList(Object value, Integer maxItems) {
        List<String> out = new List<String>();
        for (Object o : NXP_Json.toList(value)) {
            String s = clean(o, 400);
            if (s != null && out.size() < maxItems) {
                out.add(s);
            }
        }
        return out;
    }
}
