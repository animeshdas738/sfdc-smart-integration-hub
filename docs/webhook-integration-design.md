# Webhook Integration Design Document

**Document Version:** 1.0  
**Date:** 2026-08-05  
**Status:** Design Review  
**Author:** Animesh Das

---

## Executive Summary

This document describes the design for extending the **Salesforce Generic Integration Framework** to support reliable, secure webhook consumption from external applications. The webhook layer enables Salesforce to act as a webhook receiver, accept payloads from third-party systems (Stripe, Shopify, GitHub, etc.), validate authenticity, and reliably process them through the existing integration pipeline.

**Key deliverables:**
- Unified webhook ingestion REST API
- Webhook registry and routing mechanism
- Signature validation with HMAC-SHA256
- Deduplication and idempotency guards
- Persistent webhook tracking and observability
- Operational dashboard and audit trail

---

## Goals and Non-Goals

### Goals
1. **Reliable inbound webhook consumption** – Accept webhooks, respond immediately, process asynchronously
2. **Signature verification** – Validate webhook authenticity (HMAC-SHA256, RSA-SHA256, or none)
3. **Deduplication** – Prevent duplicate processing when external systems retry
4. **Traceability** – Link webhook ingestion to downstream integration logs for end-to-end visibility
5. **Extensibility** – Pluggable handler pattern for different webhook sources
6. **Operational visibility** – Dashboard showing webhook volumes, errors, and signature failures
7. **Security** – Secure key storage via Named Credentials, no secrets in custom metadata

### Non-Goals
1. Replace message brokers (Kafka, RabbitMQ) – this is for webhook ingestion, not pub/sub
2. Implement bi-directional event sync – focus is inbound consumption
3. Handle webhook retries for Salesforce callouts – that's covered by existing framework
4. Custom webhook transformation DSL – handlers are Apex classes, not YAML configs

---

## Architecture Overview

### High-Level Flow

```
External System (Stripe, Shopify, etc.)
        │
        │ POST /services/apexrest/webhooks/v1/inbound
        │ Headers: X-Webhook-Signature: sha256=...
        │ Body: { "event": "order.created", "data": {...} }
        ▼
┌─────────────────────────────────────────┐
│   Webhook Ingestion Controller (REST)   │  ← Respond 200 OK immediately
└─────────────────────────────────────────┘
        │
        ├─► Route lookup (Webhook_Endpoint__c)
        │
        ├─► Signature validation (HMAC-SHA256)
        │
        ├─► Deduplication check (Webhook_Log__c by Webhook_Id__c)
        │
        ├─► Persist Webhook_Log__c (Status = Received)
        │
        └─► Publish Webhook_Event__e (async processing)
                │
                ▼
        ┌──────────────────────────┐
        │ Webhook Event Trigger    │
        │ (after insert)           │
        └──────────────────────────┘
                │
                ├─► Update Webhook_Log__c (Status = Processing)
                │
                ├─► Invoke registered handler (WebhookHandler interface)
                │
                ├─► Transform to Integration_Event__e
                │
                └─► Publish Integration_Event__e
                    (hands off to existing retry/DLQ logic)
                        │
                        ▼
                    ┌──────────────────────────┐
                    │ Integration Service      │
                    │ (existing framework)     │
                    └──────────────────────────┘
```

### Component Breakdown

| Component | Purpose | Scope |
|---|---|---|
| **WebhookIngestController** | REST endpoint accepting webhook POST | New |
| **WebhookSignatureValidator** | HMAC/RSA signature verification | New |
| **WebhookRouter** | Route incoming payloads to endpoints | New |
| **WebhookHandler (interface)** | Contract for webhook processors | New |
| **WebhookEventTrigger** | Async entry point to processing | New |
| **Webhook_Endpoint__c** | Registry of webhook sources | New |
| **Webhook_Log__c** | Audit trail for received webhooks | New |
| **Integration Framework** | Existing outbound + retry logic | Existing (reused) |

---

## Data Model

### 1. Webhook_Endpoint__c (Custom Object)

Registry of external webhook sources. Defines routing, validation rules, and handlers.

