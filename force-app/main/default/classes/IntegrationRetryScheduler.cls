global class IntegrationRetryScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
            // Query ready logs and enqueue executor in batches (LIMIT comes from constants)
            // For scale and reliability, run the batchable which will chunk via platform batch execution
            Integer batchSize = IntegrationConstants.EXECUTOR_CHUNK_SIZE;
            Database.executeBatch(new IntegrationRetryBatch(), batchSize);
    }
}
