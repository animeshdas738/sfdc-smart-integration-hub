@isTest
private class IntegrationAttemptsHelperTest {

    @isTest static void testGetAttemptsNullLog() {
        System.assertEquals(0, IntegrationAttemptsHelper.getAttempts(null));
    }

    @isTest static void testGetAttemptsNullField() {
        Integration_Log__c log = new Integration_Log__c();
        System.assertEquals(0, IntegrationAttemptsHelper.getAttempts(log));
    }

    @isTest static void testGetAttemptsValue() {
        Integration_Log__c log = new Integration_Log__c(Attempts__c = 3);
        System.assertEquals(3, IntegrationAttemptsHelper.getAttempts(log));
    }

    @isTest static void testSetAttemptsNull() {
        // Covers the attempts == null branch (line 18) which clears the field
        Integration_Log__c log = new Integration_Log__c(Attempts__c = 5);
        IntegrationAttemptsHelper.setAttempts(log, null);
        System.assertEquals(null, log.Attempts__c);
    }

    @isTest static void testSetAttemptsNullLog() {
        // Covers the null-log guard — should not throw
        IntegrationAttemptsHelper.setAttempts(null, 3);
        System.assert(true, 'setAttempts on null log must not throw');
    }

    @isTest static void testIncrementAttempts() {
        Integration_Log__c log = new Integration_Log__c(Attempts__c = 2);
        Integer next = IntegrationAttemptsHelper.incrementAttempts(log);
        System.assertEquals(3, next);
        System.assertEquals(3, IntegrationAttemptsHelper.getAttempts(log));
    }
}
