@isTest
global class MockCalloutGenerator implements HttpCalloutMock {
    public Integer statusToReturn;
    public String bodyToReturn;

    public MockCalloutGenerator(Integer status, String body) {
        this.statusToReturn = status;
        this.bodyToReturn = body;
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type','application/json');
        res.setStatusCode(statusToReturn);
        res.setBody(bodyToReturn == null ? '' : bodyToReturn);
        return res;
    }
}
