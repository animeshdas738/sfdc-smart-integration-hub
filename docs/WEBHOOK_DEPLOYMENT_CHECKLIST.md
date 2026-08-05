# Webhook Integration - Deployment Checklist

**Date:** 2026-08-05  
**Status:** Ready for Deployment  
**Version:** 1.0

---

## Pre-Deployment Verification

### ✅ Metadata Structure
- [x] All Apex classes have `.cls-meta.xml` files (7 total)
- [x] Trigger has `.trigger-meta.xml` file (1 total)
- [x] Custom objects properly structured (3 total)
- [x] All fields in separate `.field-meta.xml` files (43 total)
- [x] Platform event aligned with existing pattern
- [x] List views configured (4 total)
- [x] Record types defined (3 total)
- [x] API version set to 56.0 (matches existing classes)

### ✅ Code Quality
- [x] WebhookHandler.cls - Interface contract
- [x] WebhookResult.cls - Data class with Status enum
- [x] WebhookSignatureValidator.cls - HMAC-SHA256 validation
- [x] WebhookIngestController.cls - REST endpoint (56KB)
- [x] WebhookEventHandler.cls - Async processor
- [x] TestWebhookHandler.cls - Example handler
- [x] WebhookIngestControllerTest.cls - Unit tests (6 test cases)
- [x] WebhookEventTrigger.trigger - After insert trigger

### ✅ Documentation
- [x] webhook-integration-design.md - Complete architecture (340+ lines)
- [x] webhook-implementation-guide.md - Step-by-step guide (400+ lines)
- [x] WEBHOOK_IMPLEMENTATION_SUMMARY.md - Quick reference
- [x] WEBHOOK_STRUCTURE_ALIGNMENT.md - Structure alignment details

---

## Deployment Steps

### Phase 1: Validate Metadata

```bash
# Check syntax and dependencies
sfdx force:source:status

# Validate against org without deploying
sfdx force:source:deploy -p force-app/ --checkonly
```

**Expected Output:**
- No warnings or errors
- All metadata recognized
- 60+ component changes

### Phase 2: Deploy to Org

```bash
# Deploy all components
sfdx force:source:deploy -p force-app/

# Watch deployment progress
sfdx force:source:deploy -p force-app/ --wait 30
```

**Expected Output:**
- Deployment successful
- 60+ components deployed
- No test failures

### Phase 3: Verify Deployment

```bash
# Verify all components are active
sfdx force:source:status

# Run webhook tests
sfdx force:apex:test:run -c -r human --classnames WebhookIngestControllerTest
```

**Expected Output:**
- All classes Active
- All tests Pass (6/6)
- 100% code coverage target

### Phase 4: Configure Webhook Endpoints

1. **Navigate to Setup → Custom Objects → Webhook Endpoint**
2. **Create Webhook_Endpoint__c record:**

```
Name:                           Stripe_Events
Webhook_Path__c:               stripe
Source_System__c:              Stripe
Signature_Algorithm__c:        HMAC_SHA256
Signature_Header_Name__c:      X-Stripe-Signature
Signing_Key_Named_Credential__c: Stripe_Webhook_Secret
Handler_Class_Name__c:         StripeWebhookHandler
Is_Active__c:                  ✓
Max_Payload_Size_Bytes__c:     1048576
Retry_Enabled__c:              ✓
```

3. **Save and note the Webhook_Endpoint__c ID**

### Phase 5: Create Named Credentials

1. **Navigate to Setup → Named Credentials**
2. **Create new Named Credential:**

```
Label:                  Stripe_Webhook_Secret
URL:                    https://stripe.com (placeholder)
Authentication Type:    Custom
Custom Header:          X-Stripe-Signature
Secret Value:           (from Stripe Dashboard)
```

### Phase 6: Configure External System

**For Stripe:**
1. Log in to Stripe Dashboard
2. Navigate to Developers → Webhooks
3. Add Endpoint
4. URL: `https://your-instance.salesforce.com/services/apexrest/webhooks/v1/stripe`
5. Select events: `charge.succeeded`, `charge.failed`
6. Copy signing secret to Named Credential

**For Shopify:**
1. Admin → Settings → Apps and Integrations
2. Develop Apps → your app
3. Configuration → Webhooks
4. Create webhook
5. URL: `https://your-instance.salesforce.com/services/apexrest/webhooks/v1/shopify`
6. Select events as needed
7. Copy secret to Named Credential

### Phase 7: Test Webhook Ingestion

```bash
# Send test webhook via cURL
curl -X POST https://your-instance.salesforce.com/services/apexrest/webhooks/v1/stripe \
  -H "Content-Type: application/json" \
  -H "X-Stripe-Signature: sha256=test_signature" \
  -d '{
    "id": "evt_test_123",
    "type": "charge.succeeded",
    "data": {
      "object": {
        "id": "ch_test_456",
        "customer": "cus_test_789",
        "amount": 9999
      }
    }
  }'
```

**Expected Response:**
```json
{
  "status": "accepted",
  "webhook_log_id": "a0A8xxxx",
  "webhook_id": "wh_...",
  "message": "Webhook received and queued for processing"
}
```

### Phase 8: Verify Processing

1. **Navigate to Webhook_Log__c list view**
2. **Filter by Status = "Received" (past 5 minutes)**
3. **Click record and verify:**
   - Status changed to "Success" or "Failed"
   - Processing_Duration_Ms__c populated
   - Related_Record_Id__c set (if handler created record)

