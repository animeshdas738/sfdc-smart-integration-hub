/**
 * @description Aura-enabled entry point for the genericDataTable LWC. Read-only: it validates the
 *              input and delegates to GenericQueryService. Validation messages are safe to show;
 *              any other failure is reported with a generic message.
 */
public with sharing class GenericQueryController {

    /**
     * @description Returns the columns and rows for the requested object and fields.
     * @param objectApiName  sObject API name.
     * @param fieldApiNames  Field API names to show as columns.
     * @param rowLimit       Optional row limit; capped on the server.
     * @return               Columns, rows and warnings.
     */
    @AuraEnabled(cacheable=true)
    public static GenericQueryService.GenericQueryResult getRecords(String objectApiName, List<String> fieldApiNames, Integer rowLimit) {
        if (String.isBlank(objectApiName) || fieldApiNames == null || fieldApiNames.isEmpty()) {
            throw new AuraHandledException(GenericTableConstants.ERR_INVALID_INPUT);
        }
        try {
            return GenericQueryService.getRecords(objectApiName, fieldApiNames, rowLimit);
        } catch (IllegalArgumentException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException(GenericTableConstants.ERR_QUERY_FAILED);
        }
    }
}
