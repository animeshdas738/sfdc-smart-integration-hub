public with sharing class IntegrationService {
    public static void send(String integrationName, String payloadId, String payloadJson) {
        // idempotency: if a successful log exists for this payloadId, skip reprocessing
        if (payloadId != null) {
            List<Integration_Log__c> existing = [SELECT Id, Status__c FROM Integration_Log__c WHERE Payload_Id__c = :payloadId AND Status__c = :IntegrationConstants.STATUS_SUCCESS LIMIT 1];
            if (!existing.isEmpty()) return;
        }

        Integration_Log__c log = new Integration_Log__c();
        log.Integration_Name__c = integrationName;
        log.Payload_Id__c = payloadId;
        log.Payload__c = payloadJson;
    log.Status__c = IntegrationConstants.STATUS_QUEUED;
        insert log;

        // perform callout synchronously for demo; production should queue this
    CalloutWrapper.CalloutResult cr = CalloutWrapper.postToNamedCredential(IntegrationConstants.DEFAULT_NAMED_CREDENTIAL, IntegrationConstants.DEFAULT_RESOURCE_PATH, payloadJson);
        ErrorMapper.ErrorResult er = ErrorMapper.classify(cr.statusCode, null);
        if (cr.statusCode != null && cr.statusCode >= 200 && cr.statusCode < 300) {
            log.Status__c = 'Success';
            log.Error_Code__c = String.valueOf(cr.statusCode);
            log.Error_Message__c = cr.body;
        } else if (er.category == ErrorMapper.ErrorCategory.TRANSIENT) {
            log.Attempts__c = 1;
            log.Next_Attempt_At__c = RetryCalculator.computeNextAttempt(1, IntegrationConfig.getBaseDelaySeconds());
            log.Status__c = IntegrationConstants.STATUS_RETRYSCHEDULED;
            log.Error_Code__c = (cr.statusCode == null) ? 'EX' : String.valueOf(cr.statusCode);
            log.Error_Message__c = cr.body;
        } else {
            log.Status__c = IntegrationConstants.STATUS_DEADLETTER;
            // create DLQ record
            Integration_DLQ__c dlq = new Integration_DLQ__c();
            dlq.Integration_Log__c = log.Id;
            dlq.Poison_Reason__c = (cr.body == null) ? 'Permanent failure' : cr.body;
            dlq.Raw_Payload__c = payloadJson;
            insert dlq;
        }
        update log;
    }
}
