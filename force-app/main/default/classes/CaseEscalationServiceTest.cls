@isTest
private class CaseEscalationServiceTest {

    @isTest static void testBulkEscalationUsesOneQueryAndOneDml() {
        List<Case> cases = createCases(200);

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Integer dmlBefore  = Limits.getDmlStatements();
        List<CaseEscalationService.EscalationResult> results = CaseEscalationService.escalate(
            idsOf(cases), CaseEscalationService.LEVEL_TIER_2, 'Bulk escalation'
        );
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Integer dmlUsed  = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(200, results.size());
        System.assertEquals(1, soqlUsed, 'Escalation must query Cases once for the whole batch');
        System.assertEquals(1, dmlUsed, 'Escalation must save Cases in one DML statement');
        for (CaseEscalationService.EscalationResult r : results) {
            System.assertEquals(true, r.escalated);
            System.assertEquals(null, r.errorCode);
        }

        Integer updated = [
            SELECT COUNT() FROM Case
            WHERE Id IN :idsOf(cases)
              AND Escalation_Level__c = :CaseEscalationService.LEVEL_TIER_2
              AND Priority = 'High'
              AND Escalation_Reason__c = 'Bulk escalation'
              AND Escalated_At__c != null
        ];
        System.assertEquals(200, updated);
    }

