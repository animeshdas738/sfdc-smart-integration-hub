/**
 * @description Batchable job that selects Integration_Log__c records in Queued or RetryScheduled status
 *              whose next-attempt time has elapsed, then dispatches them to IntegrationExecutor for
 *              processing. Batch size is controlled by IntegrationConstants.EXECUTOR_CHUNK_SIZE so that
 *              each batch scope maps to a single Queueable execution unit.
 */
global class IntegrationRetryBatch implements Database.Batchable<sObject> {

    /**
     * @description Returns a QueryLocator scoped to logs that are ready for processing:
     *              status is Queued or RetryScheduled and Next_Attempt_At__c is null or in the past.
     * @param bc Batchable context provided by the platform.
     * @return   QueryLocator over eligible Integration_Log__c records.
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime now = System.now();
        String q = 'SELECT Id FROM Integration_Log__c '
                 + 'WHERE (Status__c = :IntegrationConstants.STATUS_QUEUED OR Status__c = :IntegrationConstants.STATUS_RETRYSCHEDULED) '
                 + 'AND (Next_Attempt_At__c = NULL OR Next_Attempt_At__c <= :now)';
        // Use QueryLocator with bind variables by building via Database.getQueryLocator with a concrete SOQL string
        return Database.getQueryLocator([SELECT Id FROM Integration_Log__c
                                        WHERE (Status__c = :IntegrationConstants.STATUS_QUEUED OR Status__c = :IntegrationConstants.STATUS_RETRYSCHEDULED)
                                        AND (Next_Attempt_At__c = NULL OR Next_Attempt_At__c <= :now)]);
    }

    /**
     * @description Enqueues an IntegrationExecutor Queueable for the current batch scope of log IDs.
     * @param bc    Batchable context provided by the platform.
     * @param scope Batch of Integration_Log__c records to process.
     */
    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        List<Integration_Log__c> logs = (List<Integration_Log__c>)scope;
        if (logs.isEmpty()) return;

        // Enqueue IntegrationExecutor per batch scope (ids already chunked by batch size)
        List<Id> ids = new List<Id>();
        for (Integration_Log__c l : logs) ids.add(l.Id);
        try {
            System.enqueueJob(new IntegrationExecutor(ids));
        } catch (Exception e) {
            // best effort; production should log/alert
        }
    }

    /**
     * @description Post-processing hook called by the platform after all batch scopes complete.
     *              Reserved for future monitoring or alerting integration.
     * @param bc Batchable context provided by the platform.
     */
    global void finish(Database.BatchableContext bc) {
        // no-op; monitoring/alerts could be added here
    }
}
