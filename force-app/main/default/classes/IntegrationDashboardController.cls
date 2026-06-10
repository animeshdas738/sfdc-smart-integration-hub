/**
 * @description Aura-enabled controller that aggregates Integration_Log__c records into summary statistics
 *              for the integration health dashboard Lightning Web Component. All queries are read-only
 *              aggregate SOQLs with a configurable look-back window.
 */
public with sharing class IntegrationDashboardController {

    /**
     * @description Holds the org-wide rollup statistics returned to the dashboard component.
     */
    public class DashboardStats {
        @AuraEnabled public Integer totalRequests   { get; set; }
        @AuraEnabled public Integer successCount    { get; set; }
        @AuraEnabled public Integer failureCount    { get; set; }
        @AuraEnabled public Integer retryCount      { get; set; }
        @AuraEnabled public Decimal avgLatencyMs    { get; set; }
        @AuraEnabled public Decimal successRate     { get; set; }
        @AuraEnabled public List<IntegrationStat> byIntegration { get; set; }
    }

    /**
     * @description Holds per-integration breakdown statistics included in DashboardStats.byIntegration.
     */
    public class IntegrationStat {
        @AuraEnabled public String  integrationName { get; set; }
        @AuraEnabled public Integer total           { get; set; }
        @AuraEnabled public Integer successCount    { get; set; }
        @AuraEnabled public Integer failureCount    { get; set; }
        @AuraEnabled public Integer retryCount      { get; set; }
        @AuraEnabled public Decimal avgLatencyMs    { get; set; }
    }

    /**
     * @description Returns aggregated statistics for all Integration_Log__c records created within
     *              the specified look-back window, including overall counts by status, average latency,
     *              success rate percentage, and a per-integration breakdown.
     * @param daysBack Number of days back from now to include in the query window (e.g. 7 for one week).
     * @return         DashboardStats object populated with totals and per-integration breakdowns.
     */
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
