/**
 * @description Validates the requested object and fields against the org's describe information,
 *              runs the query through GenericRecordSelector and maps the result for lightning-datatable.
 *              Fields the running user cannot read are left out and reported as a warning. Unknown,
 *              relationship, address and location fields are rejected.
 */
public with sharing class GenericQueryService {

    /**
     * @description Column and row data returned to the genericDataTable component.
     */
    public class GenericQueryResult {
        @AuraEnabled public List<ColumnInfo> columns { get; set; }
        @AuraEnabled public List<Map<String, Object>> rows { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }
    }

    /**
     * @description Column definition for lightning-datatable.
     */
    public class ColumnInfo {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public String type { get; set; }
    }

    /**
     * @description Runs the query for the requested object and fields.
     * @param objectApiName  sObject API name.
     * @param fieldApiNames  Field API names to show as columns. Id is always returned in rows.
     * @param rowLimit       Requested row count. Null or zero uses the default; values above MAX_ROWS are capped.
     * @return               Columns, rows and warnings.
     */
    public static GenericQueryResult getRecords(String objectApiName, List<String> fieldApiNames, Integer rowLimit) {
        if (fieldApiNames == null || fieldApiNames.isEmpty()) {
            throw new IllegalArgumentException(GenericTableConstants.ERR_INVALID_INPUT);
        }
        if (fieldApiNames.size() > GenericTableConstants.MAX_FIELDS) {
            throw new IllegalArgumentException(GenericTableConstants.ERR_TOO_MANY_FIELDS);
        }

        Schema.DescribeSObjectResult objectDescribe = describeQueryableObject(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

        GenericQueryResult result = new GenericQueryResult();
        result.columns = new List<ColumnInfo>();
        result.rows = new List<Map<String, Object>>();
        result.warnings = new List<String>();

        List<String> selectFields = new List<String>();
        Set<String> seen = new Set<String>();
        Boolean removedInaccessible = false;

        for (String requested : fieldApiNames) {
            if (String.isBlank(requested)) {
                throw new IllegalArgumentException(GenericTableConstants.ERR_BLANK_FIELD);
            }
            String key = requested.trim().toLowerCase();
            if (key.contains('.')) {
                throw new IllegalArgumentException(GenericTableConstants.ERR_RELATIONSHIP_FIELD);
            }
            if (!seen.add(key)) {
                continue;
            }
            Schema.SObjectField sField = fieldMap.get(key);
            if (sField == null) {
                throw new IllegalArgumentException(GenericTableConstants.ERR_UNKNOWN_FIELD);
            }
            Schema.DescribeFieldResult fieldDescribe = sField.getDescribe();
            if (!fieldDescribe.isAccessible()) {
                removedInaccessible = true;
                continue;
            }
            if (fieldDescribe.getType() == Schema.DisplayType.ADDRESS
                || fieldDescribe.getType() == Schema.DisplayType.LOCATION) {
                throw new IllegalArgumentException(GenericTableConstants.ERR_UNSUPPORTED_FIELD);
            }
            selectFields.add(fieldDescribe.getName());
            result.columns.add(buildColumn(fieldDescribe));
        }

        if (removedInaccessible) {
            result.warnings.add(GenericTableConstants.WARN_FIELDS_REMOVED);
        }
        if (selectFields.isEmpty()) {
            throw new IllegalArgumentException(GenericTableConstants.ERR_NO_ACCESSIBLE_FIELDS);
        }
        // Rows always carry Id so the table has a key field, even when Id is not a column
        if (!seen.contains('id')) {
            selectFields.add('Id');
        }

        Integer effectiveLimit = (rowLimit == null || rowLimit <= 0)
            ? GenericTableConstants.DEFAULT_ROW_LIMIT
            : Math.min(rowLimit, GenericTableConstants.MAX_ROWS);

        List<SObject> records = GenericRecordSelector.selectRecords(objectDescribe.getName(), selectFields, effectiveLimit);
        for (SObject record : records) {
            Map<String, Object> row = new Map<String, Object>();
            for (String fieldName : selectFields) {
                row.put(fieldName, record.get(fieldName));
            }
            result.rows.add(row);
        }
        return result;
    }

    private static Schema.DescribeSObjectResult describeQueryableObject(String objectApiName) {
        Schema.SObjectType objectType = String.isBlank(objectApiName)
            ? null
            : Schema.getGlobalDescribe().get(objectApiName.trim().toLowerCase());
        if (objectType == null) {
            throw new IllegalArgumentException(GenericTableConstants.ERR_UNKNOWN_OBJECT);
        }
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        if (!objectDescribe.isAccessible() || !objectDescribe.isQueryable()) {
            throw new IllegalArgumentException(GenericTableConstants.ERR_UNKNOWN_OBJECT);
        }
        return objectDescribe;
    }

    private static ColumnInfo buildColumn(Schema.DescribeFieldResult fieldDescribe) {
        ColumnInfo column = new ColumnInfo();
        column.label = fieldDescribe.getLabel();
        column.fieldName = fieldDescribe.getName();
        column.type = toColumnType(fieldDescribe.getType());
        return column;
    }

    private static String toColumnType(Schema.DisplayType displayType) {
        if (displayType == Schema.DisplayType.BOOLEAN) {
            return GenericTableConstants.TYPE_BOOLEAN;
        }
        if (displayType == Schema.DisplayType.DATE || displayType == Schema.DisplayType.DATETIME) {
            return GenericTableConstants.TYPE_DATE;
        }
        if (displayType == Schema.DisplayType.INTEGER
            || displayType == Schema.DisplayType.LONG
            || displayType == Schema.DisplayType.DOUBLE
            || displayType == Schema.DisplayType.CURRENCY
            || displayType == Schema.DisplayType.PERCENT) {
            return GenericTableConstants.TYPE_NUMBER;
        }
        if (displayType == Schema.DisplayType.EMAIL) {
            return GenericTableConstants.TYPE_EMAIL;
        }
        if (displayType == Schema.DisplayType.PHONE) {
            return GenericTableConstants.TYPE_PHONE;
        }
        if (displayType == Schema.DisplayType.URL) {
            return GenericTableConstants.TYPE_URL;
        }
        return GenericTableConstants.TYPE_TEXT;
    }
}
