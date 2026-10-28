#import "AQTiming.h"
#import <mach/mach_time.h>
#import <sys/sysctl.h>
#import <time.h>
#import <string.h>

static id TimingFailure(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"ArgusStaging" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"TIMING_UNVERIFIED"}];
    return nil;
}

static BOOL Integer(id value) {
    if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    const char *type = [value objCType];
    if (!type || !strchr("cCsSiIlLqQ", type[0])) return NO;
    return [value compare:@0] != NSOrderedAscending && [value compare:@(INT64_MAX)] != NSOrderedDescending;
}

static BOOL Keys(NSDictionary *value, NSArray *keys) {
    return [value isKindOfClass:[NSDictionary class]] &&
        [[NSSet setWithArray:value.allKeys] isEqualToSet:[NSSet setWithArray:keys]];
}

static BOOL ValidSample(NSDictionary *sample) {
    if (!Keys(sample, @[@"clock_kind", @"boot_id", @"ticks", @"numer", @"denom", @"utc_ns"])) return NO;
    for (NSString *key in @[@"ticks", @"numer", @"denom", @"utc_ns"]) if (!Integer(sample[key])) return NO;
    if (![sample[@"clock_kind"] isEqual:@"mach-continuous-ticks"] ||
        ![sample[@"boot_id"] isKindOfClass:[NSString class]]) return NO;
    NSString *bootID = (NSString *)sample[@"boot_id"];
    NSUUID *boot = [[NSUUID alloc] initWithUUIDString:bootID];
    return boot && [boot.UUIDString.lowercaseString isEqual:bootID] &&
        [sample[@"numer"] unsignedLongLongValue] > 0 && [sample[@"numer"] unsignedLongLongValue] <= UINT32_MAX &&
        [sample[@"denom"] unsignedLongLongValue] > 0 && [sample[@"denom"] unsignedLongLongValue] <= UINT32_MAX;
}

BOOL AQServiceMonotonicNanosecondsForAbsoluteTicks(uint64_t ticks, uint32_t numer,
                                                  uint32_t denom, uint64_t *nanoseconds) {
    if (nanoseconds == NULL || numer == 0 || denom == 0) return NO;
    __uint128_t converted = (__uint128_t)ticks * numer / denom;
    if (converted > UINT64_MAX) return NO;
    *nanoseconds = (uint64_t)converted;
    return YES;
}

BOOL AQServiceMonotonicNanosecondsNow(uint64_t *nanoseconds) {
    if (nanoseconds == NULL) return NO;
    mach_timebase_info_data_t base = {0, 0};
    if (mach_timebase_info(&base) != KERN_SUCCESS) return NO;
    return AQServiceMonotonicNanosecondsForAbsoluteTicks(mach_absolute_time(), base.numer,
                                                         base.denom, nanoseconds);
}

BOOL AQStoreDeadlineTicksForMonotonicDeadline(uint64_t deadlineNanoseconds,
                                              uint64_t serviceNowNanoseconds,
                                              uint64_t storeNowContinuousTicks,
                                              uint32_t numer, uint32_t denom,
                                              uint64_t *storeDeadlineTicks) {
    if (storeDeadlineTicks == NULL || numer == 0 || denom == 0 ||
        deadlineNanoseconds <= serviceNowNanoseconds ||
        storeNowContinuousTicks > INT64_MAX) return NO;
    uint64_t remainingNanoseconds = deadlineNanoseconds - serviceNowNanoseconds;
    __uint128_t remainingTicks = (__uint128_t)remainingNanoseconds * denom / numer;
    if (remainingTicks == 0 || remainingTicks + storeNowContinuousTicks > INT64_MAX) return NO;
    *storeDeadlineTicks = storeNowContinuousTicks + (uint64_t)remainingTicks;
    return YES;
}

NSDictionary *AQClockNow(NSError **error) {
    mach_timebase_info_data_t base;
    char boot[128] = {0};
    size_t length = sizeof boot;
    struct timespec utc;
    uint64_t before = mach_continuous_time();
    if (mach_timebase_info(&base) != KERN_SUCCESS || !base.numer || !base.denom ||
        clock_gettime(CLOCK_REALTIME, &utc) != 0 || utc.tv_sec < 0 ||
        sysctlbyname("kern.bootsessionuuid", boot, &length, NULL, 0) != 0 ||
        !length || length > sizeof boot || boot[length - 1] != '\0' ||
        mach_continuous_time() < before) return TimingFailure(error);
    __int128 wall = (__int128)utc.tv_sec * 1000000000 + utc.tv_nsec;
    if (wall > INT64_MAX || before > INT64_MAX || utc.tv_nsec < 0 || utc.tv_nsec >= 1000000000) return TimingFailure(error);
    NSString *identity = [[NSString alloc] initWithBytes:boot length:length - 1 encoding:NSUTF8StringEncoding];
    if (!identity) return TimingFailure(error);
    NSDictionary *sample = @{@"clock_kind": @"mach-continuous-ticks", @"boot_id": identity.lowercaseString,
        @"ticks": @(before), @"numer": @(base.numer), @"denom": @(base.denom), @"utc_ns": @((int64_t)wall)};
    return ValidSample(sample) ? sample : TimingFailure(error);
}

static BOOL Deadline(uint64_t start, uint64_t duration, uint64_t numer, uint64_t denom, uint64_t *result) {
    __uint128_t converted = (__uint128_t)duration * denom / numer;
    if (converted + start > INT64_MAX) return NO;
    *result = start + (uint64_t)converted;
    return YES;
}

