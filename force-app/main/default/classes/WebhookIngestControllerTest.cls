/**
 * @description Tests for WebhookIngestController and related webhook infrastructure.
 */
@IsTest
private class WebhookIngestControllerTest {

    @IsTest
    static void testHandleWebhookSuccess() {
        // Setup: Create test Webhook_Endpoint__c
        Webhook_Endpoint__c endpoint = new Webhook_Endpoint__c(
            Name = 'Test_Endpoint',
            Webhook_Path__c = 'test',
            Source_System__c = 'TestSystem',
            Signature_Algorithm__c = 'None',
            Handler_Class_Name__c = 'TestWebhookHandler',
            Is_Active__c = true
        );
        insert endpoint;

        // Prepare test request
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/webhooks/v1/test';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"event":"test.created","data":{"id":"123"}}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Execute
        Test.startTest();
        WebhookIngestController.handleWebhook();
        Test.stopTest();

        // Assert
        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('accepted', responseBody.get('status'));

        // Verify Webhook_Log__c created
        List<Webhook_Log__c> logs = [SELECT Id, Status__c FROM Webhook_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals('Received', logs[0].Status__c);
    }

    @IsTest
    static void testHandleWebhookDuplicate() {
        // Setup
        Webhook_Endpoint__c endpoint = new Webhook_Endpoint__c(
            Name = 'Test_Endpoint',
            Webhook_Path__c = 'test',
            Source_System__c = 'TestSystem',
            Signature_Algorithm__c = 'None',
            Handler_Class_Name__c = 'TestWebhookHandler',
            Is_Active__c = true
        );
        insert endpoint;

        String payload = '{"event":"test.created"}';
        String webhookId = 'wh_20260805_abc123';

        // Create existing log
        Webhook_Log__c existingLog = new Webhook_Log__c(
            Webhook_Endpoint__c = endpoint.Id,
            Webhook_Id__c = webhookId,
            Payload__c = payload,
            Payload_Hash__c = 'abc123',
            Received_At__c = Datetime.now(),
            Status__c = 'Success',
            HTTP_Status_Sent__c = 200
        );
        insert existingLog;

        // Prepare duplicate request
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/webhooks/v1/test';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(payload);
        req.headers.put('X-Webhook-Id', webhookId);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Execute
        Test.startTest();
        WebhookIngestController.handleWebhook();
        Test.stopTest();

        // Assert: should still return 200 for duplicate
        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('accepted', responseBody.get('status'));
    }

    @IsTest
    static void testHandleWebhookEndpointNotFound() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/webhooks/v1/nonexistent';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"data":"test"}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        WebhookIngestController.handleWebhook();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('invalid_endpoint', responseBody.get('error'));
    }

    @IsTest
    static void testHandleWebhookEndpointInactive() {
        Webhook_Endpoint__c endpoint = new Webhook_Endpoint__c(
            Name = 'Inactive_Endpoint',
            Webhook_Path__c = 'inactive',
            Source_System__c = 'TestSystem',
            Signature_Algorithm__c = 'None',
            Handler_Class_Name__c = 'TestWebhookHandler',
            Is_Active__c = false
        );
        insert endpoint;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/webhooks/v1/inactive';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"data":"test"}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        WebhookIngestController.handleWebhook();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('endpoint_inactive', responseBody.get('error'));
    }

    @IsTest
    static void testHandleWebhookPayloadTooLarge() {
        Webhook_Endpoint__c endpoint = new Webhook_Endpoint__c(
            Name = 'Test_Endpoint',
            Webhook_Path__c = 'test',
            Source_System__c = 'TestSystem',
            Signature_Algorithm__c = 'None',
            Handler_Class_Name__c = 'TestWebhookHandler',
            Is_Active__c = true,
            Max_Payload_Size_Bytes__c = 100
        );
        insert endpoint;

        String largePayload = 'x'.repeat(200);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/webhooks/v1/test';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(largePayload);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        WebhookIngestController.handleWebhook();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('payload_too_large', responseBody.get('error'));
    }

    @IsTest
    static void testSignatureValidation() {
        // This test verifies that signature validation rejects unsigned requests
        Webhook_Endpoint__c endpoint = new Webhook_Endpoint__c(
            Name = 'Signed_Endpoint',
            Webhook_Path__c = 'signed',
            Source_System__c = 'TestSystem',
            Signature_Algorithm__c = 'HMAC_SHA256',
            Signature_Header_Name__c = 'X-Webhook-Signature',
            Handler_Class_Name__c = 'TestWebhookHandler',
            Is_Active__c = true
        );
        insert endpoint;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/webhooks/v1/signed';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"data":"test"}');
        // Missing signature header
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        WebhookIngestController.handleWebhook();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('signature_mismatch', responseBody.get('error'));
    }
}
