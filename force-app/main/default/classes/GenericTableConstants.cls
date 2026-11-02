/**
 * @description Constants for the generic table component (genericDataTable). Kept separate from
 *              IntegrationConstants because the table is not specific to the integration framework.
 */
public with sharing class GenericTableConstants {
    // Row and field limits
    public static final Integer MAX_ROWS = 500;
    public static final Integer DEFAULT_ROW_LIMIT = 50;
    public static final Integer MAX_FIELDS = 30;

    // Column types understood by lightning-datatable
    public static final String TYPE_TEXT = 'text';
    public static final String TYPE_NUMBER = 'number';
    public static final String TYPE_BOOLEAN = 'boolean';
    public static final String TYPE_DATE = 'date';
    public static final String TYPE_EMAIL = 'email';
    public static final String TYPE_PHONE = 'phone';
    public static final String TYPE_URL = 'url';

    // Validation of object and field names used in dynamic SOQL
    public static final String IDENTIFIER_REGEX = '[A-Za-z][A-Za-z0-9_]*';

    // Messages returned to the user
    public static final String ERR_INVALID_INPUT = 'Select an object and at least one field.';
    public static final String ERR_QUERY_FAILED = 'The table data could not be loaded.';
    public static final String ERR_UNKNOWN_OBJECT = 'The object is not available.';
    public static final String ERR_BLANK_FIELD = 'A field name is blank.';
    public static final String ERR_RELATIONSHIP_FIELD = 'Relationship fields are not supported.';
    public static final String ERR_UNKNOWN_FIELD = 'A field does not exist on this object.';
    public static final String ERR_UNSUPPORTED_FIELD = 'Address and location fields are not supported.';
    public static final String ERR_TOO_MANY_FIELDS = 'Too many fields were requested.';
    public static final String ERR_NO_ACCESSIBLE_FIELDS = 'None of the requested fields are accessible.';
    public static final String ERR_INVALID_IDENTIFIER = 'A field or object name is not valid.';
    public static final String WARN_FIELDS_REMOVED = 'Some fields are not accessible to you and were left out.';
}