```
Object API Name: Webhook_Endpoint__c
Label: Webhook Endpoint

Fields:
├── Name (Text, 255)
│   Example: "Stripe_Events", "Shopify_Orders", "GitHub_Pushes"
│
├── Webhook_Path__c (Text, 255) [Unique]
│   Example: "stripe", "shopify", "github"
│   Used in URL routing: /services/apexrest/webhooks/v1/{Webhook_Path__c}
│   Required: Yes
│
├── Source_System__c (Text, 255)
│   Example: "Stripe", "Shopify Inc.", "GitHub"
│   Friendly name for operators
│   Required: Yes
│
├── Description__c (Long Text Area)
│   Operator documentation and notes
│   Required: No
│
├── Is_Active__c (Checkbox)
│   If false, endpoint rejects incoming webhooks (400 Bad Request)
│   Required: No (default: true)
│
├── Signature_Algorithm__c (Picklist)
│   Values: 
│     - "HMAC_SHA256" (Stripe, Shopify, GitHub, etc.)
│     - "RSA_SHA256" (optional for future use)
│     - "None" (for testing only; disabled in production)
│   Required: Yes
│
├── Signature_Header_Name__c (Text, 255)
│   HTTP header containing signature
│   Examples: "X-Webhook-Signature", "X-Hub-Signature-256"
│   Required: Yes
│
├── Signing_Key_Named_Credential__c (Text, 255)
│   Name of Named Credential storing the webhook secret
│   Example: "Stripe_Webhook_Secret"
│   Required: Yes (unless Algorithm = "None")
│
├── Handler_Class_Name__c (Text, 255)
│   Fully qualified Apex class implementing WebhookHandler interface
│   Example: "StripeWebhookHandler", "ShopifyWebhookHandler"
│   Validation: Must be instantiable and implement WebhookHandler
│   Required: Yes
│
├── Max_Payload_Size_Bytes__c (Number)
│   Maximum allowed webhook payload size (default: 1MB = 1048576)
│   Required: No (default: 1048576)
│
├── Retry_Enabled__c (Checkbox)
│   If true, failed webhooks retry via existing Integration_Log__c retry logic
│   Required: No (default: true)
│
├── Integration_Endpoint__c (Lookup to Integration_Endpoint__c)
│   Optional link; if set, handler publishes to this endpoint
│   Allows downstream integration configuration
│   Required: No
│
├── Owner (Lookup to User)
│   Operational owner for alert routing
│   Required: No
│
├── Last_Webhook_Received_At__c (DateTime)
│   Auto-updated timestamp; helps monitor webhook liveness
│   Required: No (read-only)
│
├── Last_Webhook_Failed_At__c (DateTime)
│   Auto-updated on processing errors; alerts if stale
│   Required: No (read-only)
```

**Indexes:** Unique index on Webhook_Path__c; text index on Source_System__c and Is_Active__c.

---

### 2. Webhook_Log__c (Custom Object)

Audit trail and deduplication store for received webhooks. Mirrors Integration_Log__c but for inbound flows.

