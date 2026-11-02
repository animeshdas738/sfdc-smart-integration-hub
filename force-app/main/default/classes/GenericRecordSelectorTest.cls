@isTest
private class GenericRecordSelectorTest {

    private static final String LOG_OBJECT = 'Integration_Log__c';

    @isTest
    static void testQueryTextUsesValidatedNamesUserModeAndBoundLimit() {
        Test.startTest();
        String soql = GenericRecordSelector.buildQueryString(LOG_OBJECT, new List<String>{ 'Id', 'Status__c' });
        Test.stopTest();

        System.assertEquals(
            'SELECT Id, Status__c FROM Integration_Log__c WITH USER_MODE LIMIT :rowLimit',
            soql);
    }

    @isTest
    static void testSelectRecordsAppliesBoundRowLimit() {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Integer i = 0; i < 200; i++) {
            logs.add(new Integration_Log__c(
                Integration_Name__c = 'GenericTableTest',
                Payload_Id__c = 'sel-bulk-' + i,
                Status__c = 'Success'
            ));
        }
        insert logs;

        Test.startTest();
        List<SObject> records = GenericRecordSelector.selectRecords(
            LOG_OBJECT, new List<String>{ 'Id', 'Status__c' }, 150);
        Test.stopTest();

        System.assertEquals(150, records.size(), 'The row limit should be applied');
    }

    @isTest
    static void testInjectionAttemptInFieldNameIsRejected() {
        Test.startTest();
        try {
            GenericRecordSelector.buildQueryString(LOG_OBJECT, new List<String>{ 'Id', 'Status__c; DELETE Account' });
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_INVALID_IDENTIFIER, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testInvalidObjectNameIsRejected() {
        Test.startTest();
        try {
            GenericRecordSelector.buildQueryString('Account WHERE Id != null --', new List<String>{ 'Id' });
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals(GenericTableConstants.ERR_INVALID_IDENTIFIER, e.getMessage());
        }
        Test.stopTest();
    }
}
