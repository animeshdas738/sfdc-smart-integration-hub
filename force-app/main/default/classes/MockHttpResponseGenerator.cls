/**
 * @description Test HttpCalloutMock that returns response codes based on keywords in the request body.
 *              Include 'fail5xx' in the body to simulate a 500 server error, 'fail4xx' for a 400 client
 *              error, or any other content for a 200 success response.
 */
@isTest
global class MockHttpResponseGenerator implements HttpCalloutMock {

    /**
     * @description Inspects the request body and returns an appropriate mock HTTP response.
     * @param req The outbound HTTP request intercepted by the mock framework.
     * @return    HTTPResponse with status 200, 400, or 500 depending on body keywords.
     */
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        // Simple behavior: if payload contains 'fail5xx' return 500, if 'fail4xx' return 400, else 200
        String body = req.getBody();
        if (body != null && body.contains('fail5xx')) {
            res.setStatusCode(500);
            res.setBody('Server error');
        } else if (body != null && body.contains('fail4xx')) {
            res.setStatusCode(400);
            res.setBody('Client error');
        } else {
            res.setStatusCode(200);
            res.setBody('{"result":"ok"}');
        }
        return res;
    }
}
