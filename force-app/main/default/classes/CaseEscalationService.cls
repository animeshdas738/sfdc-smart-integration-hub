/**
 * @description Owns the case escalation rules. Escalating a Case raises its Escalation_Level__c, stamps
 *              Escalated_At__c and Escalation_Reason__c, and sets Priority from the level. A request at or
 *              below the Case's current level changes nothing, so repeated calls are safe. Runs in user
 *              mode: the caller needs read and edit access to Case and the escalation fields.
 */
public with sharing class CaseEscalationService {

    public static final String LEVEL_NONE       = 'None';
    public static final String LEVEL_TIER_2     = 'Tier_2';
    public static final String LEVEL_TIER_3     = 'Tier_3';
    public static final String LEVEL_MANAGEMENT = 'Management';

    private static final Map<String, Integer> LEVEL_RANK = new Map<String, Integer>{
        LEVEL_NONE       => 0,
        LEVEL_TIER_2     => 1,
        LEVEL_TIER_3     => 2,
        LEVEL_MANAGEMENT => 3
    };

    // Management maps to High until the org confirms a Critical value exists on the Case Priority picklist.
    private static final Map<String, String> LEVEL_PRIORITY = new Map<String, String>{
        LEVEL_TIER_2     => 'High',
        LEVEL_TIER_3     => 'High',
        LEVEL_MANAGEMENT => 'High'
    };

    /**
     * @description Outcome for one Case. errorCode is null on success; otherwise it is one of
     *              NOT_FOUND, CONFLICT, FORBIDDEN or TOOL_ERROR.
     */
    public class EscalationResult {
        public Id      caseId;
        public String  caseNumber;
        public String  level;
        public String  priority;
        public Boolean escalated;
        public String  errorCode;
        public String  message;
    }

    /**
     * @description Escalates the given Cases to the requested level. Errors are reported per Case; a
     *              failing Case does not stop the others.
     * @param caseIds Ids of the Cases to escalate.
     * @param level   Target level: LEVEL_TIER_2, LEVEL_TIER_3 or LEVEL_MANAGEMENT.
     * @param reason  Why the Cases are being escalated. Required.
     * @return One result per Id in caseIds, in no guaranteed order.
     */
    public static List<EscalationResult> escalate(Set<Id> caseIds, String level, String reason) {
        if (String.isBlank(reason)) {
            throw new IllegalArgumentException('A reason is required to escalate a case.');
        }
        if (!LEVEL_PRIORITY.containsKey(level)) {
            throw new IllegalArgumentException('Unknown escalation level: ' + level);
        }

        List<EscalationResult> results = new List<EscalationResult>();
        if (caseIds == null || caseIds.isEmpty()) {
            return results;
        }

        Map<Id, Case> casesById;
        try {
            casesById = new Map<Id, Case>([
                SELECT Id, CaseNumber, Priority, IsClosed, Escalation_Level__c
                FROM Case
                WHERE Id IN :caseIds
                WITH USER_MODE
            ]);
        } catch (QueryException e) {
            for (Id caseId : caseIds) {
                results.add(failure(caseId, 'FORBIDDEN', 'Insufficient access to Case.'));
            }
            return results;
        }

        Integer targetRank = LEVEL_RANK.get(level);
        Map<Id, EscalationResult> resultsById = new Map<Id, EscalationResult>();
        List<Case> toUpdate = new List<Case>();

        for (Id caseId : caseIds) {
            Case c = casesById.get(caseId);
            if (c == null) {
                resultsById.put(caseId, failure(caseId, 'NOT_FOUND', 'Case not found or not accessible.'));
            } else if (c.IsClosed) {
                resultsById.put(caseId, failure(caseId, 'CONFLICT', 'The case is closed.'));
            } else if (rankOf(c.Escalation_Level__c) >= targetRank) {
                resultsById.put(caseId, toResult(c, 'Case is already at or above this level.'));
            } else {
                c.Escalation_Level__c = level;
                c.Escalated_At__c     = System.now();
                c.Escalation_Reason__c = reason;
                c.Priority            = LEVEL_PRIORITY.get(level);
                toUpdate.add(c);
            }
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saves = Database.update(toUpdate, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < saves.size(); i++) {
                Case c = toUpdate[i];
                if (saves[i].isSuccess()) {
                    resultsById.put(c.Id, toResult(c, 'Case escalated.'));
                } else {
                    resultsById.put(c.Id, failure(c.Id, 'TOOL_ERROR', saves[i].getErrors()[0].getMessage()));
                }
            }
        }

        for (Id caseId : caseIds) {
            results.add(resultsById.get(caseId));
        }
        return results;
    }

    private static Integer rankOf(String level) {
        Integer rank = LEVEL_RANK.get(level);
        return rank == null ? 0 : rank;
    }

    private static EscalationResult toResult(Case c, String message) {
        EscalationResult r = new EscalationResult();
        r.caseId     = c.Id;
        r.caseNumber = c.CaseNumber;
        r.level      = c.Escalation_Level__c;
        r.priority   = c.Priority;
        r.escalated  = true;
        r.message    = message;
        return r;
    }

    private static EscalationResult failure(Id caseId, String errorCode, String message) {
        EscalationResult r = new EscalationResult();
        r.caseId    = caseId;
        r.escalated = false;
        r.errorCode = errorCode;
        r.message   = message;
        return r;
    }
}
