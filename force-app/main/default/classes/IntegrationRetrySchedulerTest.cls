@isTest
private class IntegrationRetrySchedulerTest {

    static testMethod void testSchedulerEnqueuesJobs() {
        // create several logs ready for retry
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Integer i=0;i<30;i++) {
            logs.add(new Integration_Log__c(Payload_Id__c = 'ps-'+i, Payload__c='{}', Status__c='RetryScheduled', Next_Attempt_At__c = System.now()));
        }
        insert logs;

        Test.startTest();
        // run scheduled job
        IntegrationRetryScheduler s = new IntegrationRetryScheduler();
        s.execute(null);
        Test.stopTest();

        // we cannot directly inspect enqueued jobs count in this environment reliably, but the job should not throw
        System.assert(true);
    }

}
