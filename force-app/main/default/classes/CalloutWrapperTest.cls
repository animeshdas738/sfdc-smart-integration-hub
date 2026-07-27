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

    @isTest static void testGetRequest() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"data":"test"}'));
        Test.startTest();
        CalloutWrapper.CalloutResult result = CalloutWrapper.callEndpoint('TestCred', '/path', null, 'GET');
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals('{"data":"test"}', result.body);
    }

    @isTest static void testPostRequest() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(201, '{"id":"123"}'));
        Test.startTest();
        CalloutWrapper.CalloutResult result = CalloutWrapper.callEndpoint('TestCred', '/path', '{"name":"test"}', 'POST');
        Test.stopTest();

        System.assertEquals(201, result.statusCode);
        System.assertEquals('{"id":"123"}', result.body);
    }

    @isTest static void testPutRequest() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(200, '{"updated":true}'));
        Test.startTest();
        CalloutWrapper.CalloutResult result = CalloutWrapper.callEndpoint('TestCred', '/path', '{"name":"updated"}', 'PUT');
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals('{"updated":true}', result.body);
    }

    @isTest static void testDeleteRequest() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutGenerator(204, ''));
        Test.startTest();
        CalloutWrapper.CalloutResult result = CalloutWrapper.callEndpoint('TestCred', '/path', null, 'DELETE');
        Test.stopTest();

        System.assertEquals(204, result.statusCode);
    }
}
