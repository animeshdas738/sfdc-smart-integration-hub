public with sharing class ErrorMapper {
    public enum ErrorCategory { TRANSIENT, PERMANENT }

    public class ErrorResult {
        public ErrorCategory category;
        public String message;
    }

    public static ErrorResult classify(Integer httpStatus, Exception ex) {
        ErrorResult r = new ErrorResult();
        if (ex != null) {
            // treat callout exceptions as transient by default
            r.category = ErrorCategory.TRANSIENT;
            r.message = ex.getMessage();
            return r;
        }
        if (httpStatus == null) {
            r.category = ErrorCategory.TRANSIENT;
            r.message = 'No HTTP status';
            return r;
        }
        if (httpStatus >= 500 || httpStatus == 429) {
            r.category = ErrorCategory.TRANSIENT;
            r.message = 'Server or rate limit: ' + String.valueOf(httpStatus);
        } else if (httpStatus >= 400) {
            r.category = ErrorCategory.PERMANENT;
            r.message = 'Client error: ' + String.valueOf(httpStatus);
        } else {
            r.category = ErrorCategory.PERMANENT;
            r.message = 'Unexpected status: ' + String.valueOf(httpStatus);
        }
        return r;
    }
}