NSDictionary *AQCreateTiming(NSDictionary *sample, uint64_t timeoutNS, int64_t stagingExpiryUTCNS,
                            int64_t cleanupExpiryUTCNS, uint64_t reserveNS, NSError **error) {
    if (!ValidSample(sample) || timeoutNS == 0 || timeoutNS > INT64_MAX || reserveNS > INT64_MAX) return TimingFailure(error);
    int64_t wall = [sample[@"utc_ns"] longLongValue];
    if (stagingExpiryUTCNS <= wall || cleanupExpiryUTCNS <= wall || cleanupExpiryUTCNS < stagingExpiryUTCNS) return TimingFailure(error);
    uint64_t start = [sample[@"ticks"] unsignedLongLongValue], numer = [sample[@"numer"] unsignedLongLongValue], denom = [sample[@"denom"] unsignedLongLongValue];
    uint64_t operation, staging, cleanup, reserve;
    if (!Deadline(start, timeoutNS, numer, denom, &operation) ||
        !Deadline(start, MIN(timeoutNS, (uint64_t)(stagingExpiryUTCNS - wall)), numer, denom, &staging) ||
        !Deadline(start, MIN(timeoutNS, (uint64_t)(cleanupExpiryUTCNS - wall)), numer, denom, &cleanup) ||
        !Deadline(start, reserveNS >= timeoutNS ? 0 : timeoutNS - reserveNS, numer, denom, &reserve) ||
        operation <= start || staging <= start || cleanup <= start) return TimingFailure(error);
    return @{@"schema_version": @2, @"clock_kind": (id)sample[@"clock_kind"],
        @"boot_id": (id)sample[@"boot_id"], @"numer": (id)sample[@"numer"],
        @"denom": (id)sample[@"denom"], @"start_ticks": @(start), @"wall_start_ns": @(wall),
        @"operation_timeout_ns": @(timeoutNS), @"staging_expiry_utc_ns": @(stagingExpiryUTCNS),
        @"cleanup_expiry_utc_ns": @(cleanupExpiryUTCNS), @"cleanup_reserve_ns": @(reserveNS),
        @"operation_deadline_ticks": @(operation), @"staging_deadline_ticks": @(staging),
        @"cleanup_deadline_ticks": @(cleanup), @"cleanup_reserve_start_ticks": @(reserve)};
}

BOOL AQTimingAllows(NSDictionary *timing, NSDictionary *sample, BOOL cleanup, NSError **error) {
    NSArray *numbers = @[@"schema_version", @"numer", @"denom", @"start_ticks", @"wall_start_ns", @"operation_timeout_ns",
        @"staging_expiry_utc_ns", @"cleanup_expiry_utc_ns", @"cleanup_reserve_ns", @"operation_deadline_ticks",
        @"staging_deadline_ticks", @"cleanup_deadline_ticks", @"cleanup_reserve_start_ticks"];
    NSArray *keys = [numbers arrayByAddingObjectsFromArray:@[@"clock_kind", @"boot_id"]];
    if (!Keys(timing, keys) || !ValidSample(sample)) { TimingFailure(error); return NO; }
    for (NSString *key in numbers) if (!Integer(timing[key])) { TimingFailure(error); return NO; }
    if (![timing[@"schema_version"] isEqual:@2] || ![timing[@"boot_id"] isEqual:sample[@"boot_id"]] ||
        ![timing[@"clock_kind"] isEqual:sample[@"clock_kind"]] || ![timing[@"numer"] isEqual:sample[@"numer"]] ||
        ![timing[@"denom"] isEqual:sample[@"denom"]]) { TimingFailure(error); return NO; }
    NSDictionary *start = @{@"clock_kind": (id)timing[@"clock_kind"],
        @"boot_id": (id)timing[@"boot_id"], @"ticks": (id)timing[@"start_ticks"],
        @"numer": (id)timing[@"numer"], @"denom": (id)timing[@"denom"],
        @"utc_ns": (id)timing[@"wall_start_ns"]};
    NSDictionary *expected = AQCreateTiming(start, [timing[@"operation_timeout_ns"] unsignedLongLongValue],
        [timing[@"staging_expiry_utc_ns"] longLongValue], [timing[@"cleanup_expiry_utc_ns"] longLongValue],
        [timing[@"cleanup_reserve_ns"] unsignedLongLongValue], NULL);
    uint64_t now = [sample[@"ticks"] unsignedLongLongValue];
    int64_t wall = [sample[@"utc_ns"] longLongValue];
    NSString *deadline = cleanup ? @"cleanup_deadline_ticks" : @"staging_deadline_ticks";
    NSString *expiry = cleanup ? @"cleanup_expiry_utc_ns" : @"staging_expiry_utc_ns";
    if (![expected isEqual:timing] || now < [timing[@"start_ticks"] unsignedLongLongValue] ||
        wall < [timing[@"wall_start_ns"] longLongValue] || wall >= [timing[expiry] longLongValue] ||
        now >= [timing[deadline] unsignedLongLongValue] || now >= [timing[@"operation_deadline_ticks"] unsignedLongLongValue]) {
        TimingFailure(error); return NO;
    }
    return YES;
}

uint64_t AQClockCurrentTicks(void) {
    NSDictionary *sample = AQClockNow(NULL);
    return sample ? [sample[@"ticks"] unsignedLongLongValue] : UINT64_MAX;
}
