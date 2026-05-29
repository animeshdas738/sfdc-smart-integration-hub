import { LightningElement, track } from 'lwc';
import getStats from '@salesforce/apex/IntegrationDashboardController.getStats';

const COLUMNS = [
    { label: 'Integration Name',  fieldName: 'integrationName', type: 'text',   wrapText: true },
    { label: 'Total',             fieldName: 'total',           type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Success',           fieldName: 'successCount',    type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Failures',          fieldName: 'failureCount',    type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Retries',           fieldName: 'retryCount',      type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Avg Latency (ms)',  fieldName: 'avgLatencyMs',    type: 'number', cellAttributes: { alignment: 'left' } },
];

export default class IntegrationDashboard extends LightningElement {

    @track stats;
    @track error;
    @track isLoading = true;
    @track selectedDays = '30';

    columns = COLUMNS;

    dateRangeOptions = [
        { label: 'Today',        value: '1'  },
        { label: 'Last 7 Days',  value: '7'  },
        { label: 'Last 30 Days', value: '30' },
        { label: 'Last 90 Days', value: '90' },
    ];

    connectedCallback() {
        this.loadStats();
    }

    loadStats() {
        this.isLoading = true;
        this.error     = undefined;

        getStats({ daysBack: parseInt(this.selectedDays, 10) })
            .then(result => {
                this.stats = result;
            })
            .catch(err => {
                this.error = (err.body && err.body.message) ? err.body.message : 'Failed to load dashboard data.';
                this.stats = undefined;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleDateRangeChange(event) {
        this.selectedDays = event.detail.value;
        this.loadStats();
    }

    get successRateFormatted() {
        if (!this.stats) return '—';
        return this.stats.successRate + '%';
    }

    get avgLatencyFormatted() {
        if (!this.stats || this.stats.avgLatencyMs == null) return '—';
        return this.stats.avgLatencyMs + ' ms';
    }

    get hasStats() {
        return !this.isLoading && !this.error && this.stats && this.stats.totalRequests > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.error && this.stats && this.stats.totalRequests === 0;
    }
}
