# Webhook Integration Implementation Guide

**Document Version:** 1.0  
**Date:** 2026-08-05  
**Status:** Ready for Use

---

## Overview

This guide provides step-by-step instructions for implementing webhook consumers using the Salesforce Generic Integration Framework webhook layer. It covers setup, configuration, handler development, testing, and operational tasks.

---

## Quick Start

### 1. Core Components Deployed

The following components are now available:

| Component | Type | File |
|---|---|---|
| **WebhookIngestController** | REST API | `WebhookIngestController.cls` |
| **WebhookEventTrigger** | Platform Event Trigger | `WebhookEventTrigger.trigger` |
| **WebhookEventHandler** | Async Processor | `WebhookEventHandler.cls` |
| **WebhookSignatureValidator** | Validator | `WebhookSignatureValidator.cls` |
| **WebhookHandler (interface)** | Contract | `WebhookHandler.cls` |
| **WebhookResult** | Data Class | `WebhookResult.cls` |
| **Webhook_Endpoint__c** | Custom Object | Webhook endpoint registry |
| **Webhook_Log__c** | Custom Object | Webhook audit trail |
| **Webhook_Event__e** | Platform Event | Async processing trigger |

---

## Phase 1: Configuration Setup

### Step 1: Create a Webhook_Endpoint__c Record

Navigate to Setup → Custom Objects → Webhook Endpoint or use Apex.

**Example: Stripe Webhook Endpoint**

```
Name:                           Stripe_Events
Webhook_Path__c:               stripe
Source_System__c:              Stripe
Signature_Algorithm__c:        HMAC_SHA256
Signature_Header_Name__c:      X-Stripe-Signature
Signing_Key_Named_Credential__c: Stripe_Webhook_Secret
Handler_Class_Name__c:         StripeWebhookHandler
Is_Active__c:                  ✓ (checked)
Max_Payload_Size_Bytes__c:     1048576
Retry_Enabled__c:              ✓ (checked)
```

**Webhook URL for external system:**
```
https://your-instance.salesforce.com/services/apexrest/webhooks/v1/stripe
```

### Step 2: Create Named Credential for Signing Key

Navigate to Setup → Named Credentials or use Apex deployment.

**Example: Stripe_Webhook_Secret**

