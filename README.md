# SFDC Smart Integration Hub

A reusable, production-ready outbound integration framework for Salesforce. Built on Apex Queueable, Platform Events, and Custom Metadata, it provides reliable HTTP callouts with automatic retry, exponential backoff, dead-letter queuing, and a Lightning Web Component dashboard — all without any middleware or external dependencies.

---

## Table of Contents

- [High-Level Design](#high-level-design)
  - [Architecture Overview](#architecture-overview)
  - [Component Breakdown](#component-breakdown)
  - [Data Model](#data-model)
  - [Error Handling and Retry Strategy](#error-handling-and-retry-strategy)
- [Implementation Guide](#implementation-guide)
  - [Prerequisites](#prerequisites)
  - [Deployment](#deployment)
  - [Configuration](#configuration)
  - [Sending Integrations](#sending-integrations)
  - [Monitoring and Operations](#monitoring-and-operations)
- [Project Structure](#project-structure)
- [Development](#development)

---

## High-Level Design

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        TRIGGER LAYER                                │
│                                                                     │
│   Direct Apex Call                  Platform Event Publisher        │
│   IntegrationService.send(...)      publish(Integration_Event__e)   │
└────────────────┬───────────────────────────────┬────────────────────┘
                 │                               │
                 │                 ┌─────────────▼──────────────┐
                 │                 │  IntegrationEventHandler   │
                 │                 │  (Platform Event Trigger)  │
                 └─────────────────┴────────────────────────────┘
                                               │
                              ┌────────────────▼─────────────────┐
                              │         IntegrationService        │
                              │  • Idempotency check              │
                              │  • Creates Integration_Log__c     │
                              │  • Enqueues IntegrationExecutor   │
                              └────────────────┬─────────────────┘
                                               │
                              ┌────────────────▼─────────────────┐
                              │       IntegrationExecutor         │
                              │       (Queueable + Callouts)      │
                              │  • Resolves Named Credential      │
                              │  • Calls CalloutWrapper           │
                              │  • Evaluates ErrorMapper          │
                              └─────┬──────────────────┬─────────┘
                                    │                  │
                         ┌──────────▼────┐    ┌────────▼────────────┐
                         │    SUCCESS    │    │       FAILURE        │
                         │  Log updated  │    │  ErrorMapper decides │
                         └───────────────┘    └────────┬────────────┘
                                                       │
                                          ┌────────────┴────────────┐
                                          │                         │
                                   TRANSIENT                   PERMANENT
                              (5xx, 429, timeout)            (4xx client error)
                                          │                         │
                              ┌───────────▼──────────┐   ┌─────────▼────────┐
                              │  RetryCalculator      │   │  Integration_DLQ │
                              │  Exponential backoff  │   │  Dead-letter     │
                              │  + random jitter      │   │  record created  │
                              └───────────┬──────────┘   └──────────────────┘
                                          │
                              ┌───────────▼──────────────────────────┐
                              │    IntegrationRetryScheduler          │
                              │    (Scheduled Apex, runs hourly)      │
                              │    → IntegrationRetryBatch            │
                              │    → re-enqueues IntegrationExecutor  │
                              └───────────────────────────────────────┘
```

### Component Breakdown

| Component | Type | Responsibility |
|---|---|---|
| `IntegrationService` | Apex Class | Entry point. Idempotency check, log creation, job enqueue. |
| `IntegrationExecutor` | Queueable Apex | Performs the HTTP callout, processes the response, updates the log. |
| `IntegrationEventHandler` | Apex Trigger Handler | Consumes `Integration_Event__e` platform events and delegates to `IntegrationService`. |
| `CalloutWrapper` | Apex Class | Executes `HttpRequest` against a Named Credential. Returns a `CalloutResult`. |
| `ErrorMapper` | Apex Class | Classifies HTTP status codes and exceptions as `TRANSIENT` or `PERMANENT`. |
| `RetryCalculator` | Apex Class | Computes next retry timestamp using exponential backoff with random jitter. |
| `IntegrationConfig` | Apex Class | Reads `Integration_Settings__mdt` for `maxAttempts` and `baseDelaySeconds`. |
| `IntegrationRetryScheduler` | Schedulable Apex | Runs on a schedule; launches `IntegrationRetryBatch` to pick up due retries. |
| `IntegrationRetryBatch` | Batch Apex | Queries `RETRYSCHEDULED` logs past their `Next_Attempt_At__c` and re-enqueues them. |
| `MappingHelper` | Apex Class | Applies token templates (`{{Key}}`) and declarative JSON mapping rules to transform payloads. |
| `MappingPreviewController` | Apex Controller | LWC backend for live-previewing mapping output in the UI. |
| `IntegrationDashboardController` | Apex Controller | LWC backend serving log statistics and recent activity to the dashboard. |
| `integrationDashboard` | LWC | Operational dashboard showing integration health, log summary, and DLQ alerts. |
| `mappingPreview` | LWC | Interactive tool to preview field mapping rules before deploying them. |

### Data Model

```
Integration_Settings__mdt          Integration_Endpoint__c
┌──────────────────────┐           ┌──────────────────────────┐
│ Max_Attempts__c       │           │ Named_Credential__c       │
│ Base_Delay_Seconds__c │           │ Endpoint_Path__c          │
└──────────────────────┘           └──────────┬───────────────┘
         read by                              │ lookup
   IntegrationConfig                          │
                                   ┌──────────▼───────────────┐
                                   │   Integration_Log__c      │
                                   │                          │
                                   │ Integration_Name__c       │
                                   │ Payload_Id__c  (idempotency key)
                                   │ Payload__c                │
                                   │ Status__c                 │
                                   │   QUEUED → IN_PROGRESS    │
                                   │   → SUCCESS               │
                                   │   → RETRYSCHEDULED        │
                                   │   → DEADLETTER            │
                                   │ Attempts__c               │
                                   │ Next_Attempt_At__c        │
                                   │ Error_Code__c             │
                                   │ Error_Message__c          │
                                   │ Duration_ms__c            │
                                   │ Response_Body__c          │
                                   │ Source__c                 │
                                   │ Related_Record_Id__c      │
                                   └──────────┬───────────────┘
                                              │ lookup (on failure)
                                   ┌──────────▼───────────────┐
                                   │   Integration_DLQ__c      │
                                   │                          │
                                   │ Poison_Reason__c          │
                                   │ Raw_Payload__c            │
                                   └──────────────────────────┘

Integration_Event__e  (Platform Event)
┌──────────────────────────┐
│ Integration_Name__c       │
│ Endpoint_Id__c            │
│ Payload__c                │
│ Payload_Id__c             │
│ Source_Object_Type__c     │
│ Source_Record_Id__c       │
└──────────────────────────┘
```

### Error Handling and Retry Strategy

| HTTP Status | Classification | Outcome |
|---|---|---|
| `200–299` | Success | Log set to `SUCCESS` |
| `429`, `500–599` | Transient | Schedule retry with exponential backoff |
| `400–428`, `430–499` | Permanent | Move directly to DLQ |
| Exception / no status | Transient | Schedule retry |

**Retry formula:** `delay = baseDelaySeconds × 2^attempts + randomJitter(0..baseDelaySeconds)`

Defaults (overridable via `Integration_Settings__mdt`): `maxAttempts = 5`, `baseDelaySeconds = 30`.

After `maxAttempts` transient failures, the log is marked `DEADLETTER` and a `Integration_DLQ__c` record is created with the poison reason and raw payload.

---

## Implementation Guide

### Prerequisites

- Salesforce CLI (`sf` or `sfdx`) installed
- A Salesforce org (scratch org, sandbox, or developer edition)
- Node.js 18+ (for linting/testing toolchain)
- VS Code with the [Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) (recommended)

### Deployment

**1. Clone the repository**

```bash
git clone https://github.com/<your-org>/sfdc-smart-integration-hub.git
cd sfdc-smart-integration-hub
npm install
```

**2. Authenticate to your org**

```bash
# Scratch org (recommended for development)
sf org create scratch --definition-file config/project-scratch-def.json --alias smart-hub --set-default

# Or authorize an existing sandbox/dev org
sf org login web --alias smart-hub --set-default
```

**3. Deploy the metadata**

```bash
sf project deploy start --target-org smart-hub
```

**4. Assign the permission set**

```bash
sf org assign permset --name Integration_Ops --target-org smart-hub
```

**5. Schedule the retry job** (run once in Anonymous Apex or Developer Console)

```apex
String jobId = System.schedule(
    'Integration Retry Scheduler',
    '0 0 * * * ?',          // every hour
    new IntegrationRetryScheduler()
);
```

### Configuration

#### Named Credentials

Each external endpoint must have a Named Credential in Salesforce Setup (`Setup → Named Credentials`).

- Create a Named Credential for each external system (e.g., `Gemini_API`).
- Set the authentication method as required by the external service.
- Note the **API Name** — this is what you will reference in `Integration_Endpoint__c.Named_Credential__c`.

An `External Credential` (`Gemini_External_Auth`) is included in the package for OAuth-style auth setups.

#### Integration Endpoint Records

Create one `Integration_Endpoint__c` record per target system:

| Field | Description |
|---|---|
| `Named_Credential__c` | API name of the Named Credential |
| `Endpoint_Path__c` | Relative URL path appended to the credential base URL |

#### Custom Metadata (Integration_Settings__mdt)

Tune retry behavior without code changes via `Setup → Custom Metadata Types → Integration Settings`:

| Field | Default | Description |
|---|---|---|
| `Max_Attempts__c` | `5` | Maximum retry attempts before a message is dead-lettered |
| `Base_Delay_Seconds__c` | `30` | Base delay for exponential backoff (seconds) |

### Sending Integrations

#### Option 1 — Direct Apex call

Use `IntegrationService.send()` from any Apex context (trigger, flow-launched action, batch, etc.):

```apex
// Minimal call
IntegrationService.send('MyIntegration', recordId, JSON.serialize(payload));

// With explicit endpoint
IntegrationService.send('MyIntegration', recordId, JSON.serialize(payload), endpointId);

// Full call with source traceability
IntegrationService.send(
    'MyIntegration',        // integration name (used for filtering/dashboards)
    recordId,               // idempotency key — duplicate payloads with SUCCESS are skipped
    JSON.serialize(payload),
    endpointId,             // Integration_Endpoint__c record Id
    'Account',              // source object type (optional)
    accountId               // source record Id (optional)
);
```

#### Option 2 — Platform Event (decoupled / cross-process)

Publish an `Integration_Event__e` from any Apex, Flow, or external process. The trigger invokes `IntegrationEventHandler` which calls `IntegrationService` automatically.

```apex
Integration_Event__e evt = new Integration_Event__e(
    Integration_Name__c   = 'MyIntegration',
    Endpoint_Id__c        = endpointId,
    Payload__c            = JSON.serialize(payload),
    Payload_Id__c         = recordId,               // omit to auto-generate
    Source_Object_Type__c = 'Account',
    Source_Record_Id__c   = accountId
);
EventBus.publish(evt);
```

#### Payload Mapping

Use `MappingHelper` to transform source data before sending:

```apex
// Token template
String template = '{"name":"{{AccountName}}","region":"{{Region}}"}';
Map<String, Object> ctx = new Map<String, Object>{ 'AccountName' => acc.Name, 'Region' => 'APAC' };
String payload = MappingHelper.applyTemplate(template, ctx);

// Declarative JSON mapping rules (stored on the endpoint or passed inline)
String rules = '[{"source":"Account.Name","target":"accountName"},{"source":"constant:v1","target":"version"}]';
String payload = MappingHelper.applyDeclarative(rules, ctx);
```

Use the `mappingPreview` LWC component to test mapping rules interactively before deploying them.

### Monitoring and Operations

#### Integration Dashboard

Add the `integrationDashboard` LWC component to any Lightning App page, Record page, or Home page via the Lightning App Builder. It displays:

- Integration success/failure rates
- Recent log activity
- DLQ alerts for messages requiring manual intervention

#### Integration Operations App

A dedicated Lightning App (`Integration_Ops`) is included. Open it from the App Launcher to access the dashboard, log list views, DLQ records, and endpoint configuration in one place.

#### Log Status Reference

| Status | Meaning | Action Required |
|---|---|---|
| `QUEUED` | Awaiting execution | None — executor will pick it up shortly |
| `SUCCESS` | Delivered successfully | None |
| `RETRYSCHEDULED` | Transient failure; retry pending | None — scheduler will retry automatically |
| `DEADLETTER` | Permanently failed | Review `Integration_DLQ__c` record; fix root cause and reprocess if needed |

#### Reprocessing a DLQ message

1. Identify the `Integration_DLQ__c` record and copy `Raw_Payload__c`.
2. Fix the root cause (bad endpoint config, auth issue, data problem).
3. Call `IntegrationService.send()` with the original payload and a new idempotency key (or reuse the original if the SUCCESS log was never written).

---

## Project Structure

```
sfdc-smart-integration-hub/
├── force-app/main/default/
│   ├── classes/
│   │   ├── IntegrationService.cls          # Public entry point
│   │   ├── IntegrationExecutor.cls         # Queueable HTTP executor
│   │   ├── IntegrationEventHandler.cls     # Platform event consumer
│   │   ├── IntegrationConfig.cls           # Custom metadata reader
│   │   ├── CalloutWrapper.cls              # HTTP callout abstraction
│   │   ├── ErrorMapper.cls                 # HTTP status classifier
│   │   ├── RetryCalculator.cls             # Exponential backoff
│   │   ├── MappingHelper.cls               # Payload transformation
│   │   ├── IntegrationRetryScheduler.cls   # Scheduled retry launcher
│   │   ├── IntegrationRetryBatch.cls       # Batch retry processor
│   │   ├── IntegrationAttemptsHelper.cls   # Attempt counter
│   │   ├── IntegrationConstants.cls        # Shared constants
│   │   ├── MappingPreviewController.cls    # LWC controller
│   │   ├── IntegrationDashboardController.cls
│   │   └── *Test.cls / Mock*.cls           # Test classes and mocks
│   ├── lwc/
│   │   ├── integrationDashboard/           # Ops dashboard component
│   │   └── mappingPreview/                 # Mapping rule preview tool
│   ├── objects/
│   │   ├── Integration_Endpoint__c/        # Endpoint configuration
│   │   ├── Integration_Log__c/             # Execution log
│   │   ├── Integration_DLQ__c/             # Dead-letter queue
│   │   ├── Integration_Event__e/           # Platform event
│   │   └── Integration_Settings__mdt/      # Config custom metadata
│   ├── triggers/                           # Platform event trigger
│   ├── namedCredentials/                   # Named & external credentials
│   ├── permissionsets/                     # Integration_Ops permission set
│   └── applications/                       # Integration_Ops Lightning App
├── scripts/
│   ├── apex/                               # Anonymous Apex utilities
│   └── soql/                               # SOQL query scripts
├── config/                                 # Scratch org definition
├── docs/                                   # Additional documentation
├── sfdx-project.json
├── jest.config.js
└── eslint.config.js
```

---

## Development

**Run Apex tests**

```bash
sf apex run test --target-org smart-hub --code-coverage --result-format human
```

**Run LWC unit tests**

```bash
npm test
```

**Lint**

```bash
npm run lint
```

**Open org**

```bash
sf org open --target-org smart-hub
```
