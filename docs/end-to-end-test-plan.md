# End-to-end Test Plan — SFDC Smart Integration Hub

This document describes manual steps and automated checks to validate the end-to-end integration framework in a Salesforce scratch org (or sandbox). Follow these steps to verify callouts, retries, DLQ behavior, mapping, and operator UX.

## Prerequisites
- SFDX CLI installed and authenticated (see README).
- A scratch org or sandbox with API access and the repository metadata deployed.
- Named Credential created (API name matches `IntegrationConstants.DEFAULT_NAMED_CREDENTIAL` or create an `Integration_Endpoint__c` record with a correct `Named_Credential__c`).
- Remote endpoint for testing (can use httpbin.org or a mock service). In tests we use HttpCalloutMock.
- Admin user with `Integration_Ops` permission set assigned for operator flows.

## Quick checklist
- [ ] Deploy metadata to a scratch org
- [ ] Ensure `Integration_Endpoint__c` record exists
- [ ] Create sample Integration_Log__c entries or use `IntegrationService.send` to create them
- [ ] Run scheduler / batch to process retries
- [ ] Verify DLQ creation and operator actions

---

## 1) Deploy repository to a scratch org
1. Create and push a scratch org (example):

```bash
sfdx force:org:create -s -f config/project-scratch-def.json -a integration-test
sfdx force:source:push -u integration-test
sfdx force:org:open -u integration-test
```

2. Assign the permission set and create test data if needed.

```bash
sfdx force:user:permset:assign -n Integration_Ops -u integration-test
```

---

## 2) Seed an Integration Endpoint record (example)
Create an `Integration_Endpoint__c` record via the UI or use sfdx data commands. Example JSON for `sfdx force:data:record:create`:

```bash
sfdx force:data:record:create -s Integration_Endpoint__c -v "External_System_Name__c='Test API' Named_Credential__c='My_Named_Credential' Endpoint_Path__c='/anything' Default_Max_Attempts__c=3 Default_Base_Delay_Seconds__c=10" -u integration-test
```

Note: `Named_Credential__c` must exist or use a generic test value and rely on `HttpCalloutMock` during Apex tests.

---

## 2.1) Free external services you can use for testing

If you don't have a dedicated downstream endpoint or want to avoid licensing costs for test services, the following free endpoints work well for manual and automated E2E validation:

- httpbin.org (free public HTTP request & response service)
	- Useful endpoints: `https://httpbin.org/status/500` (returns 500), `https://httpbin.org/status/200` (returns 200), `https://httpbin.org/anything` (echoes request)
	- Example: create an `Integration_Endpoint__c` that uses a Named Credential pointing to `https://httpbin.org` and set `Endpoint_Path__c` to `/status/500` to simulate transient failures.

- webhook.site (free request inspection and replay)
	- Provides a unique URL where you can see all requests, headers and bodies. Good for testing real payloads and replaying them from the UI.
	- Steps: visit https://webhook.site to get a temporary URL (no account required), paste that URL into a Named Credential or `Integration_Endpoint__c` record, then trigger `IntegrationService.send` and inspect the request on webhook.site.

Security note: these services are public; avoid sending PII or production secrets to them. Use anonymized or synthetic data for tests.

---

## 3) Manual run: synchronous send and mapping preview
1. Open App Launcher -> Integration Ops app.
2. Open the Mapping Preview LWC (place it on a page or App Page first).
3. Provide a template or declarative rules and sample JSON context and click Preview. Verify output matches expectations.
4. Use `IntegrationService.send('TestInt', 'pid-manual-1', '{"name":"ok"}')` in Execute Anonymous (Developer Console) or an Apex REST client. Verify a new `Integration_Log__c` row with Status = Success (if endpoint returns 200) or RetryScheduled/DLQ otherwise.

---

## 4) Scheduler/Batch validation (transient failures and retries)
1. Create a log via `IntegrationService.send` where the mock endpoint returns 500 (or configure the Named Credential to a URL that returns 500).
2. Run the scheduler manually (either by invoking the schedulable class in Execute Anonymous or by running the batch):

```apex
// Execute Anonymous
IntegrationRetryScheduler s = new IntegrationRetryScheduler();
s.execute(null);
```

Or run batch directly:

```apex
Database.executeBatch(new IntegrationRetryBatch(), 25);
```

3. Confirm `Integration_Log__c` Attempts increments and `Next_Attempt_At__c` is set. Repeat until `Default_Max_Attempts__c` is reached for that endpoint and verify a `Integration_DLQ__c` record is created and `Status__c` = DeadLetter.

---

## 5) DLQ and operator actions
- Use the Integration Ops app -> Integration DLQ tab to inspect DLQ entries.
- For a DLQ entry, open details, review `Poison_Reason__c` and `Raw_Payload__c`.
- Use the operator UI (or Execute Anonymous) to replay (manual retry): run `IntegrationService.send` with the same payload or an edited payload and confirm a new `Integration_Log__c` is created with a new status.

---

## 6) Automated unit test run
Run all Apex tests locally via SFDX:

```bash
sfdx force:apex:test:run -u integration-test --wait 10 --resultformat human
```

Look for green tests. The repo includes unit tests for `MappingHelper`, `IntegrationExecutor`, `IntegrationRetryScheduler` and other core classes.

---

## 7) Troubleshooting
- If tests fail due to named credential resolution, ensure `CalloutWrapper` has the test-friendly behavior (repo includes `Test.isRunningTest()` fallback).
- If SOQL datetime errors occur, ensure `IntegrationRetryScheduler` uses bind variables and the batchable is deployed.
- Use debug logs and the `Integration_Log__c` records to trace attempts and errors.

---

## 8) Next steps and hardening
- Add end-to-end integration tests that run in CI using a real or simulated downstream endpoint.
- Add monitoring and alerting for when DLQ entries exceed thresholds.
- Add mapping validation admin pages to catch template errors before they reach production.

---

## Appendix — Useful commands
- Push metadata: `sfdx force:source:push`
- Run all tests: `sfdx force:apex:test:run --wait 10 --resultformat human`
- Open scratch org: `sfdx force:org:open -u integration-test`


---

End of test plan.
