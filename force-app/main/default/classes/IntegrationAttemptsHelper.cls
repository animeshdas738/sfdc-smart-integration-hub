public with sharing class IntegrationAttemptsHelper {
    // Read Attempts__c (Number) safely as Integer. Returns 0 when null.
    public static Integer getAttempts(Integration_Log__c log) {
        if (log == null) return 0;
        Decimal d = log.Attempts__c;
        if (d == null) return 0;
        try {
            return d.intValue();
        } catch (Exception e) {
            return 0;
        }
    }

    // Set Attempts__c (Number) from an Integer.
    public static void setAttempts(Integration_Log__c log, Integer attempts) {
        if (log == null) return;
        if (attempts == null) {
            log.Attempts__c = null;
        } else {
            log.Attempts__c = Decimal.valueOf(attempts);
        }
    }

    // Safe increment: reads current attempts, returns new value and mutates log.Attempts__c
    public static Integer incrementAttempts(Integration_Log__c log) {
        Integer current = getAttempts(log);
        Integer next = current + 1;
        setAttempts(log, next);
        return next;
    }
}
