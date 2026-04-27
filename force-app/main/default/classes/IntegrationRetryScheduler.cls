global class IntegrationRetryScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        // Query ready logs and enqueue executor in batches
        List<Integration_Log__c> ready = [SELECT Id FROM Integration_Log__c
                                          WHERE (Status__c = 'Queued' OR Status__c = 'RetryScheduled')
                                            AND (Next_Attempt_At__c = NULL OR Next_Attempt_At__c <= :System.now())
                                          LIMIT 200];

        if (ready.isEmpty()) return;

        // Enqueue in chunks to avoid large queueable payloads
        Integer chunkSize = 25;
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
