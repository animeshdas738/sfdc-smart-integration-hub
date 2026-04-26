# Salesforce Generic Integration Framework

This document describes a reusable, opinionated integration framework for Salesforce that can be used across any integration project. It focuses on robustness, observability, and operational friendliness. Key capabilities:

- Retry logic with exponential backoff + jitter
- Error classification and routing (transient, permanent, poison)
- Persistent logging & dead-letter queue (DLQ)
- Dashboard for operators to monitor, filter, and act on failed messages
- Secure outgoing calls via Named Credentials and Auth Providers

## Goals and non-goals

Goals:
- Provide a standard pattern for synchronous and asynchronous integrations.
- Surface failures clearly to operators and make remediation simple.
- Ensure at-least-once delivery with idempotency safeguards.

Non-goals:
- Replace all 3rd-party ESBs — rather, integrate cleanly with them.
- Implement a large UI-heavy ops console inside Salesforce; prefer lightweight LWC and reports/dashboards.

---

## High-level architecture

Components:

- Caller (External system or internal Apex job)
- Integration Service Layer (Apex services + Platform Events)
- Transport Adapter (HTTP callouts using Named Credentials or Apex-based adapters for JMS/SFTP)
- Retry / Orchestration Engine (Apex queueable/scheduler + Platform Events replay)
- Persistence: Custom Objects for logs, DLQ and checkpoints
- Operator UI: Lightning Web Component (LWC) + Salesforce Reports & Dashboard

Sequence diagrams (simplified):

1. Synchronous outbound call
   - Caller -> IntegrationService.makeCall(payload)
   - IntegrationService validates and inserts a Log record with status=Queued
   - IntegrationService executes an HTTP callout via Named Credential
   - On success: update Log status=Success
   - On transient failure: enqueue retry record and update Log
   - On permanent failure: write to DLQ and notify operators

2. Asynchronous inbound via Platform Event
   - External system publishes into Salesforce (Platform Event) or calls REST
   - Trigger/Subscriber -> validates -> IntegrationService.processEvent
   - IntegrationService uses the same retry and DLQ logic as outbound flows

---

## Contracts

- Input: JSON payloads (example):

  {
    "integrationName": "AccountSync",
    "payloadId": "UUID",
    "payload": { /* domain object */ },
    "meta": { "source": "ERP", "receivedAt": "2026-04-26T12:34:56Z" }
  }

- Outputs:
  - Success: HTTP 200 / Platform Event ACK + Log entry (Status = Success)
  - Failure (transient): Log updated (Status=RetryScheduled) and retry scheduled
  - Failure (permanent): DLQ entry created (Status = DeadLetter) and operator notified

- Idempotency:
  - Each operation must include a stable payloadId and the system must check for an existing successful processing record before applying changes.

---

## Data model (suggested)

Create these Custom Objects (API names given):

- Integration_Log__c
  - Name (Auto) or Integration_Name__c (Text)
  - Payload_Id__c (Text, external id)
  - Status__c (Picklist: Queued, InProgress, Success, RetryScheduled, DeadLetter, Failed)
  - Attempts__c (Number)
  - Next_Attempt_At__c (DateTime)
  - Error_Code__c (Text)
  - Error_Message__c (Long Text Area)
  - Payload__c (Long Text Area) or Files for large payloads
  - Related_Record_Id__c (Text) – optional link to created/updated Salesforce record
  - Source__c (Text)
  - CreatedByIntegration__c (Checkbox) – to indicate system-created

- Integration_DLQ__c (for poison messages)
  - Link to Integration_Log__c
  - Poison_Reason__c (Long Text Area)
  - Raw_Payload__c (Long Text Area)
  - Operator_Notes__c (Long Text Area)

Indexes: create a text index on Payload_Id__c and Next_Attempt_At__c for efficient querying by scheduler.

---

## Retry strategy

Contract:
- Max attempts: configurable per integration (default 5)
- Strategy: exponential backoff with jitter:
  - baseDelay = 30 seconds
  - delay = baseDelay * (2 ^ (attempts - 1))
  - jitter = random(0, baseDelay) seconds
  - nextAttempt = now + delay + jitter
- Retryable errors: network timeouts, 429, 5xx from remote, transient DNS errors
- Non-retryable errors: 4xx client errors (other than 429), schema validation failures

Implementation notes:
- Store attempts in `Integration_Log__c.Attempts__c` and compute `Next_Attempt_At__c`.
- Scheduler (Apex Scheduled class) runs every minute to pick logs where Status in (RetryScheduled, Queued) and Next_Attempt_At__c <= now.
- Scheduler enqueues Queueable jobs to perform callouts (to respect limits). For high-volume integrations, use a batchable Apex job to chunk records.
- After exceeding max attempts, move record to DLQ (Integration_DLQ__c) and set status=DeadLetter.

Edge cases:
- Clock skew / timezone: use UTC and DateTime.nowGmt()
- Bulk retries: respect platform limits (use Batchable with appropriate batch size)

---

## Error handling and classification

