/**
 * @description Classifies outbound HTTP errors into TRANSIENT (retryable) or PERMANENT (non-retryable)
 *              categories so that callers can decide whether to schedule a retry or dead-letter the request.
 */
public with sharing class ErrorMapper {

    /** @description Indicates whether a failure is worth retrying (TRANSIENT) or should be abandoned (PERMANENT). */
    public enum ErrorCategory { TRANSIENT, PERMANENT }

    /**
     * @description Wraps the classification outcome returned by {@link #classify}.
     */
    public class ErrorResult {
        public ErrorCategory category;
        public String message;
    }

    /**
     * @description Determines the error category from an HTTP status code or a caught exception.
     *              Exceptions and 5xx/429 responses are TRANSIENT; 4xx responses are PERMANENT.
     * @param httpStatus HTTP status code from the callout response, or null if an exception occurred.
     * @param ex         Exception thrown during the callout, or null if a status code is available.
     * @return           ErrorResult containing the category and a human-readable message.
     */
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
