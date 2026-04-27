@isTest
private class IntegrationAdditionalTests {

    @isTest static void testMaxAttemptsLeadsToDLQ() {
        // Arrange - create log
        Integration_Log__c log = new Integration_Log__c(Payload_Id__c = 'pid-max', Payload__c='{}', Status__c = IntegrationConstants.STATUS_QUEUED);
        insert log;

        // Mock transient failures
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(500, 'Server error'));

        Integer maxAttempts = IntegrationConfig.getMaxAttempts();

        Test.startTest();
        // simulate repeated executor runs
        for (Integer i = 0; i < maxAttempts; i++) {
            System.enqueueJob(new IntegrationExecutor(new List<Id>{log.Id}));
        }
        Test.stopTest();

        // Assert that a DLQ record exists and Status is DeadLetter
        Integration_Log__c[] res = [SELECT Id, Status__c FROM Integration_Log__c WHERE Id = :log.Id];
        System.assertEquals(IntegrationConstants.STATUS_DEADLETTER, res[0].Status__c);
        Integration_DLQ__c[] dlqs = [SELECT Id FROM Integration_DLQ__c WHERE Integration_Log__c = :log.Id];
        System.assertEquals(1, dlqs.size());
    }

    @isTest static void testIntegrationServiceIdempotency() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"ok":true}'));

        Test.startTest();
        IntegrationService.send('TestIdemp', 'pid-idemp', '{"name":"ok"}');
        // call again with same payloadId
        IntegrationService.send('TestIdemp', 'pid-idemp', '{"name":"ok"}');
        Test.stopTest();

        // Only one success log should exist
        List<Integration_Log__c> logs = [SELECT Id, Status__c FROM Integration_Log__c WHERE Payload_Id__c = 'pid-idemp'];
        System.assertEquals(1, logs.size());
        System.assertEquals(IntegrationConstants.STATUS_SUCCESS, logs[0].Status__c);
    }
}
