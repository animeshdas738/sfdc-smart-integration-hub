@isTest
private class IntegrationEventHandlerTest {

    @TestSetup
    static void setup() {
        insert new Integration_Endpoint__c(
            External_System_Name__c       = 'Test System',
            Named_Credential__c           = 'TestCred',
            Endpoint_Path__c              = '/test',
            Payload_Mapping__c            = '{"text":"{{{message}}}"}',
            Default_Max_Attempts__c       = 3,
            Default_Base_Delay_Seconds__c = 30,
            Active__c                     = true
        );
    }

    @isTest
    static void testHandleValidEvent() {
        Integration_Endpoint__c ep = [SELECT Id FROM Integration_Endpoint__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"result":"ok"}'));

        Integration_Event__e evt = new Integration_Event__e(
            Integration_Name__c   = 'TestIntegration',
            Endpoint_Id__c        = ep.Id,
            Payload__c            = '{"text":"hello"}',
            Payload_Id__c         = 'evt-test-001',
            Source_Object_Type__c = 'CaseComment',
            Source_Record_Id__c   = '00000000000000A'
        );

        Test.startTest();
        IntegrationEventHandler.handle(new List<Integration_Event__e>{ evt });
        Test.stopTest();

        Integration_Log__c log = [
            SELECT Id, Status__c, Integration_Name__c, Source__c, Related_Record_Id__c, Integration_Endpoint__c
            FROM Integration_Log__c
            WHERE Payload_Id__c = 'evt-test-001'
            LIMIT 1
        ];
        System.assertEquals('Success',          log.Status__c);
        System.assertEquals('TestIntegration',  log.Integration_Name__c);
        System.assertEquals('CaseComment',      log.Source__c);
        System.assertEquals('00000000000000A',  log.Related_Record_Id__c);
        System.assertEquals(ep.Id,              log.Integration_Endpoint__c);
    }

    @isTest
    static void testAutoGeneratesPayloadId() {
        Integration_Endpoint__c ep = [SELECT Id FROM Integration_Endpoint__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"result":"ok"}'));

        Integration_Event__e evt = new Integration_Event__e(
            Integration_Name__c = 'AutoIdTest',
            Endpoint_Id__c      = ep.Id,
            Payload__c          = '{"text":"auto"}'
            // Payload_Id__c intentionally omitted
        );

        Test.startTest();
        IntegrationEventHandler.handle(new List<Integration_Event__e>{ evt });
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Id FROM Integration_Log__c WHERE Integration_Name__c = 'AutoIdTest'];
        System.assertEquals(1, logs.size(), 'A log should be created even without an explicit Payload_Id__c');
    }

    @isTest
    static void testSkipsMissingRequiredFields() {
        // Missing Endpoint_Id__c and Payload__c — handler should skip silently
        Integration_Event__e evt = new Integration_Event__e(
            Integration_Name__c = 'MissingFields'
        );

        Test.startTest();
        IntegrationEventHandler.handle(new List<Integration_Event__e>{ evt });
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Id FROM Integration_Log__c WHERE Integration_Name__c = 'MissingFields'];
        System.assertEquals(0, logs.size(), 'No log should be created when required fields are missing');
    }

    @isTest
    static void testIdempotencyGuard() {
        Integration_Endpoint__c ep = [SELECT Id FROM Integration_Endpoint__c LIMIT 1];

        // Pre-existing successful log for the same payloadId
        insert new Integration_Log__c(
            Integration_Name__c = 'IdempotencyTest',
            Payload_Id__c       = 'evt-idem-001',
            Payload__c          = '{}',
            Status__c           = 'Success'
        );

        Integration_Event__e evt = new Integration_Event__e(
            Integration_Name__c = 'IdempotencyTest',
            Endpoint_Id__c      = ep.Id,
            Payload__c          = '{"text":"dup"}',
            Payload_Id__c       = 'evt-idem-001'
        );

        Test.startTest();
        IntegrationEventHandler.handle(new List<Integration_Event__e>{ evt });
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Id FROM Integration_Log__c WHERE Payload_Id__c = 'evt-idem-001'];
        System.assertEquals(1, logs.size(), 'Idempotency guard must prevent a duplicate log');
    }

    @isTest
    static void testBulkHandling() {
        Integration_Endpoint__c ep = [SELECT Id FROM Integration_Endpoint__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"result":"ok"}'));

        List<Integration_Event__e> events = new List<Integration_Event__e>();
        for (Integer i = 0; i < 10; i++) {
            events.add(new Integration_Event__e(
                Integration_Name__c = 'BulkTest',
                Endpoint_Id__c      = ep.Id,
                Payload__c          = '{"index":' + i + '}',
                Payload_Id__c       = 'bulk-evt-' + i
            ));
        }

        Test.startTest();
        IntegrationEventHandler.handle(events);
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Id FROM Integration_Log__c WHERE Integration_Name__c = 'BulkTest'];
        System.assertEquals(10, logs.size(), 'All 10 events must produce individual log records');
    }

    @isTest
    static void testTransientFailureSchedulesRetry() {
        Integration_Endpoint__c ep = [SELECT Id FROM Integration_Endpoint__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(503, 'Service unavailable'));

        Integration_Event__e evt = new Integration_Event__e(
            Integration_Name__c = 'RetryTest',
            Endpoint_Id__c      = ep.Id,
            Payload__c          = '{"text":"retry"}',
            Payload_Id__c       = 'evt-retry-001'
        );

        Test.startTest();
        IntegrationEventHandler.handle(new List<Integration_Event__e>{ evt });
        Test.stopTest();

        Integration_Log__c log = [SELECT Id, Status__c FROM Integration_Log__c WHERE Payload_Id__c = 'evt-retry-001' LIMIT 1];
        System.assertEquals('RetryScheduled', log.Status__c);
    }

    @isTest
    static void testHandlerCatchesExceptionOnBadEndpointId() {
        // Covers the catch block (line 28): an invalid Id cast throws StringException,
        // which the handler swallows so no log is created.
        Integration_Event__e evt = new Integration_Event__e(
            Integration_Name__c = 'ExceptionTest',
            Endpoint_Id__c      = 'NOT-A-VALID-ID',
            Payload__c          = '{}'
        );

        Test.startTest();
        IntegrationEventHandler.handle(new List<Integration_Event__e>{ evt });
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Id FROM Integration_Log__c WHERE Integration_Name__c = 'ExceptionTest'];
        System.assertEquals(0, logs.size(), 'Exception should be swallowed and no log created');
    }
}