```
Object API Name: Webhook_Log__c
Label: Webhook Log
Record Types: Webhook (main record type)

Fields:
├── Name (Auto-generated)
│   Format: "WH-{date}{sequence}" (e.g., "WH-20260805001")
│   Generated by system
│
├── Webhook_Endpoint__c (Master-Detail to Webhook_Endpoint__c)
│   Link to source endpoint
│   Required: Yes
│   Roll-up summary: Count of logs per endpoint
│
├── Webhook_Id__c (Text, 255) [External ID, Unique]
│   Idempotency key: hash(payload) + timestamp + sequence
│   Example: "evt_1A2B3C4D5E" (from external system) or generated
│   Used for deduplication
│   Required: Yes
│   Validation: Unique constraint; queries use this for fast lookups
│
├── Source_Event_Id__c (Text, 255)
│   External system's event ID for correlation
│   Example: Stripe: "evt_1A2B3C4D5E", GitHub: "12345678"
│   Helps correlate with external audit logs
│   Required: No
│
├── Payload__c (Long Text Area, 131072)
│   Full webhook body (JSON or XML)
│   Truncated if > 131KB; full payload stored in Files if needed
│   Required: Yes
│
├── Payload_Hash__c (Text, 64)
│   SHA256 hash of raw payload (hex-encoded)
│   Used for integrity checking and deduplication verification
│   Example: "a1b2c3d4e5f6..."
│   Required: Yes
│
├── Received_At__c (DateTime)
│   Server timestamp when webhook was received
│   Set in controller before processing
│   Required: Yes
│
├── Status__c (Picklist)
│   Values:
│     - "Received"      ← Initial status after ingestion
│     - "Processing"    ← Handler invoked, awaiting result
│     - "Success"       ← Downstream integration_log succeeded
│     - "Failed"        ← Handler threw exception
│     - "Skipped"       ← Duplicate (Webhook_Id__c already exists)
│     - "ValidationFailed"  ← Signature invalid, payload invalid
│     - "DeadLetter"    ← Moved to DLQ after max attempts
│   Required: Yes (default: "Received")
│
├── HTTP_Status_Sent__c (Number)
│   HTTP status code returned to caller
│   Values: 200 (success), 400 (validation), 401 (auth), 500 (error)
│   Required: Yes
│
├── Attempt__c (Number)
│   Count of processing attempts (retry count)
│   Incremented by retry scheduler
│   Required: No (default: 1)
│
├── Max_Attempts__c (Number)
│   Max retry attempts (from Integration_Endpoint__c or default)
│   Required: No (default: 5)
│
├── Error_Code__c (Text, 255)
│   Classification of error (e.g., "SIGNATURE_INVALID", "HANDLER_EXCEPTION")
│   Used for dashboarding and alerting
│   Required: No
│
├── Error_Message__c (Long Text Area)
│   Full exception message and stack trace (first 4096 chars)
│   Required: No
│
├── Signature_Header_Value__c (Text, 1024)
│   Signature from X-Webhook-Signature header (for audit)
│   Required: No (truncated; full value in Files)
│
├── Signature_Valid__c (Checkbox)
│   true = HMAC matched, false = mismatch
│   Null = not yet validated (no signature algorithm)
│   Required: No
│
├── Is_Duplicate__c (Checkbox)
│   true if Webhook_Id__c already processed (Status != Received)
│   Helps identify retry floods from external system
│   Required: No (default: false)
│
├── Related_Integration_Log__c (Lookup to Integration_Log__c)
│   Links to downstream integration log if handler published Integration_Event__e
│   Enables tracing webhook → integration → external call
│   Required: No
│
├── Related_Record_Id__c (Text, 18)
│   Salesforce record ID created/updated by handler
│   Example: Account, Opportunity, Custom object
│   Required: No
│
├── Related_Record_Type__c (Text, 255)
│   Salesforce object API name of related record
│   Example: "Account", "Opportunity", "Case"
│   Required: No
│
├── Processed_At__c (DateTime)
│   Timestamp when handler completed (success or failure)
│   Required: No
│
├── Processing_Duration_Ms__c (Number)
│   Time in milliseconds from Received_At to Processed_At
│   Used for performance monitoring
│   Required: No
│
├── Retry_Scheduled_At__c (DateTime)
│   Next scheduled retry (if Status = "RetryScheduled")
│   Required: No
│
├── Operator_Notes__c (Long Text Area)
│   Free-form notes from ops team (e.g., "Manual replay on 2026-08-06")
│   Required: No
│
├── Metadata__c (Long Text Area)
│   JSON of extra context: request headers, IP, user agent, etc.
│   Example: {"ip": "192.0.2.1", "user_agent": "Stripe/v1"}
│   Required: No
│
└── CreatedByIntegration__c (Checkbox)
    true = system-created, false = manual test/replay
    Required: No (default: true)
```

**Indexes:**
- Unique index: Webhook_Id__c
- Composite index: Webhook_Endpoint__c + Status__c + Received_At__c (for dashboard queries)
- Text index: Source_Event_Id__c (for correlation searches)
- Datetime index: Retry_Scheduled_At__c (for scheduler)

**Roll-up summaries:**
- Webhook_Endpoint__c: Count of all logs, count of failed logs, max Attempt__c

---

### 3. Webhook_Event__e (Platform Event)

Decouples webhook ingestion from async processing. Enables replay and flow-based extensibility.

```
Event API Name: Webhook_Event__e

Fields:
├── Webhook_Log_Id__c (Text, 18)
│   Reference to Webhook_Log__c record
│   Required: Yes
│
├── Webhook_Endpoint_Id__c (Text, 18)
│   Reference to Webhook_Endpoint__c record
│   Required: Yes
│
├── Payload__c (Long Text Area, 131072)
│   Full webhook payload (JSON or XML)
│   Required: Yes
│
├── Webhook_Id__c (Text, 255)
│   Idempotency key (copied from Webhook_Log__c)
│   Required: Yes
│
├── Handler_Class_Name__c (Text, 255)
│   Handler to invoke (from Webhook_Endpoint__c)
│   Required: Yes
│
└── Source_Event_Id__c (Text, 255)
    External event ID for correlation
    Required: No
```

**Publish Behavior:** `PublishAfterCommit` – ensures Webhook_Log__c is persisted before event fires.

---

## API Contracts

### 1. Webhook Ingestion REST Endpoint

**URL:** `/services/apexrest/webhooks/v1/{endpoint_path}`

**Method:** POST