Error categories:
- Transient: network, rate limit, 5xx errors -> retry
- Permanent: 4xx invalid payload, authentication errors -> fail without retry
- Poison: repeatedly failing due to data issues -> moved to DLQ after max attempts

Handling flow:
1. Capture full HTTP response (code, headers, body) and exception stack in `Integration_Log__c`.
2. Map response codes to categories using an error mapping utility.
3. For transient errors: compute next attempt and set Status=RetryScheduled.
4. For permanent errors: create DLQ record and Status=DeadLetter.
5. For poison messages: after max attempts create DLQ and notify.

Operator notification:
- Send Platform Event or Chatter post to specific user/group when DLQ entry created.
- Optionally integrate with external alerting (Slack/PagerDuty) via webhook.

---

## Logging and observability

Primary store: `Integration_Log__c`

Fields to capture per attempt (if possible):
- Timestamp
- Attempt number
- Duration
- HTTP status
- Error code/message
- Response body (truncated to safe size)

Retention and archiving:
- Keep recent 90 days online; archive older entries to external storage or CSVs.
- Consider external syslog/ELK for very high-volume logging.

Dashboard options:
1. Salesforce Report + Dashboard
   - Create reports grouped by Integration_Name__c, Status__c, and by error type.
   - Use dashboard charts for failure rate, average attempts, top error codes.

2. LWC Operations Panel
   - Lightweight LWC that queries `Integration_Log__c` via Apex controller.
   - Filters: integrationName, status, date range, payloadId, error code.
   - Actions: view payload, retry now (manual), move to DLQ, add operator notes.

Quick operator features:
- Bulk retry selected records (invoke an Apex Batchable job with the selected logs)
- Single-record replay (re-send the payload after edits)
- Escalation button that creates a Case or posts to Chatter/Slack

---

## Security and credentials

- Use Named Credentials + Auth Providers for external APIs. Avoid storing secrets in custom metadata values.
- For per-tenant credentials, use Named Credential with a dynamic URL and an Auth Provider where possible.
- Ensure the Integration service runs in a System context or a dedicated Integration User with minimal permissions.
- Sanitize logs to avoid PII in `Integration_Log__c` or store sensitive fields encrypted. Use Platform Encryption for sensitive payloads.

---

## Implementation patterns and Apex snippets

1. Idempotency check (pseudo-Apex):

    Integration_Log__c existing = [SELECT Id, Status__c FROM Integration_Log__c WHERE Payload_Id__c = :payloadId AND Status__c = 'Success' LIMIT 1];
    if(existing != null) {
        // Already processed, return success
    }

2. Scheduling next retry (pseudo-Apex):

    Integer attempts = log.Attempts__c == null ? 0 : Integer.valueOf(log.Attempts__c);
    Integer maxAttempts = 5;
    Datetime now = Datetime.nowGmt();
    Long baseSeconds = 30;
    Long delay = baseSeconds * Math.pow(2, attempts);
    Long jitter = Math.mod(Crypto.getRandomInteger(), baseSeconds);
    log.Next_Attempt_At__c = now.addSeconds(delay + jitter);

3. Callout wrapper using Named Credential (pseudo-Apex):

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:My_Named_Credential' + '/resourcePath');
    req.setMethod('POST');
    req.setBody(payloadJson);

    Http http = new Http();
    HTTPResponse res = http.send(req);

    // map response codes, log, and decide retry

---

## Testing strategy

- Unit tests for Apex utilities: error mapper, retry calculator, idempotency checker.
- Mock HTTP callouts in tests using HttpCalloutMock implementations.
- Integration tests in scratch orgs with staging external endpoints.
- Load testing using external tools (if volume > 100 TPS)

---

## CI/CD and deployment notes

- Keep Apex code and metadata in `force-app/main/default` and use SFDX/CLI for deployments.
- Validate with runAllTestsInOrg for full regression; prefer running relevant test suites in CI.
- Use feature toggles (Custom Metadata) to enable/disable retries or change strategy per integration.

---

## Operational runbooks (short)

Common tasks:
- Manually retry failed entries: select and click "Retry" in LWC -> executes Batchable job.
- Reprocess DLQ: inspect payload, correct data, and replay via UI.
- Tune retry parameters: update Custom Metadata for baseDelay and maxAttempts.

Alerting:
- Send Platform Event on DeadLetter creation; subscribe to forward to Slack or PagerDuty.

---

## Next steps (recommended incremental work)

1. Implement `Integration_Log__c` and `Integration_DLQ__c` in an unlocked package or metadata files.
2. Implement core Apex service: Validation, Idempotent persistence, Callout wrapper, Error mapper.
3. Implement scheduler and queueable/batch classes for retries.
4. Build a minimal LWC for operators and a report/dashboard.

---

## Appendix: Useful Custom Metadata and settings

- Integration_Settings__mdt: fields for baseDelaySeconds, maxAttempts, defaultNamedCredential, notifyChatterGroupId
- Integration_Error_Map__mdt: map of HTTP codes to Retryable flag and severity


---

End of document.
