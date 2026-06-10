/**
 * @description Provides two complementary payload-building strategies: lightweight token substitution
 *              for simple cases and a rule-driven declarative mapper for structured transformations.
 *              Both methods accept a generic context map so they work with SObjects, plain Maps, or
 *              any combination.
 */
public with sharing class MappingHelper {

    /**
     * @description Replaces `{{Key}}` tokens in a template string with values from the context map.
     *              Only top-level keys are resolved; nested paths are not supported in this mode.
     * @param template Template string containing `{{Key}}` placeholders.
     * @param context  Map of key-value pairs used to resolve placeholders.
     * @return         Template string with all matching placeholders substituted, or an empty string if template is null.
     */
    public static String applyTemplate(String template, Map<String, Object> context) {
        if (template == null) return '';
        String out = template;
        for (String k : context.keySet()) {
            Object v = context.get(k);
            String sval = (v == null) ? '' : String.valueOf(v);
            out = out.replace('{{' + k + '}}', sval);
        }
        return out;
    }

    /**
     * @description Transforms a context map into a JSON payload by applying a declarative rule set.
     *              Each rule is a JSON object with a `source` dotted path (or `constant:<value>`) and a
     *              `target` dotted path where the resolved value is written in the output map.
     *              Example rule: `{"source":"Account.Name","target":"account.name"}`.
     * @param rulesJson JSON array string of mapping rule objects.
     * @param context   Source data map used to resolve dotted source paths.
     * @return          Serialised JSON string of the mapped output object, or '{}' when rulesJson is blank.
     */
    public static String applyDeclarative(String rulesJson, Map<String, Object> context) {
        if (String.isBlank(rulesJson)) return '{}';
        List<Object> rules = (List<Object>) JSON.deserializeUntyped(rulesJson);
        Map<String, Object> out = new Map<String, Object>();
        for (Object o : rules) {
            Map<String, Object> r = (Map<String, Object>) o;
            String source = (String) r.get('source');
            String target = (String) r.get('target');
            Object val = evaluateSourcePath(source, context);
            setValueAtPath(out, target, val);
        }
        return JSON.serialize(out);
    }

    /**
     * @description Walks a dotted source path through the context map, supporting both plain Map entries
     *              and SObject field access. Paths prefixed with `constant:` return the literal suffix value.
     * @param path    Dotted source path string (e.g. 'Account.Name') or `constant:<value>`.
     * @param context Root context map to traverse.
     * @return        Resolved value, or null if any segment in the path is not found.
     */
    private static Object evaluateSourcePath(String path, Map<String, Object> context) {
        if (path == null) return null;
        if (path.startsWith('constant:')) return path.substringAfter('constant:');
        List<String> parts = path.split('\\.');
        Object cur = context.get(parts[0]);
        for (Integer i=1;i<parts.size() && cur!=null;i++) {
            if (cur instanceof Map<String,Object>) {
                cur = ((Map<String,Object>)cur).get(parts[i]);
            } else {
                try { cur = ((SObject)cur).get(parts[i]); } catch (Exception e) { cur = null; }
            }
        }
        return cur;
    }

    /**
     * @description Writes a value into a nested output map at the specified dotted path,
     *              creating intermediate Map nodes as required.
     * @param root  Top-level output map to write into.
     * @param path  Dotted target path (e.g. 'address.city').
     * @param value Value to place at the leaf node.
     */
    private static void setValueAtPath(Map<String,Object> root, String path, Object value) {
        if (String.isBlank(path)) return;
        List<String> parts = path.split('\\.');
        Map<String,Object> cur = root;
        for (Integer i=0;i<parts.size();i++) {
            String p = parts[i];
            if (i==parts.size()-1) {
                cur.put(p, value);
            } else {
                if (!cur.containsKey(p) || !(cur.get(p) instanceof Map<String,Object>)) {
                    cur.put(p, new Map<String,Object>());
                }
                cur = (Map<String,Object>) cur.get(p);
            }
        }
    }
}
