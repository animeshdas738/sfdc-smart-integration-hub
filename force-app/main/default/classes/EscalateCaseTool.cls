/**
 * @description Agent tool that escalates a Case to Tier 2 with a required reason. The rules live in
 *              CaseEscalationService. Calling it again for a Case already at or above Tier 2 changes nothing.
 *              Input and output keys match the registered tool contract; do not rename them without
 *              updating the contract hash.
 */
global with sharing class EscalateCaseTool extends BaseTool {

    global override ToolResult invoke(ToolRequest req) {
        this.request = req;

        Id caseId = getId('caseId', Case.SObjectType);
        String reason = getString('reason');
        if (String.isBlank(reason)) {
            throw invalid('reason', 'Must not be blank');
        }

        CaseEscalationService.EscalationResult outcome = CaseEscalationService.escalate(
            new Set<Id>{ caseId }, CaseEscalationService.LEVEL_TIER_2, reason
        )[0];

        if (outcome.errorCode == 'NOT_FOUND') {
            throw notFound('case');
        }
        if (outcome.errorCode == 'CONFLICT') {
            throw new ToolException('CONFLICT', 'caseId', outcome.message);
        }
        if (outcome.errorCode == 'FORBIDDEN') {
            throw forbidden(outcome.message);
        }
        if (outcome.errorCode != null) {
            throw new ToolException('TOOL_ERROR', outcome.message);
        }

        return ToolResult.success(new Map<String, Object>{
            'caseNumber' => outcome.caseNumber,
            'priority' => outcome.priority,
            'escalated' => outcome.escalated
        })
            .withMessage('Case ' + outcome.caseNumber + ' escalated to ' + outcome.level)
            .touched(caseId, 'updated');
    }
}
