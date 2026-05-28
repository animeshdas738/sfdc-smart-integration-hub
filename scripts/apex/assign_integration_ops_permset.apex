// Assigns the Integration_Ops permission set to the current user.
// Run this if diagnose_genx_credential.apex reports the perm set is missing.
// Run via: SFDX: Execute Anonymous Apex with Editor Contents

Id userId = UserInfo.getUserId();
User u = [SELECT Id, Name, Username FROM User WHERE Id = :userId LIMIT 1];

PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Integration_Ops' LIMIT 1];

List<PermissionSetAssignment> existing = [
    SELECT Id FROM PermissionSetAssignment
    WHERE AssigneeId = :userId AND PermissionSetId = :ps.Id
    LIMIT 1
];

if (!existing.isEmpty()) {
    System.debug('Integration_Ops is already assigned to ' + u.Username + '. No action needed.');
} else {
    insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
    System.debug('SUCCESS: Assigned Integration_Ops to ' + u.Username + ' (' + userId + ')');
    System.debug('Re-run the failed integration log to retry the callout.');
}
