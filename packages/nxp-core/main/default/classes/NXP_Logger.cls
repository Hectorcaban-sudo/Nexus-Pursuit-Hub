/**
 * Application logger. Buffers entries in memory and writes them to NXP_Log__c on flush().
 * Never throws: logging must not break the transaction it is describing.
 */
public without sharing class NXP_Logger {
    private static final List<NXP_Log__c> BUFFER = new List<NXP_Log__c>();
    private static final String TRANSACTION_ID = Request.getCurrent().getRequestId();

    public static void error(String source, String message, Exception ex, Id recordId) {
        add('ERROR', source, message, ex, recordId);
    }

    public static void error(String source, String message) {
        add('ERROR', source, message, null, null);
    }

    public static void error(String source, Exception ex) {
        add('ERROR', source, ex == null ? null : ex.getMessage(), ex, null);
    }

    public static void warn(String source, String message) {
        add('WARN', source, message, null, null);
    }

    public static void info(String source, String message) {
        add('INFO', source, message, null, null);
    }

    public static List<NXP_Log__c> pending() {
        return BUFFER.clone();
    }

    /** Writes buffered entries. Call at the end of jobs, REST calls and controllers. */
    public static void flush() {
        if (BUFFER.isEmpty()) {
            return;
        }
        List<NXP_Log__c> toWrite = BUFFER.clone();
        BUFFER.clear();
        try {
            if (Limits.getDmlStatements() < Limits.getLimitDmlStatements()) {
                Database.insert(toWrite, false, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'NXP_Logger could not write logs: ' + e.getMessage());
        }
    }

    private static void add(String level, String source, String message, Exception ex, Id recordId) {
        System.debug(level == 'ERROR' ? LoggingLevel.ERROR : LoggingLevel.INFO, source + ': ' + message);
        BUFFER.add(
            new NXP_Log__c(
                Level__c = level,
                Source__c = NXP_Text.truncate(source, 255),
                Message__c = NXP_Text.truncate(message, 131072),
                Stack_Trace__c = ex == null ? null : NXP_Text.truncate(ex.getStackTraceString(), 32768),
                Record_Id__c = recordId,
                Transaction_Id__c = TRANSACTION_ID
            )
        );
    }
}
