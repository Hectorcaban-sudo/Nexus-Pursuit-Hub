/**
 * Turns a buyer path ("HOMELAND SECURITY, DEPARTMENT OF.US CUSTOMS AND BORDER PROTECTION")
 * into NXP_Gov_Agency__c records, one per level, upserted on Agency_Code__c.
 * Uses the source's code path (070.7014) when it lines up with the names; otherwise a
 * stable key derived from the name path.
 */
public inherited sharing class NXP_AgencyResolver {
    private static final List<String> LEVELS = new List<String>{ 'Department', 'Agency', 'Sub-agency', 'Office' };

    public class Resolved {
        public Id agencyId;
        public String displayPath;
        public String leafName;
    }

    /** Keyed by "names|codes". */
    public static Map<String, Resolved> resolve(List<NXP_IngestRecord> records) {
        Map<String, Resolved> result = new Map<String, Resolved>();
        // level index -> code -> agency
        Map<Integer, Map<String, NXP_Gov_Agency__c>> byLevel = new Map<Integer, Map<String, NXP_Gov_Agency__c>>();
        Map<String, List<String>> keyChains = new Map<String, List<String>>();

        for (NXP_IngestRecord rec : records) {
            if (String.isBlank(rec.agencyPathNames)) {
                continue;
            }
            String pathKey = rec.agencyPathNames + '|' + (rec.agencyPathCodes == null ? '' : rec.agencyPathCodes);
            if (keyChains.containsKey(pathKey)) {
                continue;
            }
            List<String> names = splitNames(rec.agencyPathNames);
            List<String> codes = String.isBlank(rec.agencyPathCodes)
                ? new List<String>()
                : rec.agencyPathCodes.split('\\.');
            Boolean useCodes = codes.size() == names.size();
            List<String> chain = new List<String>();
            for (Integer i = 0; i < names.size(); i++) {
                String code = useCodes ? String.join(slice(codes, i + 1), '.') : nameKey(slice(names, i + 1));
                code = NXP_Text.truncate(code, 40);
                chain.add(code);
                if (!byLevel.containsKey(i)) {
                    byLevel.put(i, new Map<String, NXP_Gov_Agency__c>());
                }
                NXP_Gov_Agency__c a = new NXP_Gov_Agency__c(
                    Agency_Code__c = code,
                    Name = NXP_Text.truncate(titleCase(names[i]), 80),
                    Level__c = LEVELS[Math.min(i, LEVELS.size() - 1)],
                    Full_Path__c = NXP_Text.truncate(displayPath(slice(names, i + 1)), 255)
                );
                if (i > 0) {
                    a.Parent_Agency__r = new NXP_Gov_Agency__c(Agency_Code__c = chain[i - 1]);
                }
                byLevel.get(i).put(code, a);
            }
            keyChains.put(pathKey, chain);
        }

        Map<String, Id> idsByCode = new Map<String, Id>();
        List<Integer> levels = new List<Integer>(byLevel.keySet());
        levels.sort();
        for (Integer level : levels) {
            List<NXP_Gov_Agency__c> rows = byLevel.get(level).values();
            Database.upsert(rows, NXP_Gov_Agency__c.Agency_Code__c, false, AccessLevel.SYSTEM_MODE);
            for (NXP_Gov_Agency__c a : rows) {
                if (a.Id != null) {
                    idsByCode.put(a.Agency_Code__c, a.Id);
                }
            }
        }

        for (NXP_IngestRecord rec : records) {
            if (String.isBlank(rec.agencyPathNames)) {
                continue;
            }
            String pathKey = rec.agencyPathNames + '|' + (rec.agencyPathCodes == null ? '' : rec.agencyPathCodes);
            List<String> chain = keyChains.get(pathKey);
            List<String> names = splitNames(rec.agencyPathNames);
            Resolved r = new Resolved();
            r.agencyId = idsByCode.get(chain[chain.size() - 1]);
            r.displayPath = NXP_Text.truncate(displayPath(names), 255);
            r.leafName = titleCase(names[names.size() - 1]);
            result.put(pathKey, r);
        }
        return result;
    }

    public static String keyFor(NXP_IngestRecord rec) {
        return rec.agencyPathNames + '|' + (rec.agencyPathCodes == null ? '' : rec.agencyPathCodes);
    }

    @TestVisible
    private static List<String> splitNames(String path) {
        String separator = path.contains('›') ? '›' : path.contains('>') ? '>' : '.';
        List<String> names = new List<String>();
        for (String part : path.split(separator == '.' ? '\\.' : separator)) {
            if (String.isNotBlank(part)) {
                names.add(part.trim());
            }
        }
        return names;
    }

    private static List<String> slice(List<String> items, Integer count) {
        List<String> out = new List<String>();
        for (Integer i = 0; i < count && i < items.size(); i++) {
            out.add(items[i]);
        }
        return out;
    }

    private static String nameKey(List<String> names) {
        return 'N:' + NXP_Text.sha256(String.join(names, '>').toUpperCase()).left(38);
    }

    private static String displayPath(List<String> names) {
        List<String> pretty = new List<String>();
        for (String n : names) {
            pretty.add(titleCase(n));
        }
        return String.join(pretty, ' › ');
    }

    /** SAM.gov sends names in upper case; keep short acronyms (DHS, CBP) as they are. */
    @TestVisible
    private static String titleCase(String value) {
        if (String.isBlank(value) || !value.equals(value.toUpperCase())) {
            return value;
        }
        List<String> words = new List<String>();
        Set<String> minor = new Set<String>{ 'of', 'and', 'the', 'for', 'on', 'in' };
        for (String w : value.toLowerCase().split(' ')) {
            if (minor.contains(w)) {
                words.add(w);
            } else {
                words.add(w.length() <= 3 ? w.toUpperCase() : w.capitalize());
            }
        }
        return String.join(words, ' ');
    }
}