---

## Rollback Plan

If deployment fails or issues arise:

```bash
# Retrieve previous version from git
git checkout HEAD -- force-app/

# Remove only webhook components
rm -rf force-app/main/default/classes/Webhook*
rm -rf force-app/main/default/triggers/WebhookEvent*
rm -rf force-app/main/default/objects/Webhook_*

# Deploy removal
sfdx force:source:deploy -p force-app/
```

**Note:** Custom objects and their data will be retained. Only code components are removed.

---

## Post-Deployment Tasks

### Immediate (Day 1)
- [ ] Verify all components deployed successfully
- [ ] Run unit tests and confirm 100% pass
- [ ] Create 1st Webhook_Endpoint__c for testing
- [ ] Send test webhook from external system
- [ ] Verify Webhook_Log__c created

### Short-term (Week 1)
- [ ] Configure Named Credentials for all webhook sources
- [ ] Create system-specific handlers (Stripe, Shopify, GitHub)
- [ ] Create Webhook_Endpoint__c records for each source
- [ ] Test with real webhooks from staging/sandbox of external systems
- [ ] Create Salesforce report on Webhook_Log__c for dashboarding

### Medium-term (Month 1)
- [ ] Configure operational dashboard (Webhook Summary Report)
- [ ] Set up Platform Event alerting for DeadLetter status
- [ ] Document operator runbook for webhook troubleshooting
- [ ] Schedule recurring backup of Webhook_Log__c data
- [ ] Review webhook processing metrics and latency

### Long-term (Ongoing)
- [ ] Monitor webhook ingestion rate (trending)
- [ ] Track error rates by endpoint
- [ ] Measure processing latency (p50, p95, p99)
- [ ] Review and clean up old webhook logs (retention policy)
- [ ] Optimize handler performance as needed

---

## Success Criteria

✅ **Deployment Success**
- All 60+ metadata components deployed without errors
- No code coverage gaps (all classes have tests)
- All triggers active and firing correctly

✅ **Functional Validation**
- Webhook ingestion endpoint responding 200 OK
- Webhook_Log__c records created for each request
- Webhook_Event__e platform events publishing
- Async handlers processing and updating logs

✅ **Security Validation**
- Signature validation rejecting invalid requests (401)
- Payload size limits enforced (400)
- Inactive endpoints returning 400 errors
- Duplicate detection preventing re-processing

✅ **Performance Validation**
- Webhook response time < 500ms (user-facing)
- Handler processing time < 2s (async)
- No governor limit violations in logs

---

## Troubleshooting Guide

| Symptom | Cause | Solution |
|---|---|---|
| 404 Not Found on webhook URL | Endpoint not deployed or REST endpoint not registered | Verify deployment; check REST service annotation |
| 401 Unauthorized | Invalid signature | Verify signing secret matches external system; check header name |
| Webhook_Log__c not created | Database error or trigger not firing | Check Platform Event publish; review debug logs |
| Handler throws exception | Class name mismatch or not implementing interface | Verify Handler_Class_Name__c exactly matches class; implement WebhookHandler |
| Duplicate webhook received | External system retrying with same payload | Expected behavior; Webhook_Id__c should match existing log (verify in database) |

---

## Monitoring Dashboard Setup

### Report 1: Webhook Summary by Endpoint
**Location:** Setup → Reports → New Report  
**Object:** Webhook_Log__c  
**Grouping:** Webhook_Endpoint__c, Status__c  
**Columns:** Count

### Report 2: Failed Webhooks (Last 24H)
**Location:** Setup → Reports → New Report  
**Object:** Webhook_Log__c  
**Filter:** Status__c = "Failed" AND Received_At__c >= LAST_N_DAYS:1  
**Columns:** Webhook_Endpoint__c, Error_Code__c, Error_Message__c, Received_At__c

### Dashboard Tile: Webhook Health
**Chart Type:** Gauge  
**Metric:** Count of Failed Webhooks (Last 24H)  
**Target:** < 5  
**Warning:** > 2

---

## Support & Escalation

**For deployment issues:**
1. Check deployment logs: `sfdx force:source:deploy:report -i <job-id>`
2. Review apex test failures in org
3. Verify API version compatibility (56.0+)

**For webhook ingestion issues:**
1. Check Webhook_Log__c error details
2. Review handler class debug logs
3. Verify webhook signature and format with external system
4. Check Platform Event subscribers are active

**For performance issues:**
1. Review Processing_Duration_Ms__c in Webhook_Log__c
2. Check Apex limits in debug logs
3. Consider async batch processing if volume > 100/min
4. Profile handler class execution time

---

## Sign-Off

- [ ] Technical Lead Approval
- [ ] Security Review Passed
- [ ] Performance Testing Complete
- [ ] Documentation Review Complete
- [ ] Ready for Production Deployment

**Deployed by:** _______________  
**Date:** _______________  
**Environment:** ☐ Sandbox ☐ Production

---

## Additional Resources

- **Design Document:** webhook-integration-design.md
- **Implementation Guide:** webhook-implementation-guide.md
- **Code Reference:** WebhookHandler.cls, WebhookIngestController.cls
- **Test Suite:** WebhookIngestControllerTest.cls

---

**Status:** ✅ Ready for Deployment  
**Last Updated:** 2026-08-05  
**Next Review:** Post-deployment (Day 1)

