global class IntegrationRetryScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
            // Query ready logs and enqueue executor in batches (LIMIT comes from constants)
        Datetime now = System.now();
        String nowStr = now.formatGmt('yyyy-MM-dd\\'T\\'HH:mm:ss\\'Z\\'');
        String q = 'SELECT Id FROM Integration_Log__c WHERE (Status__c = \'" + IntegrationConstants.STATUS_QUEUED + "\' OR Status__c = \'" + IntegrationConstants.STATUS_RETRYSCHEDULED + "\')'
               + ' AND (Next_Attempt_At__c = NULL OR Next_Attempt_At__c <= ' + nowStr + ') LIMIT ' + String.valueOf(IntegrationConstants.SCHEDULER_QUERY_LIMIT);
            List<Integration_Log__c> ready = Database.query(q);

        if (ready.isEmpty()) return;

        // Enqueue in chunks to avoid large queueable payloads
        Integer chunkSize = IntegrationConstants.EXECUTOR_CHUNK_SIZE;
        for (Integer i = 0; i < ready.size(); i += chunkSize) {
            Integer endIdx = Math.min(i + chunkSize, ready.size());
            List<Id> ids = new List<Id>();
            for (Integer j = i; j < endIdx; j++) {
                ids.add(ready[j].Id);
            }
            System.enqueueJob(new IntegrationExecutor(ids));
        }
    }
}
