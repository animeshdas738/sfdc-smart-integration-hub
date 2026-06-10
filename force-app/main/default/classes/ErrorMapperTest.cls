@isTest
private class ErrorMapperTest {

    @isTest static void testClassifyTransientOnException() {
        ErrorMapper.ErrorResult r = ErrorMapper.classify(null, new CalloutException('connection timeout'));
        System.assertEquals(ErrorMapper.ErrorCategory.TRANSIENT, r.category);
        System.assertEquals('connection timeout', r.message);
    }

    @isTest static void testClassifyTransientOnNullStatus() {
        ErrorMapper.ErrorResult r = ErrorMapper.classify(null, null);
        System.assertEquals(ErrorMapper.ErrorCategory.TRANSIENT, r.category);
        System.assertEquals('No HTTP status', r.message);
    }

    @isTest static void testClassifyTransientOn5xx() {
        ErrorMapper.ErrorResult r = ErrorMapper.classify(503, null);
        System.assertEquals(ErrorMapper.ErrorCategory.TRANSIENT, r.category);
    }

    @isTest static void testClassifyTransientOn429() {
        ErrorMapper.ErrorResult r = ErrorMapper.classify(429, null);
        System.assertEquals(ErrorMapper.ErrorCategory.TRANSIENT, r.category);
    }

    @isTest static void testClassifyPermanentOn4xx() {
        ErrorMapper.ErrorResult r = ErrorMapper.classify(422, null);
        System.assertEquals(ErrorMapper.ErrorCategory.PERMANENT, r.category);
    }

    @isTest static void testClassifyPermanentOnUnexpectedStatus() {
        ErrorMapper.ErrorResult r = ErrorMapper.classify(301, null);
        System.assertEquals(ErrorMapper.ErrorCategory.PERMANENT, r.category);
    }
}
