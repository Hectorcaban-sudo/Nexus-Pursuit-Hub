/**
 * Reads a GSA eBuy RFQ notification e-mail with fixed rules: "Label: value" lines, the RFQ number
 * (RFQ + digits) from the subject or body, and the first ebuy.gsa.gov link. eBuy does not publish
 * its e-mail format, so the labels accepted for each field are listed in LABELS; add to them when a
 * real e-mail uses another wording.
 * Also checks AI output (NXP_Ebuy_RFQ_Extract) the same way: anything that does not pass is dropped.
 */
public inherited sharing class NXP_EbuyEmailParser {
    /** Field -> accepted labels (lower case, without the colon). */
    @TestVisible
    private static final Map<String, List<String>> LABELS = new Map<String, List<String>>{
        'rfqNumber' => new List<String>{ 'rfq id', 'rfq number', 'rfq #', 'rfq no', 'rfq' },
        'title' => new List<String>{ 'title', 'rfq title', 'requirement', 'requirement title' },
        'agency' => new List<String>{ 'buyer agency', 'agency', 'department', 'ordering agency' },
        'office' => new List<String>{ 'buyer office', 'office', 'ordering office', 'buying office', 'activity' },
        'sins' => new List<String>{ 'category / sin', 'category/sin', 'sin', 'sins', 'category', 'categories' },
        'naics' => new List<String>{ 'naics', 'naics code' },
        'setAside' => new List<String>{ 'set-aside', 'set aside', 'socioeconomic', 'small business set-aside' },
        'issueDate' => new List<String>{ 'issue date', 'issued', 'date issued', 'posted', 'posted date' },
        'responseDue' => new List<String>{
            'close date',
            'closing date',
            'response due',
            'quote due',
            'due date',
            'rfq close date'
        },
        'placeOfPerformance' => new List<String>{ 'place of performance', 'location' },
        'buyerName' => new List<String>{ 'buyer', 'buyer name', 'contracting officer', 'point of contact' },
        'buyerEmail' => new List<String>{ 'buyer email', 'email', 'contact email' }
    };

    private static final Pattern RFQ_PATTERN = Pattern.compile(
        '(?i)\\bRFQ\\s*(?:id|number|no\\.?|#)?\\s*[:#]?\\s*(\\d{5,9})\\b'
    );
    private static final Pattern URL_PATTERN = Pattern.compile('(?i)https://[^\\s<>"\']*ebuy\\.gsa\\.gov[^\\s<>"\']*');
    private static final Pattern NAICS_PATTERN = Pattern.compile('\\b(\\d{6})\\b');
    private static final Pattern DATE_PATTERN = Pattern.compile(
        '(?i)(\\d{1,2})/(\\d{1,2})/(\\d{4})(?:\\s+(\\d{1,2}):(\\d{2})\\s*(AM|PM)?)?\\s*(ET|EST|EDT|CT|CST|CDT|MT|MST|MDT|PT|PST|PDT)?'
    );
    private static final Pattern ISO_DATE = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');
    private static final Integer MAX_DESCRIPTION = 32000;

    public class Extracted {
        public String rfqNumber;
        public String title;
        public String agency;
        public String office;
        public List<String> sins = new List<String>();
        public String naics;
        public String setAside;
        public Date issueDate;
        public Datetime responseDue;
        public Boolean dueTimeAssumed = false;
        public String placeOfPerformance;
        public String buyerName;
        public String buyerEmail;
        public String url;
        public String description;
        public String summary;
        public List<String> evaluationFactors = new List<String>();
        /** What could not be read or was dropped, in plain words. */
        public List<String> notes = new List<String>();
    }

    // ------------------------------------------------------------------------------- rules

    public static Extracted parse(String subject, String body) {
        Extracted x = new Extracted();
        String text = body == null ? '' : body.replace('\r\n', '\n').replace('\r', '\n');
        Map<String, String> fields = labelledLines(text);

        x.rfqNumber = normalizeRfq(fields.get('rfqNumber'));
        if (x.rfqNumber == null) {
            x.rfqNumber = findRfq((subject == null ? '' : subject) + '\n' + text);
        }
        x.title = clean(fields.get('title'), 255);
        if (String.isBlank(x.title)) {
            x.title = titleFromSubject(subject);
        }
        x.agency = clean(fields.get('agency'), 255);
        x.office = clean(fields.get('office'), 255);
        if (fields.containsKey('sins')) {
            for (String s : fields.get('sins').split('[,;]')) {
                if (String.isNotBlank(s)) {
                    x.sins.add(clean(s, 120));
                }
            }
        }
        x.naics = checkNaics(fields.get('naics'), x);
        x.setAside = clean(fields.get('setAside'), 255);
        x.issueDate = toDate(fields.get('issueDate'));
        String due = fields.get('responseDue');
        x.responseDue = toDatetime(due);
        x.dueTimeAssumed = x.responseDue != null && !Pattern.compile('\\d{1,2}:\\d{2}').matcher(due).find();
        x.placeOfPerformance = clean(fields.get('placeOfPerformance'), 255);
        x.buyerName = clean(fields.get('buyerName'), 120);
        x.buyerEmail = checkEmail(fields.get('buyerEmail'));
        Matcher u = URL_PATTERN.matcher(text);
        x.url = u.find() ? u.group(0).left(255) : null;
        x.description = description(text);

        if (x.rfqNumber == null) {
            x.notes.add('No RFQ number (RFQ followed by digits) in the subject or body.');
        }
        if (String.isNotBlank(due) && x.responseDue == null) {
            x.notes.add('Close date "' + due.left(40) + '" could not be read.');
        }
        if (x.responseDue == null) {
            x.notes.add('No close date found.');
        }
        return x;
    }

    // ------------------------------------------------------------------------------- AI output

    /**
     * Fills gaps in the rule-based result from the AI JSON. Rules win where both have a value; the
     * RFQ number only ever comes from the rules. Values that fail a check are dropped with a note.
     */
    public static void mergeAi(Extracted x, String aiText) {
        Map<String, Object> ai;
        try {
            String raw = aiText == null ? '' : aiText.trim();
            if (raw.startsWith('```')) {
                raw = raw.substringAfter('\n').substringBeforeLast('```');
            }
            ai = (Map<String, Object>) JSON.deserializeUntyped(raw);
        } catch (Exception e) {
            x.notes.add('AI output was not a JSON object, so it was not used.');
            return;
        }
        String aiRfq = normalizeRfq(str(ai, 'rfqNumber'));
        if (aiRfq != null && x.rfqNumber != null && aiRfq != x.rfqNumber) {
            x.notes.add(
                'AI read RFQ number ' + aiRfq + ', the e-mail says ' + x.rfqNumber + '; kept ' + x.rfqNumber + '.'
            );
        }
        if (String.isBlank(x.title) || x.title == 'eBuy RFQ') {
            x.title = clean(str(ai, 'title'), 255);
        }
        x.agency = String.isBlank(x.agency) ? clean(str(ai, 'agency'), 255) : x.agency;
        x.office = String.isBlank(x.office) ? clean(str(ai, 'office'), 255) : x.office;
        if (x.sins.isEmpty()) {
            for (Object s : NXP_Json.toList(ai.get('sins'))) {
                if (s != null) {
                    x.sins.add(clean(String.valueOf(s), 120));
                }
            }
        }
        if (x.naics == null && String.isNotBlank(str(ai, 'naics'))) {
            x.naics = checkNaics(str(ai, 'naics'), x);
        }
        x.setAside = String.isBlank(x.setAside) ? clean(str(ai, 'setAside'), 255) : x.setAside;
        x.placeOfPerformance = String.isBlank(x.placeOfPerformance)
            ? clean(str(ai, 'placeOfPerformance'), 255)
            : x.placeOfPerformance;
        if (x.issueDate == null && String.isNotBlank(str(ai, 'issueDate'))) {
            x.issueDate = isoDate(str(ai, 'issueDate'));
        }
        if (x.responseDue == null && String.isNotBlank(str(ai, 'responseDue'))) {
            Datetime d = isoDatetime(str(ai, 'responseDue'));
            if (d == null) {
                x.notes.add('AI close date "' + str(ai, 'responseDue').left(40) + '" could not be read.');
            } else {
                x.responseDue = d;
                Integer i = x.notes.indexOf('No close date found.');
                if (i >= 0) {
                    x.notes.remove(i);
                }
                x.notes.add('Close date came from AI; check it against the RFQ.');
            }
        }
        x.summary = clean(str(ai, 'summary'), 4000);
        for (Object f : NXP_Json.toList(ai.get('evaluationFactors'))) {
            if (f != null && x.evaluationFactors.size() < 15) {
                x.evaluationFactors.add(clean(String.valueOf(f), 255));
            }
        }
    }

    // ------------------------------------------------------------------------------- helpers

    /** "Label: value" lines; the first line for each field wins. */
    private static Map<String, String> labelledLines(String text) {
        Map<String, String> fieldByLabel = new Map<String, String>();
        for (String field : LABELS.keySet()) {
            for (String label : LABELS.get(field)) {
                fieldByLabel.put(label, field);
            }
        }
        Map<String, String> out = new Map<String, String>();
        for (String line : text.split('\n')) {
            Integer colon = line.indexOf(':');
            if (colon <= 0 || colon > 40) {
                continue;
            }
            String label = line.left(colon).trim().toLowerCase().removeStart('*').removeEnd('*').trim();
            String value = line.substring(colon + 1).trim();
            String field = fieldByLabel.get(label);
            if (field != null && String.isNotBlank(value) && !out.containsKey(field)) {
                out.put(field, value);
            }
        }
        return out;
    }

    @TestVisible
    private static String normalizeRfq(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        Matcher m = Pattern.compile('(?i)^\\s*(?:RFQ\\s*#?\\s*)?(\\d{5,9})\\b').matcher(value);
        return m.find() ? 'RFQ' + m.group(1) : null;
    }

    private static String findRfq(String text) {
        Matcher m = RFQ_PATTERN.matcher(text);
        return m.find() ? 'RFQ' + m.group(1) : null;
    }

    @TestVisible
    private static String titleFromSubject(String subject) {
        String s = subject == null ? '' : subject;
        s = s.replaceAll('(?i)^\\s*((fw|fwd|re)\\s*:\\s*|\\[[^\\]]*\\]\\s*)+', '');
        s = s.replaceAll('(?i)\\bebuy\\b', '').replaceAll('(?i)\\bRFQ\\s*#?\\s*\\d{5,9}\\b', '');
        s = s.replaceAll('(?i)\\b(new|modified|request for quote|rfq)\\b\\s*', ' ');
        s = s.replaceAll('^[\\s:\\-–|]+', '').replaceAll('[\\s:\\-–|]+$', '').normalizeSpace();
        return String.isBlank(s) ? 'eBuy RFQ' : s.left(255);
    }

    private static String description(String text) {
        Integer start = text.toLowerCase().indexOf('description:');
        String d = start >= 0 ? text.substring(start + 'description:'.length()) : text;
        Integer link = d.indexOf('https://');
        if (start >= 0 && link > 0) {
            d = d.left(link);
        }
        return clean(d, MAX_DESCRIPTION, true);
    }

    private static String checkNaics(String value, Extracted x) {
        if (String.isBlank(value)) {
            return null;
        }
        Matcher m = NAICS_PATTERN.matcher(value);
        if (m.find()) {
            return m.group(1);
        }
        x.notes.add('NAICS "' + value.left(20) + '" is not a 6-digit code; left blank.');
        return null;
    }

    private static String checkEmail(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        Matcher m = Pattern.compile('[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}').matcher(value);
        return m.find() ? m.group(0).left(80) : null;
    }

    /** MM/DD/YYYY [hh:mm [AM|PM]] [zone]; no zone means Eastern, no time means 5:00 PM. */
    @TestVisible
    private static Datetime toDatetime(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        Matcher m = DATE_PATTERN.matcher(value);
        if (!m.find()) {
            return isoDatetime(value.trim());
        }
        Integer month = Integer.valueOf(m.group(1));
        Integer day = Integer.valueOf(m.group(2));
        Integer year = Integer.valueOf(m.group(3));
        if (month < 1 || month > 12 || day < 1 || day > 31) {
            return null;
        }
        Integer hour = 17;
        Integer minute = 0;
        if (m.group(4) != null) {
            hour = Integer.valueOf(m.group(4));
            minute = Integer.valueOf(m.group(5));
            String ampm = m.group(6) == null ? '' : m.group(6).toUpperCase();
            if (ampm == 'PM' && hour < 12) {
                hour += 12;
            } else if (ampm == 'AM' && hour == 12) {
                hour = 0;
            }
        }
        return inZone(year, month, day, hour, minute, zoneId(m.group(7)));
    }

    private static Date toDate(String value) {
        Datetime d = toDatetime(value);
        return d == null ? null : d.dateGmt();
    }

    private static Date isoDate(String value) {
        return value != null && ISO_DATE.matcher(value.trim()).matches() ? Date.valueOf(value.trim()) : null;
    }

    private static Datetime isoDatetime(String value) {
        if (value == null) {
            return null;
        }
        try {
            if (ISO_DATE.matcher(value).matches()) {
                Date d = Date.valueOf(value);
                return inZone(d.year(), d.month(), d.day(), 17, 0, 'America/New_York');
            }
            return NXP_Json.toDateTime(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static String zoneId(String abbreviation) {
        String a = abbreviation == null ? 'ET' : abbreviation.toUpperCase();
        if (a.startsWith('C')) {
            return 'America/Chicago';
        }
        if (a.startsWith('M')) {
            return 'America/Denver';
        }
        if (a.startsWith('P')) {
            return 'America/Los_Angeles';
        }
        return 'America/New_York';
    }

    private static Datetime inZone(
        Integer year,
        Integer month,
        Integer day,
        Integer hour,
        Integer minute,
        String zone
    ) {
        Datetime asGmt = Datetime.newInstanceGmt(year, month, day, hour, minute, 0);
        Integer offsetMs = TimeZone.getTimeZone(zone).getOffset(asGmt);
        return asGmt.addSeconds(-offsetMs / 1000);
    }

    private static String str(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v == null ? null : String.valueOf(v).trim();
    }

    private static String clean(String value, Integer maxLength) {
        return clean(value, maxLength, false);
    }

    /** Removes control characters; keeps line breaks only when asked. */
    private static String clean(String value, Integer maxLength, Boolean keepLines) {
        if (value == null) {
            return null;
        }
        String s = keepLines
            ? value.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]', '').replaceAll('\n{3,}', '\n\n').trim()
            : value.replaceAll('[\\x00-\\x1F\\x7F]', ' ').normalizeSpace();
        return String.isBlank(s) ? null : s.left(maxLength);
    }
}
