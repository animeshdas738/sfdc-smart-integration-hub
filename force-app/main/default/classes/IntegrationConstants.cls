public class IntegrationConstants {
    // Status values
    public static final String STATUS_QUEUED = 'Queued';
    public static final String STATUS_INPROGRESS = 'InProgress';
    public static final String STATUS_SUCCESS = 'Success';
    public static final String STATUS_RETRYSCHEDULED = 'RetryScheduled';
    public static final String STATUS_DEADLETTER = 'DeadLetter';
    public static final String STATUS_FAILED = 'Failed';

    // Callout config
    public static final String DEFAULT_NAMED_CREDENTIAL = 'Test_Http_Bin';
    public static final String DEFAULT_RESOURCE_PATH = '/resource';
    public static final String HEADER_CONTENT_TYPE = 'Content-Type';
    public static final String CONTENT_TYPE_JSON = 'application/json';

    // Scheduler/Executor settings
    public static final Integer SCHEDULER_QUERY_LIMIT = 200;
    public static final Integer EXECUTOR_CHUNK_SIZE = 25;
}
