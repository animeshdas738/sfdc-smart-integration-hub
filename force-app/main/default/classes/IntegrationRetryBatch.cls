global class IntegrationRetryBatch implements Database.Batchable<sObject> {
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

    global void finish(Database.BatchableContext bc) {
        // no-op; monitoring/alerts could be added here
    }
}
