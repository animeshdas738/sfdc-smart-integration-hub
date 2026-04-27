import { LightningElement, track } from 'lwc';
import previewTemplate from '@salesforce/apex/MappingPreviewController.previewTemplate';
import previewDeclarative from '@salesforce/apex/MappingPreviewController.previewDeclarative';

export default class MappingPreview extends LightningElement {
    @track template = '{"accountName":"{{Account.Name}}","source":"{{Source}}"}';
    @track rules = '[{"source":"constant:ERP","target":"meta.source"},{"source":"Account.Name","target":"accountName"}]';
    @track sample = '{"Account":{"Name":"Acme Corp"},"Source":"ERP"}';
    @track output = '';

    handleTemplatePreview() {
        const ctx = JSON.parse(this.sample);
        previewTemplate({ template: this.template, context: ctx })
            .then(res => { this.output = res; })
            .catch(err => { this.output = 'Error: ' + err.body.message; });
    }

    handleDeclarativePreview() {
        const ctx = JSON.parse(this.sample);
        previewDeclarative({ rulesJson: this.rules, context: ctx })
            .then(res => { this.output = res; })
            .catch(err => { this.output = 'Error: ' + err.body.message; });
    }

    handleTemplateChange(event) {
        this.template = event.target.value;
    }

    handleRulesChange(event) {
        this.rules = event.target.value;
    }

    handleSampleChange(event) {
        this.sample = event.target.value;
    }
}
