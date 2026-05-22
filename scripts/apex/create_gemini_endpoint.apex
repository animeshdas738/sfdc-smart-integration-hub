// Creates a sample Integration_Endpoint__c record wired to the Gemini_External_Auth named credential.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents

// Payload_Mapping__c documents the expected JSON structure callers should pass to IntegrationService.send().
// Use {{{fieldName}}} tokens as placeholders for dynamic values in the outbound body.
String payloadTemplate = JSON.serialize(new Map<String, Object>{
    'contents' => new List<Object>{
        new Map<String, Object>{
            'parts' => new List<Object>{
                new Map<String, Object>{ 'text' => '{{{prompt}}}' }
            }
        }
    },
    'generationConfig' => new Map<String, Object>{
        'temperature'     => 1.0,
        'topK'            => 40,
        'topP'            => 0.95,
        'maxOutputTokens' => 8192
    },
    'safetySettings' => new List<Object>{
        new Map<String, Object>{
            'category'  => 'HARM_CATEGORY_HARASSMENT',
            'threshold' => 'BLOCK_MEDIUM_AND_ABOVE'
        },
        new Map<String, Object>{
            'category'  => 'HARM_CATEGORY_HATE_SPEECH',
            'threshold' => 'BLOCK_MEDIUM_AND_ABOVE'
        }
    }
});

Integration_Endpoint__c endpoint = new Integration_Endpoint__c(
    External_System_Name__c      = 'Google Gemini',
    Named_Credential__c          = 'Gemini_API',
    Endpoint_Path__c             = '/v1beta/models/gemini-2.5-flash:generateContent',
    Payload_Mapping__c           = payloadTemplate,
    Default_Max_Attempts__c      = 3,
    Default_Base_Delay_Seconds__c = 30,
    Active__c                    = true
);

insert endpoint;

System.debug('Created Integration Endpoint: ' + endpoint.Id + ' — ' + endpoint.Name);
System.debug('Callout will resolve to: callout:Gemini_API/v1beta/models/gemini-2.5-flash:generateContent');
