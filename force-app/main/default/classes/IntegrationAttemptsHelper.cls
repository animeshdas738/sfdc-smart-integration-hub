/**
 * @description Utility class for safely reading, writing, and incrementing the Attempts__c Number field
 *              on Integration_Log__c records. Centralises the Decimal↔Integer conversion to avoid
 *              repetition across executor and retry logic.
 */
public with sharing class IntegrationAttemptsHelper {

    /**
     * @description Returns the current attempt count from the log record as an Integer.
     *              Returns 0 when the log is null or Attempts__c is null.
     * @param log Integration_Log__c record to read from.
     * @return    Current attempt count, never null.
     */
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

    /**
     * @description Writes an Integer value to Attempts__c, converting to Decimal as required by the Number field type.
     *              Passing null clears the field.
     * @param log      Integration_Log__c record to update.
     * @param attempts New attempt count to set, or null to clear.
     */
    public static void setAttempts(Integration_Log__c log, Integer attempts) {
        if (log == null) return;
        if (attempts == null) {
            log.Attempts__c = null;
        } else {
            log.Attempts__c = Decimal.valueOf(attempts);
        }
    }

    /**
     * @description Increments Attempts__c by one, updates the field on the record in memory, and returns the new value.
     * @param log Integration_Log__c record whose attempt count should be incremented.
     * @return    The new attempt count after incrementing.
     */
    public static Integer incrementAttempts(Integration_Log__c log) {
        Integer current = getAttempts(log);
        Integer next = current + 1;
        setAttempts(log, next);
        return next;
    }
}
