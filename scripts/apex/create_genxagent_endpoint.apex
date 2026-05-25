// Creates an Integration_Endpoint__c record for the GenX Agent resolve API.
// Callout resolves to: callout:GenxAgent_api/agents/resolve
// Run via: SFDX: Execute Anonymous Apex with Editor Contents

String payloadTemplate = JSON.serialize(new Map<String, Object>{
    'subject'     => '{{{subject}}}',
    'description' => '{{{description}}}'
});

Integration_Endpoint__c endpoint = new Integration_Endpoint__c(
    External_System_Name__c       = 'GenX Agent API',
    Named_Credential__c           = 'GenxAgent_api',
    Endpoint_Path__c              = '/agents/resolve',
    Payload_Mapping__c            = payloadTemplate,
    Default_Max_Attempts__c       = 3,
    Default_Base_Delay_Seconds__c = 30,
    Active__c                     = true
);

insert endpoint;

System.debug('Created Integration Endpoint : ' + endpoint.Id + ' — ' + endpoint.Name);
System.debug('Callout will resolve to      : callout:GenxAgent_api/agents/resolve');
