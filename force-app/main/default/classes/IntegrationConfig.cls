public with sharing class IntegrationConfig {
    public static Integer getBaseDelaySeconds() {
        try {
            Integration_Settings__mdt cfg = [SELECT Base_Delay_Seconds__c FROM Integration_Settings__mdt LIMIT 1];
            return (cfg.Base_Delay_Seconds__c == null) ? 30 : Integer.valueOf(cfg.Base_Delay_Seconds__c);
        } catch (Exception ex) {
            return 30;
        }
    }

    public static Integer getMaxAttempts() {
        try {
            Integration_Settings__mdt cfg = [SELECT Max_Attempts__c FROM Integration_Settings__mdt LIMIT 1];
            return (cfg.Max_Attempts__c == null) ? 5 : Integer.valueOf(cfg.Max_Attempts__c);
        } catch (Exception ex) {
            return 5;
        }
    }
}
