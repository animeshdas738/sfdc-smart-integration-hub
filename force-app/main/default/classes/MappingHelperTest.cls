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
}
