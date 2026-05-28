// Immediately processes all Queued / RetryScheduled logs that are due now.
// Use this for ad-hoc testing or manual recovery without waiting for the scheduler.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents

Id jobId = Database.executeBatch(new IntegrationRetryBatch(), IntegrationConstants.EXECUTOR_CHUNK_SIZE);
System.debug('Batch job submitted: ' + jobId);
System.debug('Monitor progress under Setup → Apex Jobs or query AsyncApexJob WHERE Id = \'' + jobId + '\'');