**Request Headers:**
```
Content-Type: application/json
X-Webhook-Signature: sha256=<hmac_hex>
X-Webhook-Id: evt_... (optional; used if provided)
```

**Request Body (JSON):**
```json
{
  "event": "order.created",
  "data": {
    "id": "12345",
    "amount": 99.99,
    "customer": "acme"
  }
}
```

**Success Response (200 OK):**
```json
{
  "status": "accepted",
  "webhook_log_id": "a0A8....",
  "webhook_id": "evt_20260805_abc123",
  "message": "Webhook received and queued for processing"
}
```

**Error Responses:**

| Code | Scenario | Response Body |
|---|---|---|
| 400 | Endpoint inactive or unknown path | `{"error": "invalid_endpoint", "message": "..."}` |
| 400 | Missing required header or malformed JSON | `{"error": "invalid_request", "message": "..."}` |
| 401 | Signature invalid | `{"error": "signature_mismatch", "message": "HMAC validation failed"}` |
| 429 | Rate limited (future) | `{"error": "rate_limited", "retry_after": 60}` |
| 500 | Database write failure | `{"error": "server_error", "message": "..."}` |

---

### 2. WebhookHandler Interface

Contract for handlers processing specific webhook types.

```apex
public interface WebhookHandler {
    /**
     * Process a webhook payload.
     * 
     * @param webhookLog    The Webhook_Log__c record (includes Payload__c)
     * @param endpoint      The Webhook_Endpoint__c configuration
     * @return              WebhookResult with status and optional Integration_Event__e to publish
     * @throws              Exception if processing fails (caught and logged by trigger)
     */
    WebhookResult process(Webhook_Log__c webhookLog, Webhook_Endpoint__c endpoint);
}

public class WebhookResult {
    public enum Status { SUCCESS, FAILED, SKIPPED }
    
    public Status status;                          // Processing result
    public String errorCode;                       // e.g., "INVALID_PAYLOAD"
    public String errorMessage;                    // Exception message
    public String relatedRecordId;                 // ID of created/updated record
    public String relatedRecordType;               // Object API name (e.g., "Account")
    public Integration_Event__e integrationEvent;  // Publish to downstream if not null
    
    public WebhookResult(Status s) { this.status = s; }
}
```

**Example: StripeWebhookHandler**
```apex
public class StripeWebhookHandler implements WebhookHandler {
    public WebhookResult process(Webhook_Log__c log, Webhook_Endpoint__c endpoint) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(log.Payload__c);
        String eventType = (String) payload.get('type');
        
        if (eventType == 'charge.succeeded') {
            Map<String, Object> charge = (Map<String, Object>) payload.get('data');
            // Create or update Account based on charge metadata
            String customerId = (String) charge.get('customer');
            
            Integration_Event__e evt = new Integration_Event__e(
                Integration_Name__c = 'StripeChargeSyncToAccount',
                Endpoint_Id__c = endpoint.Integration_Endpoint__c,
                Payload__c = JSON.serialize(charge),
                Payload_Id__c = log.Webhook_Id__c,
                Source_Object_Type__c = 'Webhook_Log__c',
                Source_Record_Id__c = log.Id
            );
            
            WebhookResult result = new WebhookResult(WebhookResult.Status.SUCCESS);
            result.integrationEvent = evt;
            return result;
        }
        return new WebhookResult(WebhookResult.Status.SKIPPED);
    }
}
```

---

## Implementation Details

### 1. WebhookIngestController (REST Service)

