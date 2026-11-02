import { LightningElement, api } from 'lwc';
import getRecords from '@salesforce/apex/GenericQueryController.getRecords';

const KEY_FIELD = 'Id';
const MSG_MISSING_INPUT = 'Select an object and at least one field.';
const MSG_LOAD_FAILED = 'Failed to load table data.';

/**
 * Read-only table that shows the rows of a query as a lightning-datatable.
 * Set objectApiName, fieldApiNames and (optionally) rowLimit before the component is inserted.
 * Call refresh() to reload the data.
 */
export default class GenericDataTable extends LightningElement {
    @api objectApiName;
    @api fieldApiNames = [];
    @api rowLimit;
    @api cardTitle = 'Records';

    columns = [];
    rows = [];
    warnings = [];
    error;
    isLoading = true;
    keyField = KEY_FIELD;

    connectedCallback() {
        this.load();
    }

    @api
    refresh() {
        this.load();
    }

    load() {
        if (!this.objectApiName || !this.fieldApiNames || this.fieldApiNames.length === 0) {
            this.error = MSG_MISSING_INPUT;
            this.columns = [];
            this.rows = [];
            this.warnings = [];
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.error = undefined;

        getRecords({
            objectApiName: this.objectApiName,
            fieldApiNames: this.fieldApiNames,
            rowLimit: this.rowLimit
        })
            .then((result) => {
                this.columns = result.columns.map((column) => ({
                    label: column.label,
                    fieldName: column.fieldName,
                    type: column.type
                }));
                this.rows = result.rows;
                this.warnings = result.warnings || [];
            })
            .catch((err) => {
                this.error = err && err.body && err.body.message ? err.body.message : MSG_LOAD_FAILED;
                this.columns = [];
                this.rows = [];
                this.warnings = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasError() {
        return !!this.error;
    }

    get hasWarnings() {
        return this.warnings.length > 0;
    }

    get showTable() {
        return !this.isLoading && !this.error && this.rows.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.error && this.rows.length === 0;
    }
}
