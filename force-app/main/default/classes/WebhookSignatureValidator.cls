/**
 * @description Validates webhook signatures using HMAC-SHA256 or RSA-SHA256.
 *              Supports constant-time comparison to prevent timing attacks.
 */
public class WebhookSignatureValidator {
    private Webhook_Endpoint__c endpoint;

    public WebhookSignatureValidator(Webhook_Endpoint__c ep) {
        this.endpoint = ep;
    }

    /**
     * @description Validate webhook signature based on configured algorithm.
     *
     * @param payload   The raw webhook payload (JSON body as string)
     * @param signature The signature from request header (e.g., "sha256=abc123...")
     * @return          true if valid, false otherwise
     */
    public Boolean isValid(String payload, String signature) {
        if (String.isBlank(signature)) {
            return false;
        }

        if (endpoint.Signature_Algorithm__c == 'HMAC_SHA256') {
            return validateHMAC_SHA256(payload, signature);
        } else if (endpoint.Signature_Algorithm__c == 'RSA_SHA256') {
            return validateRSA_SHA256(payload, signature);
        }

        return false;
    }

    /**
     * @description Validate HMAC-SHA256 signature.
     *
     * @param payload   Raw webhook payload
     * @param signature Signature from header (may be prefixed: "sha256=...")
     * @return          true if valid
     */
    private Boolean validateHMAC_SHA256(String payload, String signature) {
        String expectedSig = signature;
        if (signature.startsWith('sha256=')) {
            expectedSig = signature.substring(7);
        }

        String secret = retrieveSecret();
        if (String.isBlank(secret)) {
            return false;
        }

        Blob payloadBlob = Blob.valueOf(payload);
        Blob secretBlob = Blob.valueOf(secret);
        Blob computedSignature = Crypto.generateMac('HmacSHA256', payloadBlob, secretBlob);
        String computedHex = EncodingUtil.convertToHex(computedSignature);

        return constantTimeEquals(computedHex.toLowerCase(), expectedSig.toLowerCase());
    }

    /**
     * @description Validate RSA-SHA256 signature (placeholder for future implementation).
     *
     * @param payload   Raw webhook payload
     * @param signature RSA signature
     * @return          true if valid
     */
    private Boolean validateRSA_SHA256(String payload, String signature) {
        throw new UnsupportedOperationException('RSA-SHA256 validation not yet implemented');
    }

    /**
     * @description Retrieve webhook secret from Named Credential.
     *              This is a placeholder; actual implementation depends on secure secret storage.
     *
     * @return Secret value or blank if not found
     */
    private String retrieveSecret() {
        // TODO: Implement secure retrieval from Named Credentials
        // Placeholder - should retrieve from Named Credential via callout or custom setting
        // For now, return empty string (will fail validation as expected)
        return '';
    }

    /**
     * @description Constant-time string comparison to prevent timing attacks.
     *
     * @param a First string
     * @param b Second string
     * @return  true if strings match
     */
    private Boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null || a.length() != b.length()) {
            return false;
        }

        Integer mismatch = 0;
        for (Integer i = 0; i < a.length(); i++) {
            if (a.charAt(i) != b.charAt(i)) {
                mismatch++;
            }
        }
        return mismatch == 0;
    }
}