    @isTest static void testEscalationSetsLevelPriorityReasonAndTimestamp() {
        Case c = createCases(1)[0];

        Test.startTest();
        CaseEscalationService.EscalationResult r = CaseEscalationService.escalate(
            new Set<Id>{ c.Id }, CaseEscalationService.LEVEL_MANAGEMENT, 'Customer threatened to cancel'
        )[0];
        Test.stopTest();

        System.assertEquals(true, r.escalated);
        System.assertEquals(null, r.errorCode);
        System.assertEquals(CaseEscalationService.LEVEL_MANAGEMENT, r.level);

        Case updated = [
            SELECT CaseNumber, Priority, Escalation_Level__c, Escalation_Reason__c, Escalated_At__c
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals(CaseEscalationService.LEVEL_MANAGEMENT, updated.Escalation_Level__c);
        System.assertEquals('High', updated.Priority);
        System.assertEquals('Customer threatened to cancel', updated.Escalation_Reason__c);
        System.assertNotEquals(null, updated.Escalated_At__c);
        System.assertEquals(updated.CaseNumber, r.caseNumber);
    }

    @isTest static void testSameOrLowerLevelIsNoOp() {
        Case c = createCases(1)[0];
        c.Escalation_Level__c  = CaseEscalationService.LEVEL_TIER_3;
        c.Escalated_At__c      = Datetime.now().addDays(-1);
        c.Escalation_Reason__c = 'Original reason';
        update c;
        // Compare against the stored value, not the in-memory one, so storage precision cannot cause a false failure.
        Datetime originalTime = [SELECT Escalated_At__c FROM Case WHERE Id = :c.Id].Escalated_At__c;

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        CaseEscalationService.EscalationResult sameLevel = CaseEscalationService.escalate(
            new Set<Id>{ c.Id }, CaseEscalationService.LEVEL_TIER_3, 'Second request'
        )[0];
        CaseEscalationService.EscalationResult lowerLevel = CaseEscalationService.escalate(
            new Set<Id>{ c.Id }, CaseEscalationService.LEVEL_TIER_2, 'Lower request'
        )[0];
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(0, dmlUsed, 'A no-op escalation must not write to the database');
        System.assertEquals(true, sameLevel.escalated);
        System.assertEquals(true, lowerLevel.escalated);
        System.assertEquals(CaseEscalationService.LEVEL_TIER_3, lowerLevel.level);

        Case unchanged = [
            SELECT Escalation_Level__c, Escalation_Reason__c, Escalated_At__c FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals(CaseEscalationService.LEVEL_TIER_3, unchanged.Escalation_Level__c);
        System.assertEquals('Original reason', unchanged.Escalation_Reason__c);
        System.assertEquals(originalTime, unchanged.Escalated_At__c);
    }

    @isTest static void testClosedCaseIsRejectedAndUnchanged() {
        Case c = new Case(Subject = 'Closed case', Status = 'Closed', Origin = 'Web');
        insert c;

        Test.startTest();
        CaseEscalationService.EscalationResult r = CaseEscalationService.escalate(
            new Set<Id>{ c.Id }, CaseEscalationService.LEVEL_TIER_2, 'Should not apply'
        )[0];
        Test.stopTest();

        System.assertEquals(false, r.escalated);
        System.assertEquals('CONFLICT', r.errorCode);

        Case unchanged = [SELECT Escalation_Level__c, Escalation_Reason__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(null, unchanged.Escalation_Level__c);
        System.assertEquals(null, unchanged.Escalation_Reason__c);
    }

    @isTest static void testMissingCaseReturnsNotFound() {
        Case c = new Case(Subject = 'Deleted case', Origin = 'Web');
        insert c;
        Id deletedId = c.Id;
        delete c;

        Test.startTest();
        CaseEscalationService.EscalationResult r = CaseEscalationService.escalate(
            new Set<Id>{ deletedId }, CaseEscalationService.LEVEL_TIER_2, 'Missing'
        )[0];
        Test.stopTest();

        System.assertEquals(false, r.escalated);
        System.assertEquals('NOT_FOUND', r.errorCode);
    }

    @isTest static void testMixedBatchReportsPerCaseAndUpdatesTheRest() {
        Case open = new Case(Subject = 'Open', Origin = 'Web');
        Case closed = new Case(Subject = 'Closed', Status = 'Closed', Origin = 'Web');
        insert new List<Case>{ open, closed };
        Case deleted = new Case(Subject = 'Deleted', Origin = 'Web');
        insert deleted;
        Id deletedId = deleted.Id;
        delete deleted;

        Test.startTest();
        List<CaseEscalationService.EscalationResult> results = CaseEscalationService.escalate(
            new Set<Id>{ open.Id, closed.Id, deletedId }, CaseEscalationService.LEVEL_TIER_2, 'Mixed batch'
        );
        Test.stopTest();

        System.assertEquals(3, results.size());
        Map<Id, CaseEscalationService.EscalationResult> byId = new Map<Id, CaseEscalationService.EscalationResult>();
        for (CaseEscalationService.EscalationResult r : results) {
            byId.put(r.caseId, r);
        }
        System.assertEquals(true, byId.get(open.Id).escalated);
        System.assertEquals('CONFLICT', byId.get(closed.Id).errorCode);
        System.assertEquals('NOT_FOUND', byId.get(deletedId).errorCode);

        System.assertEquals(CaseEscalationService.LEVEL_TIER_2,
            [SELECT Escalation_Level__c FROM Case WHERE Id = :open.Id].Escalation_Level__c);
    }

    @isTest static void testBlankReasonIsRejectedBeforeAnyQuery() {
        Case c = createCases(1)[0];
        Boolean thrown = false;

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        try {
            CaseEscalationService.escalate(new Set<Id>{ c.Id }, CaseEscalationService.LEVEL_TIER_2, '   ');
        } catch (IllegalArgumentException e) {
            thrown = true;
        }
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assertEquals(true, thrown);
        System.assertEquals(0, soqlUsed);
    }

    @isTest static void testUnknownOrNoneLevelIsRejected() {
        Case c = createCases(1)[0];
        Boolean noneThrown = false;
        Boolean bogusThrown = false;

        Test.startTest();
        try {
            CaseEscalationService.escalate(new Set<Id>{ c.Id }, CaseEscalationService.LEVEL_NONE, 'Reason');
        } catch (IllegalArgumentException e) {
            noneThrown = true;
        }
        try {
            CaseEscalationService.escalate(new Set<Id>{ c.Id }, 'Bogus', 'Reason');
        } catch (IllegalArgumentException e) {
            bogusThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, noneThrown);
        System.assertEquals(true, bogusThrown);
    }

    @isTest static void testUserWithoutCaseAccessGetsForbiddenAndNoChange() {
        Case c = createCases(1)[0];
        User restricted = createUserWithoutCaseAccess();

        CaseEscalationService.EscalationResult r;
        Test.startTest();
        System.runAs(restricted) {
            r = CaseEscalationService.escalate(
                new Set<Id>{ c.Id }, CaseEscalationService.LEVEL_TIER_2, 'No access'
            )[0];
        }
        Test.stopTest();

        System.assertEquals(false, r.escalated);
        System.assertEquals('FORBIDDEN', r.errorCode);
        System.assertEquals(null, [SELECT Escalation_Level__c FROM Case WHERE Id = :c.Id].Escalation_Level__c);
    }

    private static List<Case> createCases(Integer count) {
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            cases.add(new Case(Subject = 'Escalation test ' + i, Status = 'New', Priority = 'Low', Origin = 'Web'));
        }
        insert cases;
        return cases;
    }

    private static Set<Id> idsOf(List<Case> cases) {
        return new Map<Id, Case>(cases).keySet();
    }

    private static User createUserWithoutCaseAccess() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String suffix = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId         = p.Id,
            LastName          = 'Escalation',
            Alias             = 'esc',
            Email             = 'escalation.test@example.com',
            Username          = 'escalation.' + suffix + '@example.com.test',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }
}