| Field | Value |
|---|---|
| Label | Stripe_Webhook_Secret |
| URL | (placeholder, e.g., https://stripe.com) |
| Authentication Protocol | Custom |
| Custom Header | (store secret in Auth Header or Custom Field) |

**Retrieve webhook secret from external system:**
- **Stripe:** Dashboard → Developers → Webhooks → Show Signing Secret
- **Shopify:** Admin → Settings → Apps and Integrations → Develop Apps → Show credentials
- **GitHub:** Repository → Settings → Webhooks → Edit → (copy Secret field)

---

## Phase 2: Implement a Webhook Handler

### Step 1: Create a Handler Class

Create a class implementing the `WebhookHandler` interface:

```apex
/**
 * @description Handles Stripe webhook events (charges, payment intents, etc.)
 */
public class StripeWebhookHandler implements WebhookHandler {
    
    public WebhookResult process(Webhook_Log__c webhookLog, Webhook_Endpoint__c endpoint) {
        try {
            // Parse webhook payload
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(webhookLog.Payload__c);
            
            // Extract event type
            String eventType = (String) payload.get('type');
            Map<String, Object> dataObj = (Map<String, Object>) payload.get('data');
            Map<String, Object> chargeData = (Map<String, Object>) dataObj.get('object');
            
            // Route by event type
            if (eventType == 'charge.succeeded') {
                return handleChargeSucceeded(chargeData, webhook Log, endpoint);
            } else if (eventType == 'charge.failed') {
                return handleChargeFailed(chargeData, webhookLog, endpoint);
            } else {
                // Skip unknown event types
                return new WebhookResult(WebhookResult.Status.SKIPPED);
            }
            
        } catch (JSONException je) {
            return new WebhookResult(
                WebhookResult.Status.FAILED,
                'JSON_PARSE_ERROR',
                je.getMessage()
            );
        } catch (Exception e) {
            return new WebhookResult(
                WebhookResult.Status.FAILED,
                'HANDLER_ERROR',
                e.getMessage()
            );
        }
    }
    
    private WebhookResult handleChargeSucceeded(Map<String, Object> charge, Webhook_Log__c log, Webhook_Endpoint__c endpoint) {
        // Extract charge details
        String chargeId = (String) charge.get('id');
        String customerId = (String) charge.get('customer');
        String description = (String) charge.get('description');
        Long amount = (Long) charge.get('amount'); // in cents
        
        WebhookResult result = new WebhookResult(WebhookResult.Status.SUCCESS);
        
        // Example: Find or create Account and update
        List<Account> accounts = [
            SELECT Id FROM Account
            WHERE External_Customer_Id__c = :customerId
            LIMIT 1
        ];
        
        Account acc;
        if (accounts.isEmpty()) {
            acc = new Account(Name = description, External_Customer_Id__c = customerId);
            insert acc;
        } else {
            acc = accounts[0];
        }
        
        result.relatedRecordId = acc.Id;
        result.relatedRecordType = 'Account';
        
        // Optionally publish downstream integration event
        if (endpoint.Integration_Endpoint__c != null) {
            result.integrationEvent = new Integration_Event__e(
                Integration_Name__c = 'StripeChargeSyncToAccount',
                Endpoint_Id__c = endpoint.Integration_Endpoint__c,
                Payload__c = JSON.serialize(charge),
                Payload_Id__c = log.Webhook_Id__c,
                Source_Object_Type__c = 'Webhook_Log__c',
                Source_Record_Id__c = log.Id
            );
        }
        
        return result;
    }
    
    private WebhookResult handleChargeFailed(Map<String, Object> charge, Webhook_Log__c log, Webhook_Endpoint__c endpoint) {
        // Log failure, send alert, etc.
        String chargeId = (String) charge.get('id');
        String failureMessage = (String) charge.get('failure_message');
        
        // Example: Create a Case for failed charge
        Case failureCase = new Case(
            Subject = 'Stripe Charge Failed: ' + chargeId,
            Description = failureMessage,
            Status = 'New'
        );
        insert failureCase;
        
        WebhookResult result = new WebhookResult(WebhookResult.Status.SUCCESS);
        result.relatedRecordId = failureCase.Id;
        result.relatedRecordType = 'Case';
        return result;
    }
}
```

### Step 2: Update Webhook_Endpoint__c

Set `Handler_Class_Name__c` to your handler class:
```
Handler_Class_Name__c: StripeWebhookHandler
```

### Step 3: Test Locally

Use Apex test class or a REST client (Postman, cURL).

**Example: cURL request**
```bash
curl -X POST https://your-instance.salesforce.com/services/apexrest/webhooks/v1/stripe \
  -H "Content-Type: application/json" \
  -H "X-Stripe-Signature: sha256=test_signature" \
  -d '{
    "id": "evt_1234567890",
    "type": "charge.succeeded",
    "data": {
      "object": {
        "id": "ch_1234567890",
        "customer": "cus_1234567890",
        "amount": 9999,
        "description": "Test charge"
      }
    }
  }'
```

---

## Phase 3: Signature Validation Setup

### For HMAC-SHA256 (Stripe, Shopify, GitHub)

1. **Retrieve webhook secret from external system** (see Phase 1, Step 2)

2. **Create Named Credential** with the secret

3. **Update WebhookSignatureValidator** to retrieve secret from Named Credential

   Current placeholder:
   ```apex
   private String retrieveSecret() {
       return System.Label.Webhook_Secret; // Custom Label
   }
   ```

   **TODO:** Implement secure retrieval from Named Credentials using HTTP callout:
   ```apex
   private String retrieveSecret() {
       // Retrieve from Named Credential - requires HTTP callout or metadata read
       // Option 1: Use custom label
       return System.Label.Webhook_Secret;
       
       // Option 2: Use Auth Provider (advanced)
       // Option 3: Query encrypted custom setting
   }
   ```

### Signature Validation Flow

1. **Controller receives webhook** with header: `X-Stripe-Signature: sha256=abc123...`
2. **WebhookSignatureValidator.isValid()** called
3. **HMAC-SHA256 computed** over payload + secret
4. **Constant-time comparison** against received signature
5. **400 Unauthorized** returned if mismatch

---

## Phase 4: Testing

### Unit Tests

Run existing test class:
```apex
WebhookIngestControllerTest.testHandleWebhookSuccess();
WebhookIngestControllerTest.testHandleWebhookDuplicate();
WebhookIngestControllerTest.testHandleWebhookEndpointNotFound();
WebhookIngestControllerTest.testSignatureValidation();
```

### Integration Tests (Scratch Org)

1. **Create test Webhook_Endpoint__c**
2. **Deploy test handler** (TestWebhookHandler)
3. **POST test webhook** via REST API
4. **Verify Webhook_Log__c created** with Status = "Received"
5. **Check async processing** via Webhook_Log__c Status change to "Success"
6. **Verify Integration_Event__e published** (if handler returned event)

### Load Testing

For high-volume integrations (> 100 RPS):
- Batch size test webhook payload (1000s at once)
- Monitor Salesforce CPU time, governor limits
- Consider async queueable jobs instead of triggers

---

## Phase 5: Operational Tasks

### Dashboard & Monitoring

Create Salesforce Report on Webhook_Log__c:

**Webhook Summary Report**
- Rows: Webhook_Endpoint__c
- Columns: Status__c (pivot)
- Values: Count of records
- Filters: Received_At__c >= Last 24 Hours

**Dashboard:**
- Webhook ingestion rate (chart)
- Top errors (table)
- Processing latency distribution (histogram)
- Signature validation success rate (gauge)

### Alerting

**Chatter post on DeadLetter status:**
```apex
// In WebhookEventHandler or dedicated process
if (log.Status__c == 'DeadLetter') {
    FeedItem post = new FeedItem(
        ParentId = endpoint.Owner,
        Body = 'Webhook failed max retries: ' + endpoint.Name + 
               ' Error: ' + log.Error_Message__c
    );
    insert post;
}
```

### Manual Replay

**Scenario:** Payload was malformed; external system fixed and re-sent. Need to reprocess old payload.

1. Navigate to Webhook_Log__c record
2. View Payload__c and Operator_Notes__c
3. (Future) Add "Replay" button → re-publishes Webhook_Event__e
4. Status changes to "Processing" → "Success"

### Rate Limiting

**Future enhancement:** Limit webhooks per endpoint.

```apex
// Example threshold config
Webhook_Endpoint__c endpoint = [SELECT Max_Requests_Per_Minute__c FROM Webhook_Endpoint__c];
if (webhooksInLast60Seconds > endpoint.Max_Requests_Per_Minute__c) {
    respondError(429, 'rate_limited', 'Max requests exceeded');
}
```

---

## Troubleshooting

### Webhook not received (404 Not Found)

**Check:**
- Webhook_Endpoint__c.Webhook_Path__c matches URL path
- Endpoint.Is_Active__c = true
- REST endpoint is deployed

### Signature validation failed (401 Unauthorized)

**Check:**
- Signing_Key_Named_Credential__c value is correct
- Secret from external system matches Named Credential
- External system header name matches Signature_Header_Name__c

### Handler throws exception (Status = Failed)

**Check:**
- Error_Message__c and Error_Code__c in Webhook_Log__c
- Handler class name matches Handler_Class_Name__c exactly
- Handler implements WebhookHandler interface

### Webhook marked Duplicate (Status = Received, no further processing)

**Expected behavior:** External system retried. Webhook_Id__c matched existing record.

**To reprocess:**
1. Change existing log Status__c = "Received"
2. Delete and recreate Webhook_Log__c with new Webhook_Id__c
3. Or: Create new manual Webhook_Event__e and publish

---

## Example Handlers

### Shopify Orders Handler

```apex
public class ShopifyWebhookHandler implements WebhookHandler {
    public WebhookResult process(Webhook_Log__c log, Webhook_Endpoint__c endpoint) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(log.Payload__c);
        
        String orderId = (String) payload.get('id');
        String customerEmail = (String) payload.get('email');
        
        // Sync to Salesforce Order
        List<Account> accounts = [SELECT Id FROM Account WHERE Email__c = :customerEmail LIMIT 1];
        Account acc = accounts.isEmpty() ? null : accounts[0];
        
        if (acc != null) {
            Order o = new Order(
                AccountId = acc.Id,
                External_Order_ID__c = String.valueOf(orderId),
                Status = 'Draft'
            );
            insert o;
            
            WebhookResult result = new WebhookResult(WebhookResult.Status.SUCCESS);
            result.relatedRecordId = o.Id;
            result.relatedRecordType = 'Order';
            return result;
        }
        
        return new WebhookResult(WebhookResult.Status.SKIPPED);
    }
}
```

### GitHub Push Handler

```apex
public class GitHubWebhookHandler implements WebhookHandler {
    public WebhookResult process(Webhook_Log__c log, Webhook_Endpoint__c endpoint) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(log.Payload__c);
        
        String repo = (String) payload.get('repository');
        List<Object> commits = (List<Object>) payload.get('commits');
        
        // Log commits to Salesforce
        List<Git_Commit__c> commitRecords = new List<Git_Commit__c>();
        for (Object c : commits) {
            Map<String, Object> commit = (Map<String, Object>) c;
            commitRecords.add(new Git_Commit__c(
                Repo__c = repo,
                Commit_SHA__c = (String) commit.get('id'),
                Message__c = (String) commit.get('message')
            ));
        }
        
        insert commitRecords;
        
        WebhookResult result = new WebhookResult(WebhookResult.Status.SUCCESS);
        return result;
    }
}
```

---

## Security Best Practices

1. **Always validate signatures** – use HMAC-SHA256 or RSA-SHA256
2. **Store secrets in Named Credentials** – never hardcode or custom metadata
3. **Sanitize payloads** – don't log sensitive data (PII, tokens)
4. **Restrict endpoint access** – use Salesforce permissions and IP whitelisting
5. **Monitor logs** – alert on repeated failures or signature mismatches
6. **Rate limit** – prevent DoS via payload flood

---

## Next Steps

1. ✅ Deploy core components (Apex + metadata)
2. ⬜ Create Webhook_Endpoint__c records for each external system
3. ⬜ Implement system-specific handlers (Stripe, Shopify, etc.)
4. ⬜ Configure Named Credentials for secrets
5. ⬜ Test with external system sandbox/staging
6. ⬜ Create operational dashboard
7. ⬜ Deploy to production with change set/package

---

## Related Documentation

- [Webhook Integration Design](./webhook-integration-design.md) – Full architecture and data model
- [Integration Framework Design](./integration-framework.md) – Existing integration retry/DLQ logic
- [API Contract Reference](#phase-1-configuration-setup) – REST endpoint specs

---

## Support & Troubleshooting

For issues or questions:
1. Check Webhook_Log__c error details
2. Review handler class logs and debug statements
3. Consult [Troubleshooting](#troubleshooting) section above
4. Contact integration team with Webhook_Log__c ID

---

**Document Status:** Ready for Implementation  
**Last Updated:** 2026-08-05

