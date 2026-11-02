@isTest
private class GenericTableConstantsTest {

    @isTest
    static void testLimitsAndMessagesAreDefined() {
        Test.startTest();
        Integer maxRows = GenericTableConstants.MAX_ROWS;
        Integer defaultLimit = GenericTableConstants.DEFAULT_ROW_LIMIT;
        Integer maxFields = GenericTableConstants.MAX_FIELDS;
        Test.stopTest();

        System.assertEquals(500, maxRows);
        System.assertEquals(50, defaultLimit);
        System.assert(defaultLimit <= maxRows, 'Default limit must not exceed the maximum');
        System.assertEquals(30, maxFields);
        System.assertNotEquals(null, GenericTableConstants.ERR_INVALID_INPUT);
        System.assertNotEquals(null, GenericTableConstants.WARN_FIELDS_REMOVED);
    }
}
