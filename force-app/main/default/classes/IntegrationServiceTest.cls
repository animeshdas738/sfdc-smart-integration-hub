@isTest
private class IntegrationServiceTest {
    @isTest static void testSuccessCallout() {
    Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"result":"ok"}'));
        Test.startTest();
        IntegrationService.send('TestInt', 'pid-1', '{"name":"ok"}');
        Test.stopTest();

        Integration_Log__c[] logs = [SELECT Id, Status__c, Error_Code__c FROM Integration_Log__c WHERE Payload_Id__c = 'pid-1'];
        System.assertEquals(1, logs.size());
        System.assertEquals('Success', logs[0].Status__c);
    }

    @isTest static void testTransientFailureSchedulesRetry() {
    Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(500, 'Server error'));
        Test.startTest();
        IntegrationService.send('TestInt', 'pid-2', '{"name":"fail5xx"}');
        Test.stopTest();

        Integration_Log__c[] logs = [SELECT Id, Status__c, Attempts__c, Next_Attempt_At__c FROM Integration_Log__c WHERE Payload_Id__c = 'pid-2'];
        System.assertEquals(1, logs.size());
    System.assertEquals('RetryScheduled', logs[0].Status__c);
    System.assertEquals(1, IntegrationAttemptsHelper.getAttempts(logs[0]));
        System.assertNotEquals(null, logs[0].Next_Attempt_At__c);
    }

    @isTest static void testPermanentFailureGoesToDLQ() {
    Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(400, 'Client error'));
        Test.startTest();
        IntegrationService.send('TestInt', 'pid-3', '{"name":"fail4xx"}');
        Test.stopTest();

        Integration_Log__c[] logs = [SELECT Id, Status__c FROM Integration_Log__c WHERE Payload_Id__c = 'pid-3'];
        System.assertEquals(1, logs.size());
        System.assertEquals('DeadLetter', logs[0].Status__c);

    // query DLQ by Integration_Log__c reference
    Integration_DLQ__c[] dlqs = [SELECT Id, Integration_Log__c, Poison_Reason__c FROM Integration_DLQ__c WHERE Integration_Log__c = :logs[0].Id];
        System.assertEquals(1, dlqs.size());
    }
}
