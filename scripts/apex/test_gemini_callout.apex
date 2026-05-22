// Sample callout to the Gemini Integration Endpoint (a01g500000O1CFpAAN).
// Run via: SFDX: Execute Anonymous Apex with Editor Contents
//
// NOTE: IntegrationExecutor routes callouts using IntegrationConstants.DEFAULT_NAMED_CREDENTIAL
// ('Gemini') and DEFAULT_RESOURCE_PATH, not the endpoint record fields. The endpoint Id is
// attached to the log purely for traceability / reporting.

Id endpointId = 'a01g500000O1CFpAAN';

// Verify the endpoint exists and is active before firing
Integration_Endpoint__c ep = [
    SELECT Id, Name, External_System_Name__c, Named_Credential__c, Endpoint_Path__c, Active__c
    FROM Integration_Endpoint__c
    WHERE Id = :endpointId
    LIMIT 1
];

if (!ep.Active__c) {
    System.debug('ABORTED — endpoint ' + ep.Name + ' is inactive.');
    return;
}

System.debug('Targeting endpoint: ' + ep.Name + ' (' + ep.External_System_Name__c + ')');
System.debug('Named Credential : ' + ep.Named_Credential__c);
System.debug('Endpoint Path    : ' + ep.Endpoint_Path__c);

// Build a fully-resolved Gemini generateContent request body.
// Replace the text value below with the actual prompt you want to send.
Map<String, Object> payload = new Map<String, Object>{
    'contents' => new List<Object>{
        new Map<String, Object>{
            'parts' => new List<Object>{
                new Map<String, Object>{
                    'text' => 'Summarize the key benefits of the Salesforce Integration Hub in three bullet points.'
                }
            }
        }
    },
    'generationConfig' => new Map<String, Object>{
        'temperature'     => 1.0,
        'topK'            => 40,
        'topP'            => 0.95,
        'maxOutputTokens' => 512
    }
};

String payloadJson = JSON.serialize(payload);

// Unique payload ID — prevents duplicate processing on re-runs (idempotency guard in IntegrationService).
// Change this value to re-trigger the same prompt after a successful run.
String payloadId = 'gemini-test-' + String.valueOf(System.now().getTime());

String integrationName = 'Gemini_Content_Generation';

IntegrationService.send(integrationName, payloadId, payloadJson, endpointId);

// Query back the log to confirm it was queued
Integration_Log__c log = [
    SELECT Id, Name, Status__c, Payload_Id__c, Integration_Endpoint__c
    FROM Integration_Log__c
    WHERE Payload_Id__c = :payloadId
    LIMIT 1
];

System.debug('Integration Log created : ' + log.Id + ' (' + log.Name + ')');
System.debug('Status                  : ' + log.Status__c);
System.debug('Payload ID              : ' + log.Payload_Id__c);
System.debug('Endpoint lookup         : ' + log.Integration_Endpoint__c);
System.debug('Check the log record in Salesforce to monitor execution progress.');
