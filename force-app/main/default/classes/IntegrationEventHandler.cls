public class IntegrationEventHandler {

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
