/**
 * @description Thin wrapper around the Salesforce Http class that executes outbound callouts
 *              via Named Credentials and normalises the response into a simple result object.
 */
public with sharing class CalloutWrapper {

    /**
     * @description Holds the HTTP status code and response body returned from an outbound callout.
     */
    public class CalloutResult {
        public Integer statusCode;
        public String body;
        public Map<String, String> headers = new Map<String, String>();
    }

    /**
     * @description Sends an HTTP request to the specified Named Credential endpoint with configurable method.
     *              In test context the callout is made to a dummy HTTPS endpoint so that HttpCalloutMock
     *              can intercept it without Named Credential resolution issues.
     * @param namedCredential API name of the Named Credential (e.g. 'Gemini').
     * @param path            Resource path appended to the Named Credential base URL (e.g. '/v1/chat').
     * @param body            JSON request body string (not used for GET requests).
     * @param httpMethod      HTTP method (GET, POST, PUT, PATCH, DELETE).
     * @return                CalloutResult containing the HTTP status code and response body.
     */
    public static CalloutResult callEndpoint(String namedCredential, String path, String body, String httpMethod) {
        HttpRequest req = new HttpRequest();
        if (Test.isRunningTest()) {
            req.setEndpoint('https://example.invalid' + path);
        } else {
            req.setEndpoint('callout:' + namedCredential + path);
        }
        req.setMethod(httpMethod);
        req.setHeader(IntegrationConstants.HEADER_CONTENT_TYPE, IntegrationConstants.CONTENT_TYPE_JSON);
        if (body != null && !httpMethod.equalsIgnoreCase('GET')) {
            req.setBody(body);
        }

        Http http = new Http();
        CalloutResult res = new CalloutResult();
        try {
            HTTPResponse r = http.send(req);
            res.statusCode = r.getStatusCode();
            res.body = r.getBody();
        } catch (Exception ex) {
            res.statusCode = null;
            res.body = ex.getMessage();
        }
        return res;
    }

    /**
     * @description Sends an HTTP POST to the specified Named Credential endpoint and returns the result.
     *              Provided for backward compatibility with existing code.
     * @param namedCredential API name of the Named Credential (e.g. 'Gemini').
     * @param path            Resource path appended to the Named Credential base URL (e.g. '/v1/chat').
     * @param body            JSON request body string.
     * @return                CalloutResult containing the HTTP status code and response body.
     */
    public static CalloutResult postToNamedCredential(String namedCredential, String path, String body) {
        return callEndpoint(namedCredential, path, body, 'POST');
    }
}
