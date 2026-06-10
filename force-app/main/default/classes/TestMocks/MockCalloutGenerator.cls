/**
 * @description Configurable HttpCalloutMock that returns a fixed HTTP status code and body string.
 *              Use this in test methods where a specific status/response combination is needed rather
 *              than the keyword-based behaviour of MockHttpResponseGenerator.
 */
@isTest
global class MockCalloutGenerator implements HttpCalloutMock {
    public Integer statusToReturn;
    public String bodyToReturn;

    /**
     * @description Constructs the mock with the HTTP status code and body to return for every request.
     * @param status HTTP status code to return (e.g. 200, 429, 500).
     * @param body   Response body string; null is converted to an empty string.
     */
    public MockCalloutGenerator(Integer status, String body) {
        this.statusToReturn = status;
        this.bodyToReturn = body;
    }

    /**
     * @description Returns the pre-configured HTTP response regardless of the request content.
     * @param req The outbound HTTP request intercepted by the mock framework.
     * @return    HTTPResponse with the configured status code, JSON Content-Type header, and body.
     */
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type','application/json');
        res.setStatusCode(statusToReturn);
        res.setBody(bodyToReturn == null ? '' : bodyToReturn);
        return res;
    }
}