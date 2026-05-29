// Diagnoses Integration Log records stuck in Queued status.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents

Set<Id> logIds = new Set<Id>{
    'a02g5000008PG3NAAW',
    '00ag5000003b3jZAAQ'
};

// --- 1. Inspect the log records ---
List<Integration_Log__c> logs = [
    SELECT Id, Name, Status__c, Integration_Name__c, Payload_Id__c,
           Attempts__c, Next_Attempt_At__c, Error_Code__c, Error_Message__c,
           CreatedDate, LastModifiedDate,
           Integration_Endpoint__c,
           Integration_Endpoint__r.Named_Credential__c,
           Integration_Endpoint__r.Endpoint_Path__c,
           Integration_Endpoint__r.Active__c
    FROM Integration_Log__c
    WHERE Id IN :logIds
];

System.debug('=== Integration Logs ===');
for (Integration_Log__c log : logs) {
    System.debug('---');
    System.debug('Id                  : ' + log.Id + ' (' + log.Name + ')');
    System.debug('Status              : ' + log.Status__c);
    System.debug('Integration Name    : ' + log.Integration_Name__c);
    System.debug('Payload Id          : ' + log.Payload_Id__c);
    System.debug('Attempts            : ' + log.Attempts__c);
    System.debug('Next Attempt At     : ' + log.Next_Attempt_At__c);
    System.debug('Error Code          : ' + log.Error_Code__c);
    System.debug('Error Message       : ' + log.Error_Message__c);
    System.debug('Created             : ' + log.CreatedDate);
    System.debug('Last Modified       : ' + log.LastModifiedDate);
    System.debug('Endpoint Id         : ' + log.Integration_Endpoint__c);
    if (log.Integration_Endpoint__r != null) {
        System.debug('Named Credential    : ' + log.Integration_Endpoint__r.Named_Credential__c);
        System.debug('Endpoint Path       : ' + log.Integration_Endpoint__r.Endpoint_Path__c);
        System.debug('Endpoint Active     : ' + log.Integration_Endpoint__r.Active__c);
    } else {
        System.debug('ISSUE: No Integration_Endpoint__c linked — executor will use default constants.');
    }
}

// --- 2. Check for Queueable jobs (IntegrationExecutor) spawned around log creation time ---
Datetime since = DateTime.now().addHours(-24);
List<AsyncApexJob> queueableJobs = [
    SELECT Id, Status, JobType, ApexClass.Name, CreatedDate, CompletedDate,
           NumberOfErrors, ExtendedStatus
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'IntegrationExecutor'
      AND CreatedDate >= :since
    ORDER BY CreatedDate DESC
    LIMIT 20
];

System.debug('=== IntegrationExecutor Queueable Jobs (last 24 h) ===');
if (queueableJobs.isEmpty()) {
    System.debug('ISSUE FOUND: No IntegrationExecutor jobs found in the last 24 hours.');
    System.debug('This means System.enqueueJob() was never called, or the job failed to enqueue.');
} else {
    for (AsyncApexJob job : queueableJobs) {
        System.debug('Job Id          : ' + job.Id);
        System.debug('Status          : ' + job.Status);
        System.debug('Created         : ' + job.CreatedDate);
        System.debug('Completed       : ' + job.CompletedDate);
        System.debug('Errors          : ' + job.NumberOfErrors);
        System.debug('Extended Status : ' + job.ExtendedStatus);
        System.debug('---');
    }
}

// --- 3. Check for any Apex jobs that failed with errors ---
List<AsyncApexJob> failedJobs = [
    SELECT Id, Status, ApexClass.Name, ExtendedStatus, CreatedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name IN ('IntegrationExecutor', 'IntegrationRetryBatch', 'IntegrationRetryScheduler')
      AND Status IN ('Failed', 'Aborted')
      AND CreatedDate >= :since
    ORDER BY CreatedDate DESC
    LIMIT 10
];

System.debug('=== Failed/Aborted Integration Jobs (last 24 h) ===');
if (failedJobs.isEmpty()) {
    System.debug('No failed/aborted jobs found.');
} else {
    for (AsyncApexJob job : failedJobs) {
        System.debug('FAILED Job: ' + job.ApexClass.Name + ' | ' + job.Status + ' | ' + job.ExtendedStatus);
    }
}

// --- 4. Check governor limit: active queueable jobs right now ---
List<AsyncApexJob> activeJobs = [
    SELECT Id, Status, ApexClass.Name, CreatedDate
    FROM AsyncApexJob
    WHERE Status IN ('Queued', 'Processing', 'Preparing')
      AND JobType = 'Queueable'
    ORDER BY CreatedDate DESC
    LIMIT 10
];

System.debug('=== Currently Active Queueable Jobs ===');
if (activeJobs.isEmpty()) {
    System.debug('No active queueable jobs.');
} else {
    for (AsyncApexJob j : activeJobs) {
        System.debug(j.ApexClass.Name + ' | ' + j.Status + ' | created: ' + j.CreatedDate);
    }
}

// --- 5. Check if logs were created in a context that blocks enqueueJob ---
// If logs are Queued AND no executor was spawned, the enqueueJob likely threw inside IntegrationService
// and was silently caught. Check if the logs have an Error_Message__c from the catch block.
System.debug('=== Enqueue Failure Check ===');
List<Integration_Log__c> deadLetterFromEnqueue = [
    SELECT Id, Name, Status__c, Error_Message__c
    FROM Integration_Log__c
    WHERE Id IN :logIds
];
if (!deadLetterFromEnqueue.isEmpty()) {
    System.debug('ISSUE FOUND: Logs were moved to DeadLetter because enqueueJob failed:');
    for (Integration_Log__c l : deadLetterFromEnqueue) {
        System.debug('  ' + l.Name + ' — ' + l.Error_Message__c);
    }
} else {
    System.debug('No enqueue-failure error messages found on the logs.');
}

System.debug('=== Diagnosis Complete ===');
System.debug('Next step: if no executor jobs were found, run retry_run_now.apex to manually trigger IntegrationRetryBatch.');
