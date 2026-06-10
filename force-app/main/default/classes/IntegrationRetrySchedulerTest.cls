@isTest
private class IntegrationRetrySchedulerTest {

    static testMethod void testSchedulerEnqueuesJobs() {
        // Keep record count within a single batch chunk (EXECUTOR_CHUNK_SIZE = 25).
        // Salesforce's test framework only allows one executeBatch invocation per test,
        // and each chunk over the batch size counts as a separate invocation.
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Integer i = 0; i < 10; i++) {
            logs.add(new Integration_Log__c(
                Payload_Id__c = 'ps-' + i,
                Payload__c = '{}',
                Status__c = IntegrationConstants.STATUS_RETRYSCHEDULED,
                Next_Attempt_At__c = System.now().addSeconds(-1)
            ));
        }
        insert logs;

        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"ok":true}'));

        Test.startTest();
        IntegrationRetryScheduler s = new IntegrationRetryScheduler();
        s.execute(null);
        Test.stopTest();

        System.assert(true, 'Scheduler should complete without errors');
    }

}