```apex
@RestResource(urlMapping='/webhooks/v1/*')
global class WebhookIngestController {
    @HttpPost
    global static void handleWebhook() {
        // 1. Parse URL to extract endpoint path
        String path = RestContext.request.getRequestURI()
                      .substringAfterLast('/webhooks/v1/');
        
        // 2. Lookup Webhook_Endpoint__c by Webhook_Path__c
        Webhook_Endpoint__c endpoint = [
            SELECT Id, Source_System__c, Signature_Algorithm__c, 
                   Signature_Header_Name__c, Signing_Key_Named_Credential__c,
                   Handler_Class_Name__c, Is_Active__c, Max_Payload_Size_Bytes__c
            FROM Webhook_Endpoint__c
            WHERE Webhook_Path__c = :path
            LIMIT 1
        ];
        
        if (endpoint == null || !endpoint.Is_Active__c) {
            respondError(400, 'invalid_endpoint', 'Webhook endpoint not found or inactive');
            return;
        }
        
        // 3. Get request body and headers
        String rawBody = RestContext.request.getRequestBody().toString();
        String signature = RestContext.request.getHeader(endpoint.Signature_Header_Name__c);
        
        if (rawBody.length() > endpoint.Max_Payload_Size_Bytes__c) {
            respondError(400, 'payload_too_large', 'Payload exceeds size limit');
            return;
        }
        
        // 4. Validate signature
        if (endpoint.Signature_Algorithm__c != 'None') {
            WebhookSignatureValidator validator = new WebhookSignatureValidator(endpoint);
            if (!validator.isValid(rawBody, signature)) {
                respondError(401, 'signature_mismatch', 'HMAC validation failed');
                return;
            }
        }
        
        // 5. Check for duplicate (Webhook_Id__c)
        String webhookId = RestContext.request.getHeader('X-Webhook-Id');
        if (String.isBlank(webhookId)) {
            webhookId = generateWebhookId(rawBody);
        }
        
        Webhook_Log__c existing = [
            SELECT Id, Status__c
            FROM Webhook_Log__c
            WHERE Webhook_Id__c = :webhookId
            LIMIT 1
        ];
        
        if (existing != null) {
            // Duplicate: respond 200 but mark as skipped
            respondSuccess(200, existing.Id, webhookId, 'Webhook already processed');
            return;
        }
        
        // 6. Create Webhook_Log__c record (Status = Received)
        Webhook_Log__c log = new Webhook_Log__c(
            Webhook_Endpoint__c = endpoint.Id,
            Webhook_Id__c = webhookId,
            Payload__c = rawBody,
            Payload_Hash__c = generatePayloadHash(rawBody),
            Received_At__c = Datetime.now(),
            Status__c = 'Received',
            HTTP_Status_Sent__c = 200,
            Signature_Header_Value__c = signature?.left(1024),
            Signature_Valid__c = (endpoint.Signature_Algorithm__c != 'None'),
            Metadata__c = JSON.serialize(new Map<String, String> {
                'ip' => RestContext.request.getRemoteAddress(),
                'user_agent' => RestContext.request.getHeader('User-Agent')
            })
        );
        insert log;
        
        // 7. Publish Webhook_Event__e for async processing
        Webhook_Event__e evt = new Webhook_Event__e(
            Webhook_Log_Id__c = log.Id,
            Webhook_Endpoint_Id__c = endpoint.Id,
            Payload__c = rawBody,
            Webhook_Id__c = webhookId,
            Handler_Class_Name__c = endpoint.Handler_Class_Name__c,
            Source_Event_Id__c = RestContext.request.getHeader('X-Event-Id')
        );
        publish(evt);
        
        // 8. Respond 200 immediately (before async processing)
        respondSuccess(200, log.Id, webhookId, 'Webhook received and queued for processing');
    }
    
    // Helper methods
    private static void respondSuccess(Integer statusCode, String logId, String webhookId, String msg) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(
            new Map<String, Object> {
                'status' => 'accepted',
                'webhook_log_id' => logId,
                'webhook_id' => webhookId,
                'message' => msg
            }
        ));
    }
    
    private static void respondError(Integer statusCode, String errorCode, String message) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(
            new Map<String, Object> {
                'error' => errorCode,
                'message' => message
            }
        ));
    }
    
    private static String generateWebhookId(String payload) {
        String hash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA256', Blob.valueOf(payload)));
        return 'wh_' + Datetime.now().format('yyyyMMddHHmmss') + '_' + hash.substring(0, 8);
    }
    
    private static String generatePayloadHash(String payload) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA256', Blob.valueOf(payload)));
    }
    
    private static void publish(Webhook_Event__e evt) {
        EventBus.publish(new List<Webhook_Event__e> { evt });
    }
}
```

---

### 2. WebhookSignatureValidator

