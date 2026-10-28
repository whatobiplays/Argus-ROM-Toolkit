#import <Foundation/Foundation.h>
#import "AQTiming.h"

#include <stdint.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "timing failure line %d\n", __LINE__); failures++; } } while (0)

static NSDictionary *Sample(uint64_t ticks, int64_t utc) {
    return @{ @"clock_kind": @"mach-continuous-ticks", @"boot_id": @"00000000-0000-0000-0000-000000000001",
              @"ticks": @(ticks), @"numer": @1, @"denom": @1, @"utc_ns": @(utc) };
}

int AQRunTimingTests(void) {
    failures = 0;
    NSError *error = nil;
    NSDictionary *start = Sample(17082823080000ULL, 1000);
    NSDictionary *timing = AQCreateTiming(start, 100, 1200, 1300, 20, &error);
    CHECK(timing != nil && error == nil);
    CHECK([timing[@"operation_deadline_ticks"] unsignedLongLongValue] == 17082823080100ULL);
    CHECK(AQTimingAllows(timing, Sample(17082823080099ULL, 1099), NO, NULL));
    CHECK(!AQTimingAllows(timing, Sample(17082823080100ULL, 1100), NO, NULL));
    CHECK(!AQTimingAllows(timing, Sample(17082823080100ULL, 900), YES, NULL));
    CHECK(!AQTimingAllows(timing, Sample(17082823079999ULL, 1001), NO, NULL));
    CHECK(!AQTimingAllows(timing, Sample(17082823080001ULL, 1200), NO, NULL));
    NSMutableDictionary *changed = [Sample(17082823080001ULL, 1001) mutableCopy];
    changed[@"boot_id"] = @"00000000-0000-0000-0000-000000000002";
    CHECK(!AQTimingAllows(timing, changed, NO, NULL));
    changed = [timing mutableCopy]; changed[@"schema_version"] = @1;
    CHECK(!AQTimingAllows(changed, start, NO, NULL));
    changed = [timing mutableCopy]; changed[@"operation_deadline_ticks"] = @17082823080200ULL;
    CHECK(!AQTimingAllows(changed, start, NO, NULL));
    changed = [start mutableCopy]; changed[@"numer"] = @125; changed[@"denom"] = @3;
    NSDictionary *rounded = AQCreateTiming(changed, 100, 1200, 1300, 200, NULL);
    CHECK([rounded[@"operation_deadline_ticks"] unsignedLongLongValue] == 17082823080002ULL);
    CHECK([rounded[@"cleanup_reserve_start_ticks"] unsignedLongLongValue] == 17082823080000ULL);
    CHECK(AQCreateTiming(start, 0, 1200, 1300, 20, NULL) == nil);
    CHECK(AQCreateTiming(start, 100, 1000, 1300, 20, NULL) == nil);
    changed = [start mutableCopy]; changed[@"ticks"] = @YES;
    CHECK(AQCreateTiming(changed, 100, 1200, 1300, 20, NULL) == nil);
    changed = [start mutableCopy]; changed[@"denom"] = @0;
    CHECK(AQCreateTiming(changed, 100, 1200, 1300, 20, NULL) == nil);
    changed = [start mutableCopy]; changed[@"ticks"] = @(INT64_MAX - 1);
    CHECK(AQCreateTiming(changed, 100, 1200, 1300, 20, NULL) == nil);
    NSDictionary *live = AQClockNow(NULL);
    CHECK(live != nil);
    CHECK([live[@"ticks"] unsignedLongLongValue] > 0);

    uint64_t nanoseconds = UINT64_MAX;
    CHECK(AQServiceMonotonicNanosecondsForAbsoluteTicks(0, 1, 1, &nanoseconds));
    CHECK(nanoseconds == 0);
    CHECK(AQServiceMonotonicNanosecondsForAbsoluteTicks(3, 1, 3, &nanoseconds));
    CHECK(nanoseconds == 1);
    CHECK(AQServiceMonotonicNanosecondsForAbsoluteTicks(9, 125, 3, &nanoseconds));
    CHECK(nanoseconds == 375);
    CHECK(!AQServiceMonotonicNanosecondsForAbsoluteTicks(UINT64_MAX, 2, 1, &nanoseconds));
    CHECK(!AQServiceMonotonicNanosecondsForAbsoluteTicks(1, 0, 1, &nanoseconds));
    CHECK(!AQServiceMonotonicNanosecondsForAbsoluteTicks(1, 1, 0, &nanoseconds));
    CHECK(AQServiceMonotonicNanosecondsNow(&nanoseconds));
    CHECK(nanoseconds > 0);

    uint64_t storeDeadline = UINT64_MAX;
    CHECK(AQStoreDeadlineTicksForMonotonicDeadline(84, 0, 9, 125, 3, &storeDeadline));
    CHECK(storeDeadline == 11); // 84 ns rounds down to two 125/3 ns ticks.
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(41, 0, 9, 125, 3, &storeDeadline));
    CHECK(AQStoreDeadlineTicksForMonotonicDeadline(3600000500ULL, 500, 1000000000000ULL,
                                                    125, 3, &storeDeadline));
    CHECK(storeDeadline == 1000086400000ULL); // A simulated suspend offset stays in the store domain.
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(100, 100, 1, 1, 1, &storeDeadline));
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(100, 0, 1, 0, 1, &storeDeadline));
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(100, 0, 1, 1, 0, &storeDeadline));
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(100, 0, 1, 1, 1, NULL));
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(100, 0, (uint64_t)INT64_MAX + 1,
                                                     1, 1, &storeDeadline));
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(100, 0, INT64_MAX - 1,
                                                     125, 3, &storeDeadline));
    CHECK(!AQStoreDeadlineTicksForMonotonicDeadline(INT64_MAX, 0, 1, 1, UINT32_MAX,
                                                     &storeDeadline));
    return failures;
}

#ifdef AQ_TIMING_STANDALONE
#if defined(AQ_TIMING_STANDALONE)
int main(void) { @autoreleasepool { return AQRunTimingTests() != 0; } }
#endif
#endif
