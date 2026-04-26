public with sharing class CalloutWrapper {
    public class CalloutResult {
        public Integer statusCode;
        public String body;
        public Map<String, String> headers = new Map<String, String>();
    }

    public static CalloutResult postToNamedCredential(String namedCredential, String path, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + namedCredential + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);

        Http http = new Http();
        CalloutResult res = new CalloutResult();
        try {
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