```apex
public class WebhookSignatureValidator {
    private Webhook_Endpoint__c endpoint;
    
    public WebhookSignatureValidator(Webhook_Endpoint__c ep) {
        this.endpoint = ep;
    }
    
    public Boolean isValid(String payload, String signature) {
        if (String.isBlank(signature)) {
            return false;
        }
        
        if (endpoint.Signature_Algorithm__c == 'HMAC_SHA256') {
            return validateHMAC_SHA256(payload, signature);
        } else if (endpoint.Signature_Algorithm__c == 'RSA_SHA256') {
            return validateRSA_SHA256(payload, signature);
        }
        
        return false;
    }
    
    private Boolean validateHMAC_SHA256(String payload, String signature) {
        // Extract expected signature from header (may be prefixed: "sha256=...")
        String expectedSig = signature;
        if (signature.startsWith('sha256=')) {
            expectedSig = signature.substring(7);
        }
        
        // Retrieve secret from Named Credential
        String secret = retrieveSecret();
        if (String.isBlank(secret)) {
            return false;
        }
        
        // Compute HMAC-SHA256
        Blob payloadBlob = Blob.valueOf(payload);
        Blob secretBlob = Blob.valueOf(secret);
        Blob computedSignature = Crypto.generateMac('HmacSHA256', payloadBlob, secretBlob);
        String computedHex = EncodingUtil.convertToHex(computedSignature);
        
        // Constant-time comparison to prevent timing attacks
        return constantTimeEquals(computedHex.toLowerCase(), expectedSig.toLowerCase());
    }
    
    private Boolean validateRSA_SHA256(String payload, String signature) {
        // Future: retrieve public key from Named Credential, verify signature
        throw new UnsupportedOperationException('RSA validation not yet implemented');
    }
    
    private String retrieveSecret() {
        // Retrieve secret from Named Credential
        // Note: This requires a REST callout to retrieve the secret securely
        // For now, assume secret is stored in Named Credential value
        
        // TODO: Implement secure secret retrieval from Named Credentials
        // This is a simplified placeholder
        return 'secret_value_from_named_credential';
    }
    
    private Boolean constantTimeEquals(String a, String b) {
        if (a.length() != b.length()) {
            return false;
        }
        
        Integer mismatch = 0;
        for (Integer i = 0; i < a.length(); i++) {
            if (a.charAt(i) != b.charAt(i)) {
                mismatch++;
            }
        }
        return mismatch == 0;
    }
}
```

---

### 3. WebhookEventTrigger (Async Processing)

```apex
trigger WebhookEventTrigger on Webhook_Event__e (after insert) {
    WebhookEventHandler handler = new WebhookEventHandler();
    handler.handle(Trigger.new);
}

public class WebhookEventHandler {
    public void handle(List<Webhook_Event__e> events) {
        List<Webhook_Log__c> logsToUpdate = new List<Webhook_Log__c>();
        List<Integration_Event__e> integrationsToPublish = new List<Integration_Event__e>();
        
        for (Webhook_Event__e evt : events) {
            try {
                // Retrieve Webhook_Log__c and Webhook_Endpoint__c
                Webhook_Log__c log = [
                    SELECT Id, Payload__c, Webhook_Endpoint__c
                    FROM Webhook_Log__c
                    WHERE Id = :evt.Webhook_Log_Id__c
                    LIMIT 1
                ];
                
                Webhook_Endpoint__c endpoint = [
                    SELECT Id, Handler_Class_Name__c, Integration_Endpoint__c
                    FROM Webhook_Endpoint__c
                    WHERE Id = :evt.Webhook_Endpoint_Id__c
                    LIMIT 1
                ];
                
                // Update log to Processing
                log.Status__c = 'Processing';
                logsToUpdate.add(log);
                
                // Instantiate handler and process
                Type handlerType = Type.forName(evt.Handler_Class_Name__c);
                WebhookHandler processorHandler = (WebhookHandler) handlerType.newInstance();
                WebhookResult result = processorHandler.process(log, endpoint);
                
                // Update log with result
                log.Status__c = result.status == WebhookResult.Status.SUCCESS ? 'Success' : 
                                result.status == WebhookResult.Status.SKIPPED ? 'Skipped' : 'Failed';
                log.Error_Code__c = result.errorCode;
                log.Error_Message__c = result.errorMessage;
                log.Related_Record_Id__c = result.relatedRecordId;
                log.Related_Record_Type__c = result.relatedRecordType;
                log.Processed_At__c = Datetime.now();
                log.Processing_Duration_Ms__c = log.Processed_At__c.getTime() - log.Received_At__c.getTime();
                
                // If handler provided Integration_Event__e, enqueue for publish
                if (result.integrationEvent != null) {
                    integrationsToPublish.add(result.integrationEvent);
                    log.Related_Integration_Log__c = null; // Will be updated after integration publishes
                }
                
                logsToUpdate.add(log);
                
            } catch (Exception e) {
                Webhook_Log__c log = new Webhook_Log__c(
                    Id = evt.Webhook_Log_Id__c,
                    Status__c = 'Failed',
                    Error_Code__c = 'HANDLER_EXCEPTION',
                    Error_Message__c = e.getMessage() + '\n' + e.getStackTraceString(),
                    Processed_At__c = Datetime.now()
                );
                logsToUpdate.add(log);
            }
        }
        
        update logsToUpdate;
        
        if (!integrationsToPublish.isEmpty()) {
            EventBus.publish(integrationsToPublish);
        }
    }
}
```

