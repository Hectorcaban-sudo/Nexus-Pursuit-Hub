/**
 * Boolean keyword expressions for saved searches, e.g.
 *   cyber AND (zero trust OR ZTA) NOT training
 *   "identity management" ICAM*
 * Operators AND, OR, NOT are not case-sensitive; adjacent terms mean AND; quotes make a phrase;
 * a trailing * matches a word prefix. Matching is case-insensitive on whole words.
 */
public inherited sharing class NXP_KeywordExpression {
    public class ParseException extends Exception {
    }

    private class Node {
        public String op; // TERM, AND, OR, NOT
        public String term;
        public Boolean prefix = false;
        public List<Node> kids = new List<Node>();
    }

    private final Node root;
    private List<String> tokens;
    private Integer pos;

    public NXP_KeywordExpression(String expression) {
        this.tokens = tokenize(expression == null ? '' : expression);
        this.pos = 0;
        this.root = tokens.isEmpty() ? null : parseOr();
        if (pos < tokens.size()) {
            throw new ParseException('Unexpected "' + tokens[pos] + '" in keywords.');
        }
    }

    public Boolean isEmpty() {
        return root == null;
    }

    /** Lower-cases text and pads words with spaces so terms match whole words only. */
    public static String normalize(String text) {
        return ' ' + (text == null ? '' : text.toLowerCase().replaceAll('[^a-z0-9]+', ' ')) + ' ';
    }

    /** text must come from normalize(). matched collects the terms that hit. */
    public Boolean evaluate(String normalizedText, Set<String> matched) {
        return root == null ? true : eval(root, normalizedText, matched);
    }

    private Boolean eval(Node n, String text, Set<String> matched) {
        switch on n.op {
            when 'TERM' {
                String needle = normalize(n.term);
                if (n.prefix) {
                    needle = needle.removeEnd(' ');
                }
                Boolean hit = text.contains(needle);
                if (hit && matched != null) {
                    matched.add(n.term + (n.prefix ? '*' : ''));
                }
                return hit;
            }
            when 'NOT' {
                return !eval(n.kids[0], text, null);
            }
            when 'AND' {
                Boolean all = true;
                for (Node k : n.kids) {
                    all = eval(k, text, matched) && all;
                }
                return all;
            }
            when else {
                Boolean any = false;
                for (Node k : n.kids) {
                    any = eval(k, text, matched) || any;
                }
                return any;
            }
        }
    }

    // OR has the lowest precedence, then AND (explicit or implied), then NOT.
    private Node parseOr() {
        Node left = parseAnd();
        if (peek() != 'OR') {
            return left;
        }
        Node orNode = new Node();
        orNode.op = 'OR';
        orNode.kids.add(left);
        while (peek() == 'OR') {
            pos++;
            orNode.kids.add(parseAnd());
        }
        return orNode;
    }

    private Node parseAnd() {
        Node left = parseNot();
        Node andNode = null;
        while (pos < tokens.size() && peek() != 'OR' && peek() != ')') {
            if (peek() == 'AND') {
                pos++;
            }
            if (andNode == null) {
                andNode = new Node();
                andNode.op = 'AND';
                andNode.kids.add(left);
            }
            andNode.kids.add(parseNot());
        }
        return andNode == null ? left : andNode;
    }

    private Node parseNot() {
        if (peek() == 'NOT') {
            pos++;
            Node n = new Node();
            n.op = 'NOT';
            n.kids.add(parseNot());
            return n;
        }
        return parsePrimary();
    }

    private Node parsePrimary() {
        if (pos >= tokens.size()) {
            throw new ParseException('Keywords end too early.');
        }
        String t = tokens[pos++];
        if (t == '(') {
            Node inner = parseOr();
            if (peek() != ')') {
                throw new ParseException('Missing closing parenthesis in keywords.');
            }
            pos++;
            return inner;
        }
        if (t == ')' || t == 'AND' || t == 'OR') {
            throw new ParseException('Unexpected "' + t + '" in keywords.');
        }
        Node n = new Node();
        n.op = 'TERM';
        if (t.startsWith('"')) {
            n.term = t.removeStart('"').removeEnd('"');
        } else if (t.endsWith('*')) {
            n.term = t.removeEnd('*');
            n.prefix = true;
        } else {
            n.term = t;
        }
        if (String.isBlank(n.term)) {
            throw new ParseException('Empty term in keywords.');
        }
        return n;
    }

    private String peek() {
        return pos < tokens.size() ? tokens[pos] : null;
    }

    @TestVisible
    private static List<String> tokenize(String s) {
        List<String> out = new List<String>();
        Integer i = 0;
        while (i < s.length()) {
            String c = s.substring(i, i + 1);
            if (c == ' ' || c == '\t' || c == '\n' || c == ',') {
                i++;
            } else if (c == '(' || c == ')') {
                out.add(c);
                i++;
            } else if (c == '"') {
                Integer end = s.indexOf('"', i + 1);
                if (end < 0) {
                    throw new ParseException('Missing closing quote in keywords.');
                }
                out.add(s.substring(i, end + 1));
                i = end + 1;
            } else {
                Integer j = i;
                while (j < s.length() && ' \t\n,()"'.indexOf(s.substring(j, j + 1)) < 0) {
                    j++;
                }
                out.add(s.substring(i, j));
                i = j;
            }
        }
        return out;
    }
}
