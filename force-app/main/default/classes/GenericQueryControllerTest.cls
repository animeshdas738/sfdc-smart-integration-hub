@isTest
private class GenericQueryControllerTest {

    private static final String LOG_OBJECT = 'Integration_Log__c';

    private static List<Integration_Log__c> buildLogs(Integer count, String prefix) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Integer i = 0; i < count; i++) {
            logs.add(new Integration_Log__c(
                Integration_Name__c = 'GenericTableTest',
                Payload_Id__c = prefix + i,
                Status__c = 'Success'
            ));
        }
        return logs;
    }

    private static User createStandardUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueSuffix = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User standardUser = new User(
            Alias = 'gctl',
            Email = 'gctl' + uniqueSuffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'GenericControllerTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'gctl' + uniqueSuffix + '@example.com.test'
        );
        insert standardUser;
        return standardUser;
    }

    @isTest
    static void testGetRecordsReturnsColumnsAndRows() {
        insert buildLogs(200, 'ctl-happy-');

        Test.startTest();
        GenericQueryService.GenericQueryResult result = GenericQueryController.getRecords(
            LOG_OBJECT, new List<String>{ 'Status__c', 'Integration_Name__c' }, 200);
        Test.stopTest();

        System.assertEquals(200, result.rows.size());
        System.assertEquals(2, result.columns.size());
    }

    @isTest
    static void testBlankObjectNameIsRejected() {
        Test.startTest();
        try {
            GenericQueryController.getRecords('  ', new List<String>{ 'Status__c' }, 10);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertEquals(GenericTableConstants.ERR_INVALID_INPUT, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testEmptyAndNullFieldListAreRejected() {
        Test.startTest();
        try {
            GenericQueryController.getRecords(LOG_OBJECT, new List<String>(), 10);
            System.assert(false, 'Expected AuraHandledException for empty list');
        } catch (AuraHandledException e) {
            System.assertEquals(GenericTableConstants.ERR_INVALID_INPUT, e.getMessage());
        }
        try {
            GenericQueryController.getRecords(LOG_OBJECT, null, 10);
            System.assert(false, 'Expected AuraHandledException for null list');
        } catch (AuraHandledException e) {
            System.assertEquals(GenericTableConstants.ERR_INVALID_INPUT, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testServiceValidationErrorIsPassedToUser() {
        Test.startTest();
        try {
            GenericQueryController.getRecords(LOG_OBJECT, new List<String>{ 'Not_A_Field__c' }, 10);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertEquals(GenericTableConstants.ERR_UNKNOWN_FIELD, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUserWithoutObjectAccessGetsAuraError() {
        User standardUser = createStandardUser();
        insert buildLogs(200, 'ctl-denied-');

        Test.startTest();
        System.runAs(standardUser) {
            try {
                GenericQueryController.getRecords(LOG_OBJECT, new List<String>{ 'Status__c' }, 10);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assertEquals(GenericTableConstants.ERR_UNKNOWN_OBJECT, e.getMessage());
            }
        }
        Test.stopTest();
    }
}
