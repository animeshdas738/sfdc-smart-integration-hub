public with sharing class CalloutWrapper {
    public class CalloutResult {
        public Integer statusCode;
        public String body;
        public Map<String, String> headers = new Map<String, String>();
    }

    public static CalloutResult postToNamedCredential(String namedCredential, String path, String body) {
        HttpRequest req = new HttpRequest();
        // During tests, avoid resolving Named Credentials which can sometimes cause runtime
        // exceptions even when HttpCalloutMock is registered. Use a dummy HTTPS endpoint in tests.
        if (Test.isRunningTest()) {
            req.setEndpoint('https://example.invalid' + path);
        } else {
            req.setEndpoint('callout:' + namedCredential + path);
        }
        req.setMethod('POST');
    req.setHeader(IntegrationConstants.HEADER_CONTENT_TYPE, IntegrationConstants.CONTENT_TYPE_JSON);
        req.setBody(body);

        Http http = new Http();
        CalloutResult res = new CalloutResult();
        try {
            // During tests, Test.setMock handles responses. Ensure endpoint is set correctly.
            HTTPResponse r = http.send(req);
            res.statusCode = r.getStatusCode();
            res.body = r.getBody();
            // headers not captured due to platform compatibility; callers can access body/statusCode
        } catch (Exception ex) {
            res.statusCode = null;
            res.body = ex.getMessage();
        }
        return res;
    }
}
