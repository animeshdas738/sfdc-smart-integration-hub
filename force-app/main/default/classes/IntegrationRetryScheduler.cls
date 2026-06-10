/**
 * @description Schedulable wrapper that fires IntegrationRetryBatch on a recurring cron schedule.
 *              Deploy this class as a scheduled job (e.g. every 5 minutes) to provide near-real-time
 *              retry processing without manual intervention.
 */
global class IntegrationRetryScheduler implements Schedulable {

    /**
     * @description Scheduled entry point called by the platform. Runs IntegrationRetryBatch with the
     *              chunk size defined in IntegrationConstants so each batch scope fits one Queueable slot.
     * @param sc SchedulableContext provided by the platform.
     */
    global void execute(SchedulableContext sc) {
            // Query ready logs and enqueue executor in batches (LIMIT comes from constants)
            // For scale and reliability, run the batchable which will chunk via platform batch execution
            Integer batchSize = IntegrationConstants.EXECUTOR_CHUNK_SIZE;
            Database.executeBatch(new IntegrationRetryBatch(), batchSize);
    }
}
