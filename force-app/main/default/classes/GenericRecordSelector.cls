/**
 * @description Runs the generic table query. Object and field names must already be checked by
 *              GenericQueryService against describe information; this class also checks their
 *              format so that no user text can reach the query string. The row limit is a bound
 *              variable and the query runs in user mode so platform field and object security apply.
 *              Note: the repository has no BaseSelector class, so this is a plain selector.
 */
public with sharing class GenericRecordSelector {

    /**
     * @description Runs the query and returns up to rowLimit records.
     * @param objectApiName Validated sObject API name.
     * @param fieldNames    Validated field API names (must include Id).
     * @param rowLimit      Already capped by the caller; bound into the query.
     * @return              Matching records.
     */
    public static List<SObject> selectRecords(String objectApiName, List<String> fieldNames, Integer rowLimit) {
        return Database.query(buildQueryString(objectApiName, fieldNames));
    }

    /**
     * @description Builds the query text. The limit is written as the bind variable :rowLimit and is
     *              bound by selectRecords, so the caller must keep the rowLimit variable in scope.
     * @param objectApiName Object API name to validate and use in FROM.
     * @param fieldNames    Field API names to validate and use in SELECT.
     * @return              The SOQL text.
     */
    public static String buildQueryString(String objectApiName, List<String> fieldNames) {
        validateIdentifier(objectApiName);
        for (String fieldName : fieldNames) {
            validateIdentifier(fieldName);
        }
        return 'SELECT ' + String.join(fieldNames, ', ')
            + ' FROM ' + objectApiName
            + ' WITH USER_MODE LIMIT :rowLimit';
    }

    private static void validateIdentifier(String name) {
        if (String.isBlank(name) || !Pattern.matches(GenericTableConstants.IDENTIFIER_REGEX, name)) {
            throw new IllegalArgumentException(GenericTableConstants.ERR_INVALID_IDENTIFIER);
        }
    }
}
