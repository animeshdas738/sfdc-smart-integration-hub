/**
 * @description Result object returned by WebhookHandler implementations.
 *              Encapsulates processing status, errors, and optional downstream events.
 */
public class WebhookResult {
    public enum Status { SUCCESS, FAILED, SKIPPED }

    public Status status;
    public String errorCode;
    public String errorMessage;
    public String relatedRecordId;
    public String relatedRecordType;
    public Integration_Event__e integrationEvent;

    public WebhookResult(Status s) {
        this.status = s;
    }

    public WebhookResult(Status s, String code, String message) {
        this.status = s;
        this.errorCode = code;
        this.errorMessage = message;
    }
}
