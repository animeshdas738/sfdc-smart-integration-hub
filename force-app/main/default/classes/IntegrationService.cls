/**
 * @description Service layer entry point for submitting outbound integration requests. Creates an
 *              Integration_Log__c record in Queued status and immediately enqueues IntegrationExecutor
 *              for delivery. Provides idempotency via Payload_Id__c: duplicate submissions for the
 *              same payload ID (that have not yet dead-lettered) are silently ignored.
 */
public with sharing class IntegrationService {

    /**
     * @description Convenience overload that submits a payload with no endpoint or source record context.
     * @param integrationName Logical name of the integration (e.g. 'AccountSync').
     * @param payloadId       Unique identifier for idempotency; null disables duplicate checking.
     * @param payloadJson     JSON string of the outbound request body.
     */
    public static void send(String integrationName, String payloadId, String payloadJson) {
        send(integrationName, payloadId, payloadJson, null, null, null);
    }

    /**
     * @description Overload that targets a specific Integration_Endpoint__c record but omits source traceability.
     * @param integrationName Logical name of the integration.
     * @param payloadId       Unique identifier for idempotency; null disables duplicate checking.
     * @param payloadJson     JSON string of the outbound request body.
     * @param endpointId      ID of the Integration_Endpoint__c record supplying Named Credential and path.
     */
    public static void send(String integrationName, String payloadId, String payloadJson, Id endpointId) {
        send(integrationName, payloadId, payloadJson, endpointId, null, null);
    }

    /**
     * @description Full signature used by IntegrationEventHandler and callers requiring source traceability.
     *              Checks idempotency, inserts the log record, and enqueues the executor. If enqueueing
     *              fails the log is immediately dead-lettered with the exception message.
     * @param integrationName Logical name of the integration.
     * @param payloadId       Unique identifier for idempotency; null disables duplicate checking.
     * @param payloadJson     JSON string of the outbound request body.
     * @param endpointId      ID of the Integration_Endpoint__c record, or null to use defaults.
     * @param sourceType      API name of the originating SObject type for traceability (nullable).
     * @param sourceRecordId  Salesforce ID of the originating record for traceability (nullable).
     */
    public static void send(String integrationName, String payloadId, String payloadJson, Id endpointId, String sourceType, String sourceRecordId) {
        // idempotency: skip if a successful log already exists for this payloadId
        if (payloadId != null) {
            List<Integration_Log__c> existing = [
                SELECT Id FROM Integration_Log__c
                WHERE Payload_Id__c = :payloadId AND Status__c != :IntegrationConstants.STATUS_DEADLETTER
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
