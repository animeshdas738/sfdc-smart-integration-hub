public with sharing class IntegrationExecutor implements Queueable, Database.AllowsCallouts {
    private List<Id> logIds;

    public IntegrationExecutor(List<Id> logIds) {
        this.logIds = (logIds == null) ? new List<Id>() : logIds;
    }

    public void execute(QueueableContext ctx) {
        if (logIds.isEmpty()) return;

        List<Integration_Log__c> logs = [SELECT Id, Integration_Name__c, Payload_Id__c, Payload__c, Status__c, Attempts__c, Next_Attempt_At__c
                                         FROM Integration_Log__c
                                         WHERE Id IN :logIds
                                         FOR UPDATE];

        List<Integration_Log__c> toUpdate = new List<Integration_Log__c>();
        List<Integration_DLQ__c> toInsertDlq = new List<Integration_DLQ__c>();

        for (Integration_Log__c log : logs) {
            // skip if already processed successfully
            if (log.Status__c == IntegrationConstants.STATUS_SUCCESS) continue;

            // ensure it's ready to be processed
            Boolean ready = false;
            if (log.Status__c == IntegrationConstants.STATUS_QUEUED) ready = true;
            else if (log.Status__c == IntegrationConstants.STATUS_RETRYSCHEDULED) {
                if (log.Next_Attempt_At__c == null || log.Next_Attempt_At__c <= System.now()) ready = true;
            }
            if (!ready) continue;

            CalloutWrapper.CalloutResult cr = CalloutWrapper.postToNamedCredential(IntegrationConstants.DEFAULT_NAMED_CREDENTIAL, IntegrationConstants.DEFAULT_RESOURCE_PATH, log.Payload__c);
            ErrorMapper.ErrorResult er = ErrorMapper.classify(cr.statusCode, null);

            if (cr.statusCode != null && cr.statusCode >= 200 && cr.statusCode < 300) {
                log.Status__c = IntegrationConstants.STATUS_SUCCESS;
                log.Error_Code__c = String.valueOf(cr.statusCode);
                log.Error_Message__c = cr.body;
            } else if (er.category == ErrorMapper.ErrorCategory.TRANSIENT) {
                // compute next attempts with explicit types to avoid Decimal/Integer mismatches
                Decimal currentAttempts = log.Attempts__c;
                Integer attemptsInt = (currentAttempts == null) ? 1 : currentAttempts.intValue() + 1;
                // store attempts back as Decimal because Attempts__c is a Number field
                log.Attempts__c = Decimal.valueOf(attemptsInt);

                Integer maxAttempts = IntegrationConfig.getMaxAttempts();
                Integer baseDelay = IntegrationConfig.getBaseDelaySeconds();
                if (attemptsInt >= maxAttempts) {
                    log.Status__c = IntegrationConstants.STATUS_DEADLETTER;
                    Integration_DLQ__c dlq = new Integration_DLQ__c();
                    dlq.Integration_Log__c = log.Id;
                    dlq.Poison_Reason__c = (cr.body == null) ? 'Transient failures exceeded' : cr.body;
                    dlq.Raw_Payload__c = log.Payload__c;
                    toInsertDlq.add(dlq);
                } else {
                    log.Next_Attempt_At__c = RetryCalculator.computeNextAttempt(attemptsInt, baseDelay);
                    log.Status__c = IntegrationConstants.STATUS_RETRYSCHEDULED;
                    log.Error_Code__c = (cr.statusCode == null) ? 'EX' : String.valueOf(cr.statusCode);
                    log.Error_Message__c = cr.body;
                }
            } else {
                log.Status__c = IntegrationConstants.STATUS_DEADLETTER;
                Integration_DLQ__c dlq = new Integration_DLQ__c();
                dlq.Integration_Log__c = log.Id;
                dlq.Poison_Reason__c = (cr.body == null) ? 'Permanent failure' : cr.body;
                dlq.Raw_Payload__c = log.Payload__c;
                toInsertDlq.add(dlq);
            }

            toUpdate.add(log);
        }

        if (!toUpdate.isEmpty()) {
            try { update toUpdate; } catch (Exception ex) { /* best-effort update; errors should be handled/logged in production */ }
        }

        if (!toInsertDlq.isEmpty()) {
            try { insert toInsertDlq; } catch (Exception ex) { /* log / alert in production */ }
        }
    }
}
