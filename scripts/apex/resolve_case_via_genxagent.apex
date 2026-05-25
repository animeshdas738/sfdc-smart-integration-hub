// Sends Case 500g500000UcbDNAAZ to the GenX Agent resolve endpoint for AI-driven resolution.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents

Id caseId = '500g500000UcbDNAAZ';

// Fetch the case fields needed for the payload
Case c = [
    SELECT Id, CaseNumber, Subject, Description, Status
    FROM Case
    WHERE Id = :caseId
    LIMIT 1
];

System.debug('Case        : ' + c.CaseNumber + ' — ' + c.Subject);
System.debug('Status      : ' + c.Status);
System.debug('Description : ' + c.Description);

// Locate the active GenX Agent resolve endpoint
Integration_Endpoint__c ep = [
    SELECT Id, Name, Named_Credential__c, Endpoint_Path__c, Payload_Mapping__c, Active__c
    FROM Integration_Endpoint__c
    WHERE Named_Credential__c = 'GenxAgent_api'
      AND Endpoint_Path__c    = '/agents/resolve'
      AND Active__c           = true
    LIMIT 1
];

System.debug('Endpoint    : ' + ep.Name + ' (' + ep.Id + ')');

if (String.isBlank(ep.Payload_Mapping__c)) {
    System.debug('ABORTED — Payload_Mapping__c is empty on endpoint ' + ep.Name);
    return;
}

// Substitute case fields into the payload template
String payloadJson = ep.Payload_Mapping__c
    .replace('{{{subject}}}',     (c.Subject     != null ? c.Subject     : ''))
    .replace('{{{description}}}', (c.Description != null ? c.Description : ''));

System.debug('Payload     : ' + payloadJson);

// payloadId tied to the case so the idempotency guard prevents duplicate submissions
String payloadId      = 'genxagent-case-' + caseId;
String integrationName = 'GenXAgent_CaseResolution';

IntegrationService.send(integrationName, payloadId, payloadJson, ep.Id);

// Confirm the log was created
Integration_Log__c log = [
    SELECT Id, Name, Status__c, Payload_Id__c, Integration_Endpoint__c
    FROM Integration_Log__c
    WHERE Payload_Id__c = :payloadId
    LIMIT 1
];

System.debug('Integration Log : ' + log.Id + ' (' + log.Name + ')');
System.debug('Status          : ' + log.Status__c);
System.debug('Endpoint lookup : ' + log.Integration_Endpoint__c);
System.debug('Monitor the Integration Log record in Salesforce for execution progress.');
