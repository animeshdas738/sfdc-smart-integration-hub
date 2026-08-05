/**
 * @description Example webhook handler for testing purposes.
 *              Demonstrates the WebhookHandler interface implementation.
 */
public class TestWebhookHandler implements WebhookHandler {
    /**
     * @description Process test webhook payload.
     *              Parses JSON and creates/updates test objects.
     *
     * @param webhookLog The webhook log record
     * @param endpoint   The endpoint configuration
     * @return           WebhookResult with status and optional downstream event
     */
    public WebhookResult process(Webhook_Log__c webhookLog, Webhook_Endpoint__c endpoint) {
        try {
            // Parse payload
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(webhookLog.Payload__c);

            // Example: Extract event type and handle accordingly
            String eventType = (String) payload.get('event');
            if (String.isBlank(eventType)) {
                return new WebhookResult(WebhookResult.Status.FAILED, 'MISSING_EVENT_TYPE', 'Event type is required');
            }

            // Example: Create a test record or perform business logic
            // For this test, just return success
            WebhookResult result = new WebhookResult(WebhookResult.Status.SUCCESS);
            result.relatedRecordType = 'Account';

            // Optionally publish downstream Integration_Event__e
            // This would trigger the existing integration framework
            if (eventType == 'test.create') {
                result.integrationEvent = new Integration_Event__e(
                    Integration_Name__c = 'TestEventProcessing',
                    Endpoint_Id__c = endpoint.Integration_Endpoint__c,
                    Payload__c = JSON.serialize(payload),
                    Payload_Id__c = webhookLog.Webhook_Id__c,
                    Source_Object_Type__c = 'Webhook_Log__c',
                    Source_Record_Id__c = webhookLog.Id
                );
            }

            return result;

        } catch (JSONException je) {
            return new WebhookResult(
                WebhookResult.Status.FAILED,
                'JSON_PARSE_ERROR',
                'Failed to parse webhook payload: ' + je.getMessage()
            );
        } catch (Exception e) {
            return new WebhookResult(
                WebhookResult.Status.FAILED,
                'HANDLER_ERROR',
                'Unexpected error: ' + e.getMessage()
            );
        }
    }
}
