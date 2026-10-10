@isTest
private class EscalateCaseToolTest {

    @isTest static void testSuccessEscalatesCaseAndStoresReason() {
        Case c = createCase('Open case');

        Test.startTest();
        ToolResult result = new EscalateCaseTool().invoke(escalateRequest(c.Id, 'Customer waiting 3 days'));
        Test.stopTest();

        Case updated = [
            SELECT CaseNumber, Priority, Escalation_Level__c, Escalation_Reason__c, Escalated_At__c
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals('success', result.status);
        System.assertEquals(true, result.outputs.get('escalated'));
        System.assertEquals(updated.CaseNumber, result.outputs.get('caseNumber'));
        System.assertEquals('High', result.outputs.get('priority'));
        System.assertEquals(CaseEscalationService.LEVEL_TIER_2, updated.Escalation_Level__c);
        System.assertEquals('Customer waiting 3 days', updated.Escalation_Reason__c);
        System.assertNotEquals(null, updated.Escalated_At__c);
    }

    @isTest static void testRepeatCallIsIdempotent() {
        Case c = createCase('Repeat case');

        Test.startTest();
        new EscalateCaseTool().invoke(escalateRequest(c.Id, 'First call'));
        Case afterFirst = [SELECT Escalated_At__c FROM Case WHERE Id = :c.Id];
        ToolResult second = new EscalateCaseTool().invoke(escalateRequest(c.Id, 'Second call'));
        Test.stopTest();

        Case afterSecond = [SELECT Escalation_Level__c, Escalation_Reason__c, Escalated_At__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(true, second.outputs.get('escalated'));
        System.assertEquals(afterFirst.Escalated_At__c, afterSecond.Escalated_At__c);
        System.assertEquals('First call', afterSecond.Escalation_Reason__c);
        System.assertEquals(CaseEscalationService.LEVEL_TIER_2, afterSecond.Escalation_Level__c);
    }

    @isTest static void testClosedCaseGivesConflict() {
        Case c = new Case(Subject = 'Closed case', Status = 'Closed', Origin = 'Web');
        insert c;

        String code;
        Test.startTest();
        try {
            new EscalateCaseTool().invoke(escalateRequest(c.Id, 'Should fail'));
        } catch (ToolException e) {
            code = e.code;
        }
        Test.stopTest();

        System.assertEquals('CONFLICT', code);
    }

    @isTest static void testUnknownCaseGivesNotFound() {
        Case c = createCase('Deleted case');
        Id deletedId = c.Id;
        delete c;

        String code;
        Test.startTest();
        try {
            new EscalateCaseTool().invoke(escalateRequest(deletedId, 'Missing'));
        } catch (ToolException e) {
            code = e.code;
        }
        Test.stopTest();

        System.assertEquals('NOT_FOUND', code);
    }

    @isTest static void testWrongObjectTypeGivesInvalidInput() {
        Account a = new Account(Name = 'Not a case');
        insert a;

        String code;
        String field;
        Test.startTest();
        try {
            new EscalateCaseTool().invoke(escalateRequest(a.Id, 'Wrong type'));
        } catch (ToolException e) {
            code = e.code;
            field = e.field;
        }
        Test.stopTest();

        System.assertEquals('INVALID_INPUT', code);
        System.assertEquals('caseId', field);
    }

    @isTest static void testBlankReasonGivesInvalidInput() {
        Case c = createCase('Blank reason case');

        String code;
        String field;
        Test.startTest();
        try {
            new EscalateCaseTool().invoke(escalateRequest(c.Id, '   '));
        } catch (ToolException e) {
            code = e.code;
            field = e.field;
        }
        Test.stopTest();

        System.assertEquals('INVALID_INPUT', code);
        System.assertEquals('reason', field);
        System.assertEquals(null, [SELECT Escalation_Level__c FROM Case WHERE Id = :c.Id].Escalation_Level__c);
    }

    private static Case createCase(String subject) {
        Case c = new Case(Subject = subject, Status = 'New', Priority = 'Low', Origin = 'Web');
        insert c;
        return c;
    }

    private static ToolRequest escalateRequest(Id caseId, String reason) {
        return new ToolRequest('escalate_case', '1.0.0', new Map<String, Object>{
            'caseId' => String.valueOf(caseId),
            'reason' => reason
        });
    }
}
