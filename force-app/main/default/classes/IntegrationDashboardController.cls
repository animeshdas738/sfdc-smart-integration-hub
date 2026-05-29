public with sharing class IntegrationDashboardController {

    public class DashboardStats {
        @AuraEnabled public Integer totalRequests   { get; set; }
        @AuraEnabled public Integer successCount    { get; set; }
        @AuraEnabled public Integer failureCount    { get; set; }
        @AuraEnabled public Integer retryCount      { get; set; }
        @AuraEnabled public Decimal avgLatencyMs    { get; set; }
        @AuraEnabled public Decimal successRate     { get; set; }
        @AuraEnabled public List<IntegrationStat> byIntegration { get; set; }
    }

    public class IntegrationStat {
        @AuraEnabled public String  integrationName { get; set; }
        @AuraEnabled public Integer total           { get; set; }
        @AuraEnabled public Integer successCount    { get; set; }
        @AuraEnabled public Integer failureCount    { get; set; }
        @AuraEnabled public Integer retryCount      { get; set; }
        @AuraEnabled public Decimal avgLatencyMs    { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static DashboardStats getStats(Integer daysBack) {
        Datetime since = System.now().addDays(-daysBack);

        // Overall totals grouped by status
        List<AggregateResult> byStatus = [
            SELECT Status__c status, COUNT(Id) cnt
            FROM Integration_Log__c
            WHERE CreatedDate >= :since
            GROUP BY Status__c
        ];

        // Average latency only for completed successful logs that have duration recorded
        List<AggregateResult> latencyResult = [
            SELECT AVG(Duration_ms__c) avgDur
            FROM Integration_Log__c
            WHERE CreatedDate >= :since
              AND Status__c = 'Success'
              AND Duration_ms__c != null
        ];

        DashboardStats stats    = new DashboardStats();
        stats.totalRequests     = 0;
        stats.successCount      = 0;
        stats.failureCount      = 0;
        stats.retryCount        = 0;
        stats.avgLatencyMs      = null;
        stats.successRate       = 0;

        for (AggregateResult ar : byStatus) {
            String  status = (String)  ar.get('status');
            Integer cnt    = (Integer) ar.get('cnt');
            stats.totalRequests += cnt;
            if (status == IntegrationConstants.STATUS_SUCCESS)                                          stats.successCount += cnt;
            if (status == IntegrationConstants.STATUS_DEADLETTER || status == IntegrationConstants.STATUS_FAILED)  stats.failureCount += cnt;
            if (status == IntegrationConstants.STATUS_RETRYSCHEDULED)                                   stats.retryCount   += cnt;
        }

        if (!latencyResult.isEmpty() && latencyResult[0].get('avgDur') != null) {
            stats.avgLatencyMs = ((Decimal) latencyResult[0].get('avgDur')).setScale(0);
        }

        if (stats.totalRequests > 0) {
            stats.successRate = ((Decimal) stats.successCount / stats.totalRequests * 100).setScale(1);
        }

        // Per-integration breakdown grouped by name + status
        List<AggregateResult> byIntegration = [
            SELECT Integration_Name__c iname, Status__c status, COUNT(Id) cnt, AVG(Duration_ms__c) avgDur
            FROM Integration_Log__c
            WHERE CreatedDate >= :since
            GROUP BY Integration_Name__c, Status__c
            ORDER BY Integration_Name__c
        ];

        Map<String, IntegrationStat> statMap = new Map<String, IntegrationStat>();
        for (AggregateResult ar : byIntegration) {
            String  name   = (String)  ar.get('iname');
            String  status = (String)  ar.get('status');
            Integer cnt    = (Integer) ar.get('cnt');

            if (!statMap.containsKey(name)) {
                IntegrationStat s  = new IntegrationStat();
                s.integrationName  = name;
                s.total            = 0;
                s.successCount     = 0;
                s.failureCount     = 0;
                s.retryCount       = 0;
                s.avgLatencyMs     = null;
                statMap.put(name, s);
            }

            IntegrationStat s = statMap.get(name);
            s.total += cnt;
            if (status == IntegrationConstants.STATUS_SUCCESS) {
                s.successCount += cnt;
                if (ar.get('avgDur') != null) {
                    s.avgLatencyMs = ((Decimal) ar.get('avgDur')).setScale(0);
                }
            }
            if (status == IntegrationConstants.STATUS_DEADLETTER || status == IntegrationConstants.STATUS_FAILED) {
                s.failureCount += cnt;
            }
            if (status == IntegrationConstants.STATUS_RETRYSCHEDULED) {
                s.retryCount += cnt;
            }
        }

        stats.byIntegration = statMap.values();
        return stats;
    }
}
