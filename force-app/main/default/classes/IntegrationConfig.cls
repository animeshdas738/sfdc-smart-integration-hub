/**
 * @description Reads runtime configuration from the Integration_Settings__mdt custom metadata type.
 *              Falls back to safe defaults when no metadata record exists, preventing failures in
 *              sandboxes or scratch orgs where metadata may not be deployed.
 */
public with sharing class IntegrationConfig {

    /**
     * @description Returns the base delay in seconds used for exponential backoff calculations.
     *              Defaults to 30 seconds when no metadata record is present.
     * @return Base delay in seconds.
     */
    public static Integer getBaseDelaySeconds() {
        try {
            Integration_Settings__mdt cfg = [SELECT Base_Delay_Seconds__c FROM Integration_Settings__mdt LIMIT 1];
            return (cfg.Base_Delay_Seconds__c == null) ? 30 : Integer.valueOf(cfg.Base_Delay_Seconds__c);
        } catch (Exception ex) {
            return 30;
        }
    }

    /**
     * @description Returns the maximum number of delivery attempts before a log is dead-lettered.
     *              Defaults to 5 when no metadata record is present.
     * @return Maximum retry attempt count.
     */
    public static Integer getMaxAttempts() {
        try {
            Integration_Settings__mdt cfg = [SELECT Max_Attempts__c FROM Integration_Settings__mdt LIMIT 1];
            return (cfg.Max_Attempts__c == null) ? 5 : Integer.valueOf(cfg.Max_Attempts__c);
        } catch (Exception ex) {
            return 5;
        }
    }
}
