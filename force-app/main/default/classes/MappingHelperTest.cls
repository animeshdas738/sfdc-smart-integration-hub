@isTest
private class MappingHelperTest {
    @isTest static void testTemplateApply() {
        String template = '{"name":"{{Name}}","meta":{"source":"{{Source}}"}}';
        Map<String,Object> ctx = new Map<String,Object>{'Name' => 'Acme', 'Source' => 'ERP'};
        String out = MappingHelper.applyTemplate(template, ctx);
        System.assert(out.contains('Acme'));
        System.assert(out.contains('ERP'));
    }

    @isTest static void testDeclarativeMapping() {
        String rules = '[{"source":"constant:ERP","target":"meta.source"},{"source":"Account.Name","target":"accountName"}]';
        Map<String,Object> acct = new Map<String,Object>{'Name' => 'Acme'};
        Map<String,Object> ctx = new Map<String,Object>{'Account' => acct};
        String out = MappingHelper.applyDeclarative(rules, ctx);
        System.assert(out.contains('Acme'));
        System.assert(out.contains('ERP'));
    }

    @isTest static void testDeclarativeMappingWithSObject() {
        // Covers the SObject dot-walk branch (line 38): context value is an SObject, not a Map
        Account acct = new Account(Name = 'TestCorp');
        Map<String,Object> ctx = new Map<String,Object>{ 'Account' => acct };
        String rules = '[{"source":"Account.Name","target":"companyName"}]';
        String out = MappingHelper.applyDeclarative(rules, ctx);
        Map<String,Object> result = (Map<String,Object>) JSON.deserializeUntyped(out);
        System.assertEquals('TestCorp', result.get('companyName'));
    }

    @isTest static void testApplyTemplateNullTemplate() {
        System.assertEquals('', MappingHelper.applyTemplate(null, new Map<String,Object>()));
    }

    @isTest static void testApplyDeclarativeBlankRules() {
        System.assertEquals('{}', MappingHelper.applyDeclarative('', new Map<String,Object>()));
    }
}
