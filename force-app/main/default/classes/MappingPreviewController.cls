public with sharing class MappingPreviewController {
    @AuraEnabled(cacheable=true)
    public static String previewTemplate(String template, Map<String,Object> context) {
        try {
            return MappingHelper.applyTemplate(template, context);
        } catch (Exception e) {
            throw new AuraHandledException('Template preview error: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String previewDeclarative(String rulesJson, Map<String,Object> context) {
        try {
            return MappingHelper.applyDeclarative(rulesJson, context);
        } catch (Exception e) {
            throw new AuraHandledException('Declarative preview error: ' + e.getMessage());
        }
    }
}
