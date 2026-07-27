/**
 * @description Queueable job that processes a batch of Integration_Log__c records by making outbound
 *              HTTP callouts and updating each record's status based on the response. Implements the
 *              full retry/dead-letter lifecycle: successful responses set Status to Success; transient
 *              failures schedule a back-off retry up to the configured maximum; permanent failures or
 *              exhausted retries move the record to DeadLetter and create an Integration_DLQ__c entry.
 */
public with sharing class IntegrationExecutor implements Queueable, Database.AllowsCallouts {
    private List<Id> logIds;

    /**
     * @description Constructs the executor with the list of Integration_Log__c IDs to process.
     * @param logIds List of record IDs to fetch and attempt delivery for. Null is treated as empty.
     */
    public IntegrationExecutor(List<Id> logIds) {
        this.logIds = (logIds == null) ? new List<Id>() : logIds;
    }

    /**
     * @description Queueable entry point. Queries the log records FOR UPDATE to prevent concurrent
     *              processing, performs the HTTP callout for each eligible record, then bulk-updates
     *              statuses and bulk-inserts DLQ entries. Records already marked Success are skipped.
     * @param ctx QueueableContext provided by the platform.
     */
    public void execute(QueueableContext ctx) {
        if (logIds.isEmpty()) return;

    List<Integration_Log__c> logs = [SELECT Id, Integration_Name__c, Payload_Id__c, Payload__c, Status__c, Attempts__c, Next_Attempt_At__c,
                                                Integration_Endpoint__r.Named_Credential__c, Integration_Endpoint__r.Endpoint_Path__c, Integration_Endpoint__r.HTTP_Method__c
                                         FROM Integration_Log__c
                                         WHERE Id IN :logIds
                                         FOR UPDATE];

        List<Integration_Log__c> toUpdate = new List<Integration_Log__c>();
        List<Integration_DLQ__c> toInsertDlq = new List<Integration_DLQ__c>();

        for (Integration_Log__c log : logs) {
            // skip if already processed successfully
            if (log.Status__c == IntegrationConstants.STATUS_SUCCESS) continue;

            // ensure it's ready to be processed
            Boolean ready = false;
            if (log.Status__c == IntegrationConstants.STATUS_QUEUED) ready = true;
            else if (log.Status__c == IntegrationConstants.STATUS_RETRYSCHEDULED) {
                if (log.Next_Attempt_At__c == null || log.Next_Attempt_At__c <= System.now()) ready = true;
            }
            if (!ready) continue;

            String namedCredential = (log.Integration_Endpoint__r != null && log.Integration_Endpoint__r.Named_Credential__c != null)
                ? log.Integration_Endpoint__r.Named_Credential__c
                : IntegrationConstants.DEFAULT_NAMED_CREDENTIAL;
            String resourcePath = (log.Integration_Endpoint__r != null && log.Integration_Endpoint__r.Endpoint_Path__c != null)
                ? log.Integration_Endpoint__r.Endpoint_Path__c
                : IntegrationConstants.DEFAULT_RESOURCE_PATH;
            String httpMethod = (log.Integration_Endpoint__r != null && log.Integration_Endpoint__r.HTTP_Method__c != null)
                ? log.Integration_Endpoint__r.HTTP_Method__c
                : 'POST';
            Long startMs = System.currentTimeMillis();
            CalloutWrapper.CalloutResult cr = CalloutWrapper.callEndpoint(namedCredential, resourcePath, log.Payload__c, httpMethod);
            ((SObject)log).put('Duration_ms__c', Decimal.valueOf(System.currentTimeMillis() - startMs));
            ErrorMapper.ErrorResult er = ErrorMapper.classify(cr.statusCode, null);

            if (cr.statusCode != null && cr.statusCode >= 200 && cr.statusCode < 300) {
                log.Status__c = IntegrationConstants.STATUS_SUCCESS;
                log.Error_Code__c = String.valueOf(cr.statusCode);
                log.Error_Message__c = cr.body;
                ((SObject)log).put('Response_Body__c', cr.body);
            } else if (er.category == ErrorMapper.ErrorCategory.TRANSIENT) {
                Integer attemptsInt = IntegrationAttemptsHelper.incrementAttempts(log);

                Integer maxAttempts = IntegrationConfig.getMaxAttempts();
                Integer baseDelay = IntegrationConfig.getBaseDelaySeconds();
                    if (attemptsInt >= maxAttempts) {
                    log.Status__c = IntegrationConstants.STATUS_DEADLETTER;
                    ((SObject)log).put('Response_Body__c', cr.body);
                    Integration_DLQ__c dlq = new Integration_DLQ__c();
                    dlq.Integration_Log__c = log.Id;
                    dlq.Poison_Reason__c = (cr.body == null) ? 'Transient failures exceeded' : cr.body;
                    dlq.Raw_Payload__c = log.Payload__c;
                    toInsertDlq.add(dlq);
                } else {
                    log.Next_Attempt_At__c = RetryCalculator.computeNextAttempt(attemptsInt, baseDelay);
                    log.Status__c = IntegrationConstants.STATUS_RETRYSCHEDULED;
                    log.Error_Code__c = (cr.statusCode == null) ? 'EX' : String.valueOf(cr.statusCode);
                    log.Error_Message__c = cr.body;
                    ((SObject)log).put('Response_Body__c', cr.body);
                }
            } else {
                log.Status__c = IntegrationConstants.STATUS_DEADLETTER;
                ((SObject)log).put('Response_Body__c', cr.body);
                Integration_DLQ__c dlq = new Integration_DLQ__c();
                dlq.Integration_Log__c = log.Id;
                dlq.Poison_Reason__c = (cr.body == null) ? 'Permanent failure' : cr.body;
                dlq.Raw_Payload__c = log.Payload__c;
                toInsertDlq.add(dlq);
            }

            toUpdate.add(log);
        }

        if (!toUpdate.isEmpty()) {
            try { update toUpdate; } catch (Exception ex) { /* best-effort update; errors should be handled/logged in production */ }
        }

        if (!toInsertDlq.isEmpty()) {
            try { insert toInsertDlq; } catch (Exception ex) { /* log / alert in production */ }
        }
    }
}
