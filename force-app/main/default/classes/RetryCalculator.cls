/**
 * @description Computes the next retry datetime using an exponential backoff formula with random jitter
 *              to avoid thundering-herd problems when many failed logs become eligible simultaneously.
 */
public with sharing class RetryCalculator {

    /**
     * @description Calculates the next attempt time as: now + (baseSeconds * 2^attempts) + random jitter.
     *              Jitter is a random value in [0, baseSeconds) drawn from a cryptographically random integer.
     * @param attempts    Number of attempts already performed (0-based). Treated as 0 when null.
     * @param baseSeconds Base delay in seconds; also used as the jitter ceiling.
     * @return            Datetime at which the next attempt should be made.
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
