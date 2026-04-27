public with sharing class MappingHelper {
    // Apply a simple token template using {{Key}} tokens replaced from context map (keys are top-level only)
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

    // Apply declarative mapping: rules is a JSON array like [{"source":"Account.Name","target":"accountName"}, ...]
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
