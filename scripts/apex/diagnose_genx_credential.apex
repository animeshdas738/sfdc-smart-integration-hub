// Diagnoses the "couldn't access Genx_External_Auth" credential error.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents
//
// Chain:  callout:GenxAgent_api  →  Genx_External_Auth (external credential)
// The named credential GenxAgent_api is correct. The error occurs when Salesforce
// cannot resolve the external credential that backs it.

// --- 1. Inspect the integration log ---
Id logId = 'a02g5000008LnKUAA0';

Integration_Log__c log = [
    SELECT Id, Name, Status__c, Error_Message__c, Integration_Name__c,
           Integration_Endpoint__r.Named_Credential__c,
           Integration_Endpoint__r.Endpoint_Path__c,
           Integration_Endpoint__r.Active__c
    FROM Integration_Log__c
    WHERE Id = :logId
    LIMIT 1
];

System.debug('=== Integration Log ===');
System.debug('Log Id            : ' + log.Id);
System.debug('Status            : ' + log.Status__c);
System.debug('Error             : ' + log.Error_Message__c);
System.debug('Named Credential  : ' + log.Integration_Endpoint__r.Named_Credential__c);
System.debug('Endpoint Path     : ' + log.Integration_Endpoint__r.Endpoint_Path__c);
System.debug('Endpoint Active   : ' + log.Integration_Endpoint__r.Active__c);

// --- 2. Check current user ---
User u = [SELECT Id, Name, Username FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
System.debug('=== Running User ===');
System.debug('User Id   : ' + u.Id);
System.debug('Username  : ' + u.Username);

// --- 3. Check Integration_Ops permission set is assigned to the running user ---
List<PermissionSetAssignment> psas = [
    SELECT Id, PermissionSet.Name
    FROM PermissionSetAssignment
    WHERE AssigneeId = :UserInfo.getUserId()
      AND PermissionSet.Name = 'Integration_Ops'
    LIMIT 1
];

if (psas.isEmpty()) {
    System.debug('ISSUE FOUND: Integration_Ops permission set is NOT assigned to ' + u.Username);
    System.debug('FIX: Run assign_integration_ops_permset.apex to assign it.');
} else {
    System.debug('OK: Integration_Ops permission set is assigned to ' + u.Username);
}

// --- 4. Check all permission set assignments for the running user (for reference) ---
List<PermissionSetAssignment> allPsas = [
    SELECT PermissionSet.Name
    FROM PermissionSetAssignment
    WHERE AssigneeId = :UserInfo.getUserId()
    ORDER BY PermissionSet.Name
];
System.debug('=== All Permission Sets on Running User ===');
for (PermissionSetAssignment psa : allPsas) {
    System.debug('  - ' + psa.PermissionSet.Name);
}