---

## Security Considerations

### 1. Signature Validation

- **Algorithm:** HMAC-SHA256 (default), RSA-SHA256 (future)
- **Key Storage:** Named Credentials only; never custom metadata or text fields
- **Comparison:** Constant-time comparison to prevent timing attacks
- **Replay attacks:** Webhook_Id__c deduplication prevents same payload twice

### 2. Payload Size Limits

- Default 1 MB; configurable per endpoint
- Prevents DoS via large payloads

### 3. Rate Limiting

- Future: Implement rate limiting (requests per minute per endpoint)
- IP-based and API-key-based options

### 4. Data Isolation

- Webhook_Log__c records isolated by Webhook_Endpoint__c
- Permissions follow standard Salesforce object access
- Operators: Custom permission `Manage_Webhooks` for LWC dashboard

### 5. Sensitive Data

- Payload stored as-is; sanitize in handler if needed
- Consider Platform Encryption for PII fields
- Audit logs enabled on Webhook_Log__c

---

## Error Handling and Retry Strategy

Webhook failures fall into two categories:

| Category | Examples | Behavior |
|---|---|---|
| **Handler error** | Schema validation, missing required field | Status = "Failed", no retry |
| **Transient error** | Network timeout, external API rate limit | Status = "RetryScheduled", retry via Integration_Log__c |

**Retry flow:**
1. Handler throws exception → status = "Failed"
2. If error is transient (detected by error code), publish Integration_Event__e to trigger retry
3. Existing Integration_Log__c retry mechanism handles exponential backoff

**DLQ flow:**
1. After max retries exceed → move to DLQ
2. Operator reviews via dashboard, corrects payload, manually replays via LWC

---

## Operational Aspects

### Dashboard Requirements (LWC: WebhookMonitor)

**Views:**
- **Overview:** Volume (24h), Success rate, Top errors, Slowest endpoints
- **By Endpoint:** Webhook count, Failure rate, Last activity, Signature mismatches
- **Error Details:** Error code, Message, Payload preview, Related records
- **Replay:** Bulk retry failed webhooks, reprocess from payload

**Filters:**
- Date range
- Endpoint
- Status (Success, Failed, Skipped, etc.)
- Error code

### Alerting

- Platform Event on Status = "DeadLetter" → notify operator via Chatter/Slack
- Email digest of top error codes (daily)
- Custom permission `View_Webhook_Errors` for alert recipients

### Audit Trail

- Webhook_Log__c tracks all inbound events
- Integration_Log__c tracks downstream integrations
- Link enables end-to-end visibility: webhook → handler → integration → external call

### Monitoring

- Salesforce Report: "Webhook Processing Summary" (grouped by endpoint, status)
- Grafana/Datadog: Export webhook metrics via API for centralized monitoring

---

## Testing Strategy

### Unit Tests

1. **WebhookSignatureValidator**
   - Valid HMAC-SHA256 signature: passes
   - Invalid signature: fails
   - Missing signature: fails
   - Constant-time comparison: passes (no timing differences)

2. **WebhookIngestController**
   - Valid webhook: 200 OK, Webhook_Log__c created
   - Duplicate webhook (same Webhook_Id__c): 200 OK, marked skipped
   - Missing endpoint: 400 Bad Request
   - Inactive endpoint: 400 Bad Request
   - Payload too large: 400 Bad Request
   - Invalid signature: 401 Unauthorized

3. **WebhookEventHandler**
   - Handler invoked with correct parameters
   - Exception in handler: log status = "Failed"
   - Integration event published if returned by handler
   - Timing duration calculated correctly

### Integration Tests (Scratch Org)

1. **End-to-end flow:** POST webhook → Webhook_Log__c created → handler invoked → Integration_Event__e published → Integration_Log__c created
2. **Signature validation:** Stripe/Shopify test webhooks with real signatures
3. **Deduplication:** Same payload sent twice → second request marked skipped
4. **Handler extensibility:** Custom handler processing Shopify order webhook

### Mock Data

- Stripe test event payloads (charge.succeeded, payment_intent.created)
- Shopify test event payloads (orders/create, products/update)
- GitHub test webhooks (push, pull_request)

---

## Deployment Plan

### Phase 1: Core Webhook Infrastructure (Week 1-2)

1. Create Webhook_Endpoint__c and Webhook_Log__c objects
2. Implement WebhookIngestController and WebhookSignatureValidator
3. Implement WebhookEventTrigger and WebhookEventHandler
4. Deploy to dev org; basic smoke tests
5. Create Webhook_Event__e platform event

