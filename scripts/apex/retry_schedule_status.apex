// Checks the current status of the IntegrationRetryScheduler scheduled job.
// Also shows recently completed retry batch jobs.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents

String jobName = 'IntegrationRetryScheduler';

// --- Scheduled job status ---
List<CronTrigger> scheduled = [
    SELECT Id, CronExpression, State, NextFireTime, PreviousFireTime, TimesTriggered
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
];

if (scheduled.isEmpty()) {
    System.debug('No scheduled job found for: ' + jobName);
    System.debug('Run retry_schedule.apex to register it.');
} else {
    for (CronTrigger ct : scheduled) {
        System.debug('--- Scheduled Job ---');
        System.debug('Id               : ' + ct.Id);
        System.debug('State            : ' + ct.State);
        System.debug('Cron             : ' + ct.CronExpression);
        System.debug('Next Fire Time   : ' + ct.NextFireTime);
        System.debug('Previous Fire    : ' + ct.PreviousFireTime);
        System.debug('Times Triggered  : ' + ct.TimesTriggered);
    }
}

// --- Recent batch job runs ---
List<AsyncApexJob> recentBatches = [
    SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedDate, CompletedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'IntegrationRetryBatch'
    ORDER BY CreatedDate DESC
    LIMIT 5
];

if (recentBatches.isEmpty()) {
    System.debug('No IntegrationRetryBatch jobs found yet.');
} else {
    System.debug('--- Last ' + recentBatches.size() + ' Retry Batch Run(s) ---');
    for (AsyncApexJob j : recentBatches) {
        System.debug('Job Id     : ' + j.Id);
        System.debug('Status     : ' + j.Status);
        System.debug('Processed  : ' + j.JobItemsProcessed + ' / ' + j.TotalJobItems);
        System.debug('Errors     : ' + j.NumberOfErrors);
        System.debug('Started    : ' + j.CreatedDate);
        System.debug('Completed  : ' + j.CompletedDate);
        System.debug('---');
    }
}

// --- Pending retry log counts ---
Datetime now = System.now();
Integer dueNow = [
    SELECT COUNT() FROM Integration_Log__c
    WHERE (Status__c = 'Queued' OR Status__c = 'RetryScheduled')
    AND (Next_Attempt_At__c = NULL OR Next_Attempt_At__c <= :now)
];
Integer pendingFuture = [
    SELECT COUNT() FROM Integration_Log__c
    WHERE Status__c = 'RetryScheduled'
    AND Next_Attempt_At__c > :now
];

System.debug('--- Retry Log Summary ---');
System.debug('Due for retry now  : ' + dueNow);
System.debug('Scheduled (future) : ' + pendingFuture);
