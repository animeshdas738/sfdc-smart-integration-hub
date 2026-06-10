@isTest
private class CalloutWrapperTest {

    @isTest static void testSuccessfulCallout() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"ok":true}'));
        Test.startTest();
        CalloutWrapper.CalloutResult result = CalloutWrapper.postToNamedCredential('TestCred', '/path', '{}');
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals('{"ok":true}', result.body);
    }

    @isTest static void testCalloutExceptionReturnsNullStatus() {
        // No mock registered — http.send() throws a CalloutException in test context,
        // exercising the catch branch (lines 29-31) and returning null statusCode.
        Test.startTest();
        CalloutWrapper.CalloutResult result = CalloutWrapper.postToNamedCredential('TestCred', '/path', '{}');
        Test.stopTest();

        System.assertEquals(null, result.statusCode);
        System.assertNotEquals(null, result.body);
    }
}
