trigger IntegrationEventTrigger on Integration_Event__e (after insert) {
    IntegrationEventHandler.handle(Trigger.new);
}
