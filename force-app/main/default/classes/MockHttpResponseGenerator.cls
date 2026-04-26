@isTest
global class MockHttpResponseGenerator implements HttpCalloutMock {
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
