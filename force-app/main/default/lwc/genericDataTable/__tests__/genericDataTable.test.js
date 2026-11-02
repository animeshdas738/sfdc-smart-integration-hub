import { createElement } from 'lwc';
import GenericDataTable from 'c/genericDataTable';
import getRecords from '@salesforce/apex/GenericQueryController.getRecords';

jest.mock(
    '@salesforce/apex/GenericQueryController.getRecords',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const SAMPLE_RESULT = {
    columns: [
        { label: 'Status', fieldName: 'Status__c', type: 'text' },
        { label: 'Integration', fieldName: 'Integration_Name__c', type: 'text' }
    ],
    rows: [
        { Id: 'a01000000000001AAA', Status__c: 'Success', Integration_Name__c: 'Gemini' },
        { Id: 'a01000000000002AAA', Status__c: 'Failed', Integration_Name__c: 'GenX' }
    ],
    warnings: []
};

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createTable(props = {}) {
    const element = createElement('c-generic-data-table', { is: GenericDataTable });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

describe('c-generic-data-table', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('calls getRecords with the object, fields and row limit', async () => {
        getRecords.mockResolvedValue(SAMPLE_RESULT);

        createTable({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c', 'Integration_Name__c'],
            rowLimit: 10
        });
        await flushPromises();

        expect(getRecords).toHaveBeenCalledTimes(1);
        expect(getRecords).toHaveBeenCalledWith({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c', 'Integration_Name__c'],
            rowLimit: 10
        });
    });

    it('renders the columns and rows returned by Apex', async () => {
        getRecords.mockResolvedValue(SAMPLE_RESULT);

        const element = createTable({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c', 'Integration_Name__c']
        });
        await flushPromises();

        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        expect(datatable).not.toBeNull();
        expect(datatable.keyField).toBe('Id');
        expect(datatable.columns).toHaveLength(2);
        expect(datatable.columns[0].fieldName).toBe('Status__c');
        expect(datatable.data).toHaveLength(2);
        expect(datatable.data[1].Status__c).toBe('Failed');
    });

    it('shows the error message and no table when Apex fails', async () => {
        getRecords.mockRejectedValue({ body: { message: 'The object is not available.' } });

        const element = createTable({
            objectApiName: 'No_Such_Object__c',
            fieldApiNames: ['Id']
        });
        await flushPromises();

        const error = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(error).not.toBeNull();
        expect(error.textContent).toBe('The object is not available.');
        expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();
    });

    it('shows a generic message when the error has no body', async () => {
        getRecords.mockRejectedValue(new Error('network'));

        const element = createTable({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c']
        });
        await flushPromises();

        const error = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(error.textContent).toBe('Failed to load table data.');
    });

    it('shows the empty state when no rows are returned', async () => {
        getRecords.mockResolvedValue({ columns: SAMPLE_RESULT.columns, rows: [], warnings: [] });

        const element = createTable({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c']
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();
        const empty = element.shadowRoot.querySelector('.slds-text-align_center');
        expect(empty).not.toBeNull();
        expect(empty.textContent).toBe('No records found.');
    });

    it('shows the spinner while the request is in progress', async () => {
        getRecords.mockReturnValue(new Promise(() => {}));

        const element = createTable({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c']
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();
    });

    it('shows the warnings returned with the result', async () => {
        getRecords.mockResolvedValue({
            columns: SAMPLE_RESULT.columns,
            rows: SAMPLE_RESULT.rows,
            warnings: ['Some fields are not accessible to you and were left out.']
        });

        const element = createTable({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c', 'Integration_Name__c']
        });
        await flushPromises();

        const warnings = element.shadowRoot.querySelectorAll('.slds-text-color_weak');
        expect(warnings).toHaveLength(1);
        expect(warnings[0].textContent).toBe('Some fields are not accessible to you and were left out.');
        expect(element.shadowRoot.querySelector('lightning-datatable')).not.toBeNull();
    });

    it('does not call Apex and shows a message when the object is missing', async () => {
        const element = createTable({
            fieldApiNames: ['Status__c']
        });
        await flushPromises();

        expect(getRecords).not.toHaveBeenCalled();
        const error = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(error.textContent).toBe('Select an object and at least one field.');
    });

    it('reloads the data when refresh() is called', async () => {
        getRecords.mockResolvedValue(SAMPLE_RESULT);

        const element = createTable({
            objectApiName: 'Integration_Log__c',
            fieldApiNames: ['Status__c']
        });
        await flushPromises();
        element.refresh();
        await flushPromises();

        expect(getRecords).toHaveBeenCalledTimes(2);
    });
});
