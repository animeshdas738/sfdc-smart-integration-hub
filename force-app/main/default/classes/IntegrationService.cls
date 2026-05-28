public with sharing class IntegrationService {

    // Convenience overload — no endpoint or source context
    public static void send(String integrationName, String payloadId, String payloadJson) {
        send(integrationName, payloadId, payloadJson, null, null, null);
    }

    // Overload with endpoint, no source context
    public static void send(String integrationName, String payloadId, String payloadJson, Id endpointId) {
        send(integrationName, payloadId, payloadJson, endpointId, null, null);
    }

    // Full signature — used by IntegrationEventHandler and any caller that needs source traceability
    public static void send(String integrationName, String payloadId, String payloadJson, Id endpointId, String sourceType, String sourceRecordId) {
        // idempotency: skip if a successful log already exists for this payloadId
        if (payloadId != null) {
            List<Integration_Log__c> existing = [
                SELECT Id FROM Integration_Log__c
                WHERE Payload_Id__c = :payloadId AND Status__c = :IntegrationConstants.STATUS_SUCCESS
                LIMIT 1
            ];
            if (!existing.isEmpty()) return;
        }

        Integration_Log__c log = new Integration_Log__c(
            Integration_Name__c = integrationName,
            Payload_Id__c       = payloadId,
            Payload__c          = payloadJson,
            Status__c           = IntegrationConstants.STATUS_QUEUED
        );
        if (endpointId    != null) log.Integration_Endpoint__c = endpointId;
        if (sourceType    != null) log.Source__c               = sourceType;
        if (sourceRecordId != null) log.Related_Record_Id__c   = sourceRecordId;
        insert log;

        try {
            System.enqueueJob(new IntegrationExecutor(new List<Id>{ log.Id }));
        } catch (Exception ex) {
            log.Status__c      = IntegrationConstants.STATUS_DEADLETTER;
            log.Error_Message__c = 'Failed to enqueue executor: ' + ex.getMessage();
            update log;
        }
    }
}
