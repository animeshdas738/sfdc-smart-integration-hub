@isTest
private class IntegrationExecutorTest {

    static testMethod void testSuccessPath() {
        // arrange
    Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"ok":true}'));
        Integration_Log__c log = new Integration_Log__c(Payload_Id__c = 'pid-success', Payload__c = '{"foo":"bar"}', Status__c='Queued');
        insert log;

        // act
        Test.startTest();
        System.enqueueJob(new IntegrationExecutor(new List<Id>{log.Id}));
        Test.stopTest();

        // assert
        Integration_Log__c[] res = [SELECT Id, Status__c, Attempts__c FROM Integration_Log__c WHERE Id = :log.Id];
        System.assertEquals('Success', res[0].Status__c);
    }

    static testMethod void testTransientRetryPath() {
        // arrange - mock a 500
    Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(500, 'server error'));
        Integration_Log__c log = new Integration_Log__c(Payload_Id__c = 'pid-transient', Payload__c = '{}', Status__c='Queued');
        insert log;

        // act
        Test.startTest();
        System.enqueueJob(new IntegrationExecutor(new List<Id>{log.Id}));
        Test.stopTest();

        // assert
        Integration_Log__c[] res = [SELECT Id, Status__c, Attempts__c, Next_Attempt_At__c FROM Integration_Log__c WHERE Id = :log.Id];
    System.assertEquals('RetryScheduled', res[0].Status__c);
    System.assertEquals(1, IntegrationAttemptsHelper.getAttempts(res[0]));
        System.assertNotEquals(null, res[0].Next_Attempt_At__c);
    }

    static testMethod void testPermanentDLQPath() {
        // arrange - mock a 400
    Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(400, 'bad payload'));
        Integration_Log__c log = new Integration_Log__c(Payload_Id__c = 'pid-perm', Payload__c = '{}', Status__c='Queued');
        insert log;

        // act
        Test.startTest();
        System.enqueueJob(new IntegrationExecutor(new List<Id>{log.Id}));
        Test.stopTest();

        // assert
        Integration_Log__c[] res = [SELECT Id, Status__c FROM Integration_Log__c WHERE Id = :log.Id];
        System.assertEquals('DeadLetter', res[0].Status__c);
        Integration_DLQ__c[] dlqs = [SELECT Id, Integration_Log__c FROM Integration_DLQ__c WHERE Integration_Log__c = :log.Id];
        System.assertEquals(1, dlqs.size());
    }

}
