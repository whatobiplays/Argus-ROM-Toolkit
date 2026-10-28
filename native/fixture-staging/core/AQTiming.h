#import <Foundation/Foundation.h>

/** Read the actual sleep-inclusive Darwin clock, timebase, boot identity and UTC.
 * Failure returns nil. The boot identifier stays private and is never a verdict.
 */
NSDictionary *AQClockNow(NSError **error);

/** Convert an absolute mach_absolute_time() tick value to integer nanoseconds
 * for schema-1 service consent and freshness deadlines. This clock excludes
 * suspended time. The conversion rounds down and fails for an invalid
 * timebase, an unrepresentable result, or a null output pointer.
 */
BOOL AQServiceMonotonicNanosecondsForAbsoluteTicks(uint64_t ticks, uint32_t numer,
                                                  uint32_t denom, uint64_t *nanoseconds);

/** Read sleep-exclusive mach_absolute_time() and convert it to schema-1
 * monotonic nanoseconds. Returns NO when the platform timebase is unavailable
 * or the converted value cannot be represented. */
BOOL AQServiceMonotonicNanosecondsNow(uint64_t *nanoseconds);

/** Map an immutable schema-1 absolute-time deadline onto the internal
 * mach_continuous_time() store clock. Callers sample store ticks before service
 * nanoseconds. The result rounds down, so it cannot authorize store work later
 * than the supplied service deadline; a deadline too close to represent or an
 * overflowing signed-64-bit store tick is rejected. This helper does not
 * change the persisted schema-1 deadline or the schema-2 store clock contract.
 */
BOOL AQStoreDeadlineTicksForMonotonicDeadline(uint64_t deadlineNanoseconds,
                                              uint64_t serviceNowNanoseconds,
                                              uint64_t storeNowContinuousTicks,
                                              uint32_t numer, uint32_t denom,
                                              uint64_t *storeDeadlineTicks);

/** Capture immutable timing schema 2. Durations and UTC values are integer
 * nanoseconds; authoritative persisted deadlines are continuous-clock ticks.
 * Conversion rounds deadlines earlier, never later, than the requested limit.
 */
NSDictionary *AQCreateTiming(NSDictionary *sample, uint64_t timeoutNS,
                            int64_t stagingExpiryUTCNS, int64_t cleanupExpiryUTCNS,
                            uint64_t reserveNS, NSError **error);

/** Check the original record without extending it or translating schema 1.
 * Expiry is inclusive: a clock at the deadline no longer grants dispatch.
 * An already-dispatched syscall cannot be recalled; its later completion does
 * not independently authorize another operation or confer fixture eligibility.
 */
BOOL AQTimingAllows(NSDictionary *timing, NSDictionary *sample, BOOL cleanup, NSError **error);

/** Convenience for bounded store operations. UINT64_MAX is a fail-closed sentinel. */
uint64_t AQClockCurrentTicks(void);
