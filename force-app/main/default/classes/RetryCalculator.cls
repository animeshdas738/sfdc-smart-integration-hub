public with sharing class RetryCalculator {
    /**
     * Compute next attempt datetime using exponential backoff with jitter.
     * attempts: number of attempts already performed (0-based)
     * baseSeconds: base delay in seconds
     */
    public static Datetime computeNextAttempt(Integer attempts, Integer baseSeconds) {
        Integer att = (attempts == null) ? 0 : attempts;
        // delay = baseSeconds * (2 ^ attempts)
        Double delay = baseSeconds * Math.pow(2, Math.max(0, att));
        Integer jitter = Math.mod(Math.abs(Crypto.getRandomInteger()), baseSeconds);
        Integer totalSeconds = Integer.valueOf(Math.round(delay)) + jitter;
        return Datetime.now().addSeconds(totalSeconds);
    }
}
