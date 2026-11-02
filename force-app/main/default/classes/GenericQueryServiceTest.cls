@isTest
private class GenericQueryServiceTest {

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
            Alias = 'gtest',
            Email = 'gtest' + uniqueSuffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'GenericTableTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'gtest' + uniqueSuffix + '@example.com.test'
        );
        insert standardUser;
        return standardUser;
    }

    @isTest
    static void testBulkRecordsReturnColumnsAndRows() {
        insert buildLogs(200, 'svc-bulk-');

        Test.startTest();
        GenericQueryService.GenericQueryResult result = GenericQueryService.getRecords(
            LOG_OBJECT, new List<String>{ 'Status__c', 'Integration_Name__c' }, 200);
        Test.stopTest();

        System.assertEquals(200, result.rows.size(), 'All 200 records should be returned');
        System.assertEquals(2, result.columns.size(), 'Only the requested fields should be columns');
        System.assertEquals(
            Schema.Integration_Log__c.Status__c.getDescribe().getLabel(),
            result.columns[0].label);
        System.assertEquals('Status__c', result.columns[0].fieldName);
        System.assertEquals('text', result.columns[0].type, 'Picklist should map to text');
        System.assertEquals('Success', result.rows[0].get('Status__c'));
        System.assertEquals(0, result.warnings.size());
    }

    @isTest
    static void testIdIsReturnedInRowsButNotAsColumn() {
        insert buildLogs(200, 'svc-id-');

        Test.startTest();
        GenericQueryService.GenericQueryResult result = GenericQueryService.getRecords(
            LOG_OBJECT, new List<String>{ 'Status__c' }, 10);
        Test.stopTest();

        System.assertEquals(1, result.columns.size());
        System.assert(result.rows[0].containsKey('Id'), 'Rows must carry Id as the key field');
        System.assertNotEquals(null, result.rows[0].get('Id'));
    }

    @isTest
    static void testNumberDateAndTextColumnTypes() {
        insert buildLogs(200, 'svc-types-');

        Test.startTest();
        GenericQueryService.GenericQueryResult result = GenericQueryService.getRecords(
            LOG_OBJECT, new List<String>{ 'Duration_ms__c', 'Next_Attempt_At__c', 'Payload_Id__c' }, 10);
        Test.stopTest();

        System.assertEquals('number', result.columns[0].type);
        System.assertEquals('date', result.columns[1].type);
        System.assertEquals('text', result.columns[2].type);
    }

    @isTest
    static void testNullAndZeroRowLimitUseDefault() {
        insert buildLogs(200, 'svc-default-');

        Test.startTest();
        GenericQueryService.GenericQueryResult nullLimit = GenericQueryService.getRecords(
            LOG_OBJECT, new List<String>{ 'Status__c' }, null);
        GenericQueryService.GenericQueryResult zeroLimit = GenericQueryService.getRecords(
            LOG_OBJECT, new List<String>{ 'Status__c' }, 0);
        Test.stopTest();

        System.assertEquals(GenericTableConstants.DEFAULT_ROW_LIMIT, nullLimit.rows.size());
        System.assertEquals(GenericTableConstants.DEFAULT_ROW_LIMIT, zeroLimit.rows.size());
    }

    @isTest
    static void testRowLimitAboveMaximumIsCapped() {
        // More records than MAX_ROWS so the cap is actually reached
        insert buildLogs(GenericTableConstants.MAX_ROWS + 1, 'svc-cap-');

        Test.startTest();
        GenericQueryService.GenericQueryResult result = GenericQueryService.getRecords(
            LOG_OBJECT, new List<String>{ 'Status__c' }, 10000);
        Test.stopTest();

        System.assertEquals(GenericTableConstants.MAX_ROWS, result.rows.size());
    }

    @isTest
    static void testDuplicateFieldsAreIgnored() {
        insert buildLogs(200, 'svc-dup-');

        Test.startTest();
        GenericQueryService.GenericQueryResult result = GenericQueryService.getRecords(
            LOG_OBJECT, new List<String>{ 'Status__c', 'status__c' }, 5);
        Test.stopTest();

        System.assertEquals(1, result.columns.size());
    }

    @isTest
    static void testUnknownObjectIsRejected() {
        Test.startTest();
        try {
            GenericQueryService.getRecords('No_Such_Object__c', new List<String>{ 'Id' }, 10);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_UNKNOWN_OBJECT, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUnknownFieldIsRejected() {
        Test.startTest();
        try {
            GenericQueryService.getRecords(LOG_OBJECT, new List<String>{ 'Not_A_Field__c' }, 10);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_UNKNOWN_FIELD, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testRelationshipFieldIsRejected() {
        Test.startTest();
        try {
            GenericQueryService.getRecords(LOG_OBJECT, new List<String>{ 'Integration_Endpoint__r.Name' }, 10);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_RELATIONSHIP_FIELD, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testAddressFieldIsRejected() {
        Test.startTest();
        try {
            GenericQueryService.getRecords('Contact', new List<String>{ 'MailingAddress' }, 10);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_UNSUPPORTED_FIELD, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testBlankFieldIsRejected() {
        Test.startTest();
        try {
            GenericQueryService.getRecords(LOG_OBJECT, new List<String>{ '  ' }, 10);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_BLANK_FIELD, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testEmptyAndTooManyFieldsAreRejected() {
        List<String> tooMany = new List<String>();
        for (Integer i = 0; i <= GenericTableConstants.MAX_FIELDS; i++) {
            tooMany.add('Status__c');
        }

        Test.startTest();
        try {
            GenericQueryService.getRecords(LOG_OBJECT, new List<String>(), 10);
            System.assert(false, 'Expected IllegalArgumentException for empty field list');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_INVALID_INPUT, e.getMessage());
        }
        try {
            GenericQueryService.getRecords(LOG_OBJECT, tooMany, 10);
            System.assert(false, 'Expected IllegalArgumentException for too many fields');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_TOO_MANY_FIELDS, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUserWithoutObjectAccessIsRejected() {
        User standardUser = createStandardUser();
        insert buildLogs(200, 'svc-denied-');

        Test.startTest();
        System.runAs(standardUser) {
            try {
                GenericQueryService.getRecords(LOG_OBJECT, new List<String>{ 'Status__c' }, 10);
                System.assert(false, 'Expected IllegalArgumentException for a user without object access');
            } catch (IllegalArgumentException e) {
                System.assertEquals(GenericTableConstants.ERR_UNKNOWN_OBJECT, e.getMessage());
            }
        }
        Test.stopTest();
    }
}
