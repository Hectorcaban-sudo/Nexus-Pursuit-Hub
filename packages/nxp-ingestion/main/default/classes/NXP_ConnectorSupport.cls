/**
 * Shared helpers for connectors and the run machinery.
 */
public inherited sharing class NXP_ConnectorSupport {
    /** Parses "a=1&b=2" from NXP_Feed_Config__mdt.Extra_Parameters__c. Keys starting with _ are connector options. */
    public static Map<String, String> parseParams(String value) {
        Map<String, String> params = new Map<String, String>();
        if (String.isBlank(value)) {
            return params;
        }
        for (String pair : value.split('&')) {
            if (pair.contains('=')) {
                params.put(pair.substringBefore('=').trim(), pair.substringAfter('=').trim());
            }
        }
        return params;
    }

    /** Instantiates the connector class named on the feed config. */
    public static NXP_FeedConnector connectorFor(NXP_Feed_Config__mdt config) {
        Type t = Type.forName(config.Connector_Class__c);
        if (t == null) {
            throw new IllegalArgumentException('Connector class not found: ' + config.Connector_Class__c);
        }
        NXP_FeedConnector connector = (NXP_FeedConnector) t.newInstance();
        connector.init(config);
        return connector;
    }

    public static NXP_Feed_Config__mdt config(String feedName) {
        NXP_Feed_Config__mdt config = NXP_Feed_Config__mdt.getInstance(feedName);
        if (config == null) {
            throw new IllegalArgumentException('No NXP_Feed_Config__mdt record named ' + feedName);
        }
        return config;
    }

    /** Strips HTML tags and collapses whitespace (SAM.gov descriptions arrive as HTML). */
    public static String htmlToText(String html) {
        if (html == null) {
            return null;
        }
        String text = html.replaceAll('(?i)<br\\s*/?>', '\n').replaceAll('(?i)</p>', '\n\n').replaceAll('<[^>]+>', ' ');
        text = text.replace('&nbsp;', ' ')
            .replace('&amp;', '&')
            .replace('&lt;', '<')
            .replace('&gt;', '>')
            .replace('&quot;', '"')
            .replace('&#39;', '\'');
        return text.replaceAll('[ \\t]+', ' ').replaceAll('\\n\\s*\\n\\s*\\n+', '\n\n').trim();
    }
}
