public with sharing class IntegrationService {
    public static void send(String integrationName, String payloadId, String payloadJson) {
        send(integrationName, payloadId, payloadJson, null);
    }

    /**
     * Overload that accepts an Integration Endpoint Id and populates the lookup on the log.
     */
    public static void send(String integrationName, String payloadId, String payloadJson, Id endpointId) {
        // idempotency: if a successful log exists for this payloadId, skip reprocessing
        if (payloadId != null) {
            List<Integration_Log__c> existing = [SELECT Id, Status__c FROM Integration_Log__c WHERE Payload_Id__c = :payloadId AND Status__c = :IntegrationConstants.STATUS_SUCCESS LIMIT 1];
            if (!existing.isEmpty()) return;
        }

        Integration_Log__c log = new Integration_Log__c();
        log.Integration_Name__c = integrationName;
        log.Payload_Id__c = payloadId;
        log.Payload__c = payloadJson;
        if (endpointId != null) log.Integration_Endpoint__c = endpointId;
    log.Status__c = IntegrationConstants.STATUS_QUEUED;
        insert log;

        // enqueue a Queueable to perform the callout in a separate transaction
        try {
            System.enqueueJob(new IntegrationExecutor(new List<Id>{ log.Id }));
        } catch (Exception ex) {
            // If enqueue fails, mark the log as DeadLetter so it is visible to operators
            log.Status__c = IntegrationConstants.STATUS_DEADLETTER;
            log.Error_Message__c = 'Failed to enqueue executor: ' + ex.getMessage();
            update log;
        }
    }
}
