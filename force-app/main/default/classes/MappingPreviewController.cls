/**
 * @description Aura-enabled controller that exposes MappingHelper methods to Lightning Web Components,
 *              allowing developers to preview payload transformations from the integration configuration UI.
 */
public with sharing class MappingPreviewController {

    /**
     * @description Previews the result of applying a token template against a sample context map.
     * @param template Template string containing `{{Key}}` placeholders.
     * @param context  Sample data map used to resolve placeholders.
     * @return         Rendered template string with placeholders substituted.
     * @throws AuraHandledException when template evaluation fails.
     */
    @AuraEnabled(cacheable=true)
    public static String previewTemplate(String template, Map<String,Object> context) {
        try {
            return MappingHelper.applyTemplate(template, context);
        } catch (Exception e) {
            throw new AuraHandledException('Template preview error: ' + e.getMessage());
        }
    }

    /**
     * @description Previews the result of applying a declarative rule set against a sample context map.
     * @param rulesJson JSON array string of mapping rule objects.
     * @param context   Sample data map used to resolve source paths.
     * @return          Serialised JSON string of the mapped output.
     * @throws AuraHandledException when rule evaluation fails.
     */
    @AuraEnabled(cacheable=true)
    public static String previewDeclarative(String rulesJson, Map<String,Object> context) {
        try {
            return MappingHelper.applyDeclarative(rulesJson, context);
        } catch (Exception e) {
            throw new AuraHandledException('Declarative preview error: ' + e.getMessage());
        }
    }
}
