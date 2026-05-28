// Registers IntegrationRetryScheduler as a recurring scheduled job.
// Run this ONCE to activate the retry mechanism in your org.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents
//
// Cron expression reference (Salesforce format: Seconds Minutes Hours Day Month DayOfWeek):
// NOTE: Salesforce does not support the / increment operator in Seconds or Minutes fields.
//       Use comma-separated values instead.
//   '0 0,5,10,15,20,25,30,35,40,45,50,55 * * * ?'  — every 5 minutes  (recommended)
//   '0 0,10,20,30,40,50 * * * ?'                    — every 10 minutes
//   '0 0 * * * ?'                                   — every hour (low-volume orgs)

String jobName = 'IntegrationRetryScheduler';
String cron    = '0 0,5,10,15,20,25,30,35,40,45,50,55 * * * ?';

// Abort any existing schedule with the same name to avoid duplicates
List<CronTrigger> existing = [
    SELECT Id, CronExpression, State
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
];

if (!existing.isEmpty()) {
    for (CronTrigger ct : existing) {
        System.abortJob(ct.Id);
        System.debug('Aborted existing job: ' + ct.Id + ' (was: ' + ct.CronExpression + ', state: ' + ct.State + ')');
    }
}

String scheduledJobId = System.schedule(jobName, cron, new IntegrationRetryScheduler());

System.debug('Scheduler registered  : ' + jobName);
System.debug('Cron expression       : ' + cron);
System.debug('Scheduled Job Id      : ' + scheduledJobId);
System.debug('Verify under Setup → Scheduled Jobs');
