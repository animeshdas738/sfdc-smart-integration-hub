/**
 * @description Interface for webhook handlers processing specific webhook types.
 *              Implementations transform external webhook payloads into Integration_Event__e
 *              or perform Salesforce operations directly.
 */
public interface WebhookHandler {
    /**
     * Process a webhook payload.
     *
     * @param webhookLog    The Webhook_Log__c record (includes Payload__c)
     * @param endpoint      The Webhook_Endpoint__c configuration
     * @return              WebhookResult with status and optional Integration_Event__e to publish
     * @throws              Exception if processing fails (caught and logged by trigger)
     */
    WebhookResult process(Webhook_Log__c webhookLog, Webhook_Endpoint__c endpoint);
}
