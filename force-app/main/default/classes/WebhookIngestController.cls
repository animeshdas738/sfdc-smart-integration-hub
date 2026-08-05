/**
 * @description REST endpoint for receiving webhooks from external systems.
 *              Routes webhooks to registered handlers, validates signatures, and deduplicates.
 */
@RestResource(urlMapping='/webhooks/v1/*')
global class WebhookIngestController {
    private static final Integer DEFAULT_MAX_PAYLOAD_SIZE = 1048576; // 1 MB

    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            // Parse URL to extract endpoint path
            String path = req.requestURI.substringAfterLast('/webhooks/v1/');
            if (String.isBlank(path)) {
                respondError(res, 400, 'invalid_endpoint', 'Webhook path is required');
                return;
            }

            // Lookup Webhook_Endpoint__c by Webhook_Path__c
            List<Webhook_Endpoint__c> endpoints = [
                SELECT Id, Source_System__c, Signature_Algorithm__c,
                       Signature_Header_Name__c, Signing_Key_Named_Credential__c,
                       Handler_Class_Name__c, Is_Active__c, Max_Payload_Size_Bytes__c
                FROM Webhook_Endpoint__c
                WHERE Webhook_Path__c = :path
                LIMIT 1
            ];

            if (endpoints.isEmpty()) {
                respondError(res, 400, 'invalid_endpoint', 'Webhook endpoint not found');
                return;
            }

            Webhook_Endpoint__c endpoint = endpoints[0];

            if (!endpoint.Is_Active__c) {
                respondError(res, 400, 'endpoint_inactive', 'Webhook endpoint is not active');
                return;
            }

            // Get request body and headers
            String rawBody = req.requestBody.toString();
            String signature = req.headers.get(endpoint.Signature_Header_Name__c);

            // Validate payload size
            Integer maxSize = endpoint.Max_Payload_Size_Bytes__c != null
                ? Integer.valueOf(endpoint.Max_Payload_Size_Bytes__c)
                : DEFAULT_MAX_PAYLOAD_SIZE;

            if (rawBody.length() > maxSize) {
                respondError(res, 400, 'payload_too_large', 'Payload exceeds size limit of ' + maxSize + ' bytes');
                return;
            }

            // Validate signature
            if (endpoint.Signature_Algorithm__c != 'None') {
                WebhookSignatureValidator validator = new WebhookSignatureValidator(endpoint);
                if (!validator.isValid(rawBody, signature)) {
                    respondError(res, 401, 'signature_mismatch', 'HMAC validation failed');
                    return;
                }
            }

            // Generate or retrieve Webhook_Id__c
            String webhookId = req.headers.get('X-Webhook-Id');
            if (String.isBlank(webhookId)) {
                webhookId = generateWebhookId(rawBody);
            }

            // Check for duplicate
            List<Webhook_Log__c> existingLogs = [
                SELECT Id, Status__c
                FROM Webhook_Log__c
                WHERE Webhook_Id__c = :webhookId
                LIMIT 1
            ];

            if (!existingLogs.isEmpty()) {
                respondSuccess(res, 200, existingLogs[0].Id, webhookId, 'Webhook already processed');
                return;
            }

            // Create Webhook_Log__c record (Status = Received)
            Webhook_Log__c log = new Webhook_Log__c(
                Webhook_Endpoint__c = endpoint.Id,
                Webhook_Id__c = webhookId,
                Payload__c = rawBody,
                Payload_Hash__c = generatePayloadHash(rawBody),
                Received_At__c = Datetime.now(),
                Status__c = 'Received',
                HTTP_Status_Sent__c = 200,
                Signature_Header_Value__c = signature != null ? signature.left(255) : null,
                Signature_Valid__c = (endpoint.Signature_Algorithm__c != 'None'),
                Metadata__c = JSON.serialize(new Map<String, String> {
                    'ip' => req.remoteAddress,
                    'user_agent' => req.headers.get('User-Agent') != null ? req.headers.get('User-Agent') : 'unknown'
                })
            );
            insert log;

            // Publish Webhook_Event__e for async processing
            Webhook_Event__e evt = new Webhook_Event__e(
                Webhook_Log_Id__c = log.Id,
                Webhook_Endpoint_Id__c = endpoint.Id,
                Payload__c = rawBody,
                Webhook_Id__c = webhookId,
                Handler_Class_Name__c = endpoint.Handler_Class_Name__c,
                Source_Event_Id__c = req.headers.get('X-Event-Id')
            );
            EventBus.publish(new List<Webhook_Event__e> { evt });

            // Respond 200 immediately (before async processing)
            respondSuccess(res, 200, log.Id, webhookId, 'Webhook received and queued for processing');

        } catch (QueryException qe) {
            respondError(RestContext.response, 500, 'server_error', 'Database query failed: ' + qe.getMessage());
        } catch (DmlException de) {
            respondError(RestContext.response, 500, 'server_error', 'Database write failed: ' + de.getMessage());
        } catch (Exception e) {
            respondError(RestContext.response, 500, 'server_error', 'Unexpected error: ' + e.getMessage());
        }
    }

    private static void respondSuccess(RestResponse res, Integer statusCode, String logId, String webhookId, String msg) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(
            new Map<String, Object> {
                'status' => 'accepted',
                'webhook_log_id' => logId,
                'webhook_id' => webhookId,
                'message' => msg
            }
        ));
    }

    private static void respondError(RestResponse res, Integer statusCode, String errorCode, String message) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(
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
}
