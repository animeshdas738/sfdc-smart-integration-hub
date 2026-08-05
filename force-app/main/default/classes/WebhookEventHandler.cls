/**
 * @description Handles asynchronous processing of Webhook_Event__e platform events.
 *              Invokes registered handlers and manages error handling, status updates, and downstream events.
 */
public class WebhookEventHandler {
    /**
     * @description Process webhook events by invoking registered handlers.
     *
     * @param events List of Webhook_Event__e to process
     */
    public void handle(List<Webhook_Event__e> events) {
        List<Webhook_Log__c> logsToUpdate = new List<Webhook_Log__c>();
        List<Integration_Event__e> integrationsToPublish = new List<Integration_Event__e>();

        // Fetch all referenced Webhook_Log__c and Webhook_Endpoint__c records
        Set<Id> logIds = new Set<Id>();
        Set<Id> endpointIds = new Set<Id>();

        for (Webhook_Event__e evt : events) {
            logIds.add(evt.Webhook_Log_Id__c);
            endpointIds.add(evt.Webhook_Endpoint_Id__c);
        }

        Map<Id, Webhook_Log__c> logMap = new Map<Id, Webhook_Log__c>(
            [SELECT Id, Payload__c, Webhook_Endpoint__c FROM Webhook_Log__c WHERE Id IN :logIds]
        );

        Map<Id, Webhook_Endpoint__c> endpointMap = new Map<Id, Webhook_Endpoint__c>(
            [SELECT Id, Handler_Class_Name__c, Integration_Endpoint__c FROM Webhook_Endpoint__c WHERE Id IN :endpointIds]
        );

        // Process each event
        for (Webhook_Event__e evt : events) {
            try {
                Webhook_Log__c log = logMap.get(evt.Webhook_Log_Id__c);
                Webhook_Endpoint__c endpoint = endpointMap.get(evt.Webhook_Endpoint_Id__c);

                if (log == null || endpoint == null) {
                    continue;
                }

                // Update log to Processing
                log.Status__c = 'Processing';
                Datetime processStartTime = Datetime.now();

                // Instantiate and invoke handler
                Type handlerType = Type.forName(evt.Handler_Class_Name__c);
                if (handlerType == null) {
                    throw new TypeException('Handler class not found: ' + evt.Handler_Class_Name__c);
                }

                WebhookHandler processorHandler = (WebhookHandler) handlerType.newInstance();
                WebhookResult result = processorHandler.process(log, endpoint);

                // Map result status to Webhook_Log__c status
                if (result.status == WebhookResult.Status.SUCCESS) {
                    log.Status__c = 'Success';
                } else if (result.status == WebhookResult.Status.SKIPPED) {
                    log.Status__c = 'Skipped';
                } else {
                    log.Status__c = 'Failed';
                }

                log.Error_Code__c = result.errorCode;
                log.Error_Message__c = result.errorMessage;
                log.Related_Record_Id__c = result.relatedRecordId;
                log.Related_Record_Type__c = result.relatedRecordType;
                log.Processed_At__c = Datetime.now();
                log.Processing_Duration_Ms__c = log.Processed_At__c.getTime() - log.Received_At__c.getTime();

                // If handler provided Integration_Event__e, enqueue for publish
                if (result.integrationEvent != null) {
                    integrationsToPublish.add(result.integrationEvent);
                }

                logsToUpdate.add(log);

            } catch (Exception e) {
                Webhook_Log__c log = logMap.get(evt.Webhook_Log_Id__c);
                if (log != null) {
                    log.Status__c = 'Failed';
                    log.Error_Code__c = 'HANDLER_EXCEPTION';
                    log.Error_Message__c = e.getMessage() + '\n' + e.getStackTraceString();
                    log.Processed_At__c = Datetime.now();
                    log.Processing_Duration_Ms__c = log.Processed_At__c.getTime() - log.Received_At__c.getTime();
                    logsToUpdate.add(log);
                }
            }
        }

        // Update webhook logs
        if (!logsToUpdate.isEmpty()) {
            update logsToUpdate;
        }

        // Publish downstream integration events
        if (!integrationsToPublish.isEmpty()) {
            EventBus.publish(integrationsToPublish);
        }
    }
}
