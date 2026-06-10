/**
 * @description Platform Event subscriber for Integration_Event__e. Translates each incoming event into
 *              an Integration_Log__c record via IntegrationService, auto-generating an idempotency key
 *              when the publisher omits Payload_Id__c. Errors are logged at ERROR level and do not
 *              prevent remaining events in the batch from being processed.
 */
public class IntegrationEventHandler {

    /**
     * @description Processes a batch of Integration_Event__e events delivered by the platform.
     *              Events missing Integration_Name__c, Endpoint_Id__c, or Payload__c are skipped with a
     *              warning. Each valid event is forwarded to IntegrationService.send.
     * @param events List of Integration_Event__e events from the platform trigger.
     */
    public static void handle(List<Integration_Event__e> events) {
        for (Integration_Event__e evt : events) {
            try {
                if (String.isBlank(evt.Integration_Name__c)
                        || String.isBlank(evt.Endpoint_Id__c)
                        || String.isBlank(evt.Payload__c)) {
                    System.debug(LoggingLevel.WARN,
                        'IntegrationEventHandler: skipping event — Integration_Name__c, Endpoint_Id__c, and Payload__c are all required.');
                    continue;
                }

                // Auto-generate a unique idempotency key when the publisher omits one
                String payloadId = String.isBlank(evt.Payload_Id__c)
                    ? 'evt-' + String.valueOf(System.now().getTime()) + '-' + Math.abs(Crypto.getRandomInteger())
                    : evt.Payload_Id__c;

                IntegrationService.send(
                    evt.Integration_Name__c,
                    payloadId,
                    evt.Payload__c,
                    (Id) evt.Endpoint_Id__c,
                    evt.Source_Object_Type__c,
                    evt.Source_Record_Id__c
                );

            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'IntegrationEventHandler: error processing event — ' + ex.getMessage()
                    + '\n' + ex.getStackTraceString());
            }
        }
    }
}