### Phase 2: Handler Implementations (Week 3)

1. Create StripeWebhookHandler
2. Create ShopifyWebhookHandler
3. Create GitHubWebhookHandler (extensible example)
4. Integration tests in scratch org

### Phase 3: Dashboard and Operations (Week 4)

1. Create WebhookMonitor LWC
2. Create Webhook Processing Summary report
3. Implement manual replay functionality
4. Alerting via Platform Events

### Phase 4: Documentation and Handoff (Week 5)

1. Operator runbook for webhook configuration
2. Developer guide for creating custom handlers
3. Security review and pen test
4. Migrate to production via changeset or unlocked package

---

## Configuration Example

**Stripe Webhook Endpoint (Setup via UI):**

| Field | Value |
|---|---|
| Name | Stripe_Events |
| Webhook_Path__c | stripe |
| Source_System__c | Stripe |
| Signature_Algorithm__c | HMAC_SHA256 |
| Signature_Header_Name__c | X-Stripe-Signature |
| Signing_Key_Named_Credential__c | Stripe_Webhook_Secret |
| Handler_Class_Name__c | StripeWebhookHandler |
| Integration_Endpoint__c | Stripe_Charge_Sync (optional) |
| Is_Active__c | checked |

**Salesforce Configuration:**

1. Create Named Credential: `Stripe_Webhook_Secret`
   - URL: (placeholder, not used for webhook secrets)
   - Auth Type: Custom
   - Store secret in external identity field or use Alternative Auth Provider

2. Configure Stripe Dashboard:
   - Webhook URL: `https://your-instance.salesforce.com/services/apexrest/webhooks/v1/stripe`
   - Events: charge.succeeded, payment_intent.created
   - Signing secret: (auto-generated by Stripe)

3. Copy signing secret into Named Credential

4. Create Webhook_Endpoint__c record via Setup UI or Apex

---

## Success Metrics

| Metric | Target | Tracking |
|---|---|---|
| **Webhook acceptance rate** | > 99.9% | Webhook_Log__c count / external system attempt count |
| **Processing latency (p50)** | < 500ms | Processing_Duration_Ms__c percentile |
| **Deduplication effectiveness** | > 95% of retries identified | Count of Is_Duplicate__c = true |
| **Signature validation accuracy** | 100% (no false negatives) | Manual audit of Signature_Valid__c |
| **Handler error rate** | < 0.1% | Failed_Status count / total processed |
| **Dashboard load time** | < 1s | LWC WebhookMonitor performance |

---

## Future Enhancements

1. **Rate limiting:** Throttle requests per endpoint/IP to prevent abuse
2. **Webhook templating:** Allow non-code configuration of simple transformations (JSON path extraction)
3. **Webhook filtering:** Accept only specific event types per endpoint (defined in Webhook_Endpoint__c)
4. **Metrics export:** Publish webhook metrics to Datadog/New Relic for centralized monitoring
5. **Replay from DLQ:** UI to review, correct, and re-submit poison messages
6. **Bulk upload:** Accept multiple webhooks in single request (for recovery scenarios)
7. **Webhook signing:** Salesforce signs outbound notifications to external systems (reverse flow)

---

## Glossary

- **Webhook:** HTTP POST from external system to Salesforce (inbound)
- **Webhook_Id__c:** Unique idempotency key for deduplication
- **Payload_Hash__c:** SHA256 hash of payload for integrity verification
- **Signature validation:** HMAC/RSA check to ensure webhook authenticity
- **Handler:** Apex class implementing WebhookHandler interface; processes specific webhook type
- **DLQ (Dead Letter Queue):** Storage for repeatedly-failing webhooks
- **Platform Event:** Salesforce asynchronous message; enables decoupling and replay

---

## Appendix: Related Framework Docs

- [Integration Framework Design](./integration-framework.md)
- [Integration Endpoints Configuration Guide](./integration-endpoints.md)
- [Retry Strategy and Exponential Backoff](./retry-strategy.md)
- [Error Mapping and Classification](./error-handling.md)

---

## Document History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-08-05 | Animesh Das | Initial design document |
| | | | - Webhook ingestion architecture |
| | | | - Data model (Webhook_Endpoint__c, Webhook_Log__c) |
| | | | - WebhookHandler interface and examples |
| | | | - Security considerations (HMAC, key storage) |
| | | | - Testing and deployment plan |

---

**Status:** Ready for Architecture Review  
**Next Steps:** 
1. Review with technical stakeholders
2. Approve design
3. Begin Phase 1 implementation
4. Set up git branch: `feature/webhook-integration`

