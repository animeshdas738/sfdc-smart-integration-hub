/**
 * @description Trigger for Webhook_Event__e platform events.
 *              Async entry point for webhook processing.
 */
trigger WebhookEventTrigger on Webhook_Event__e (after insert) {
    WebhookEventHandler handler = new WebhookEventHandler();
    handler.handle(Trigger.new);
}
