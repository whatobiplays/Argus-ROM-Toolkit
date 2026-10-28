#import "AQServiceReceiptJournal.h"

#import "AQJSON.h"
#import "AQServiceProtocol.h"

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const AQReceiptErrorDomain = @"AQServiceReceiptJournal";
static const NSUInteger AQReceiptMaximumBytes = 256 * 1024;
static const uint64_t AQReceiptAggregateMaximumBytes = 64ULL * 1024 * 1024;
static const uint64_t AQReceiptReservationBytes = 512ULL * 1024;
static const NSUInteger AQReceiptAggregateMaximumEntries = 256;
static const NSUInteger AQReceiptRecoveryMaximumEntries = 1024;
static NSArray<NSString *> *AQReceiptBindingKeys(void) {
    return @[@"request_id", @"session_id", @"service_boot_id", @"sequence",
             @"deadline_ns", @"manifest_sha256", @"generation", @"members"];
}

static NSError *AQReceiptError(void) {
    return [NSError errorWithDomain:AQReceiptErrorDomain code:1 userInfo:nil];
}

static BOOL AQReceiptEqualBinding(NSDictionary *left, NSDictionary *right) {
    for (NSString *key in AQReceiptBindingKeys()) {
        if (left[key] == nil || ![left[key] isEqual:right[key]]) return NO;
    }
    return YES;
}

static BOOL AQReceiptWriteAll(int descriptor, NSData *data) {
    const uint8_t *cursor = data.bytes;
    size_t remaining = data.length;
    while (remaining != 0) {
        ssize_t count = write(descriptor, cursor, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        cursor += count;
        remaining -= (size_t)count;
    }
    return YES;
}

@interface AQServiceReceiptJournal ()
@property(nonatomic) int directoryFD;
@end

static BOOL AQReceiptIsLowercaseSHA256(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 64) return NO;
    NSString *digest = value;
    for (NSUInteger index = 0; index < digest.length; ++index) {
        unichar character = [digest characterAtIndex:index];
        if (!((character >= '0' && character <= '9') ||
              (character >= 'a' && character <= 'f'))) return NO;
    }
    return YES;
}

static BOOL AQReceiptIsIntegerNumber(id value) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    CFTypeRef bridged = (__bridge CFTypeRef)value;
    return CFGetTypeID(bridged) == CFNumberGetTypeID() &&
        !CFNumberIsFloatType((__bridge CFNumberRef)value);
}

static NSSet<NSString *> *AQReceiptCompletionKeys(void) {
    return [NSSet setWithArray:@[
        @"schema_version", @"status", @"code", @"request_id", @"session_id",
        @"service_boot_id", @"sequence", @"deadline_ns", @"manifest_sha256",
        @"authorization_sha256", @"generation", @"members", @"members_sha256",
        @"member_count", @"frame_sha256", @"receipt_sha256", @"receipt_path",
        @"durable",
    ]];
}

/** Validate the exact broker DTO and its canonical digests before consuming a reservation. */
static BOOL AQReceiptCompletionMatchesBinding(NSDictionary *completion,
                                              NSDictionary *binding,
                                              NSError **error) {
    if (![completion isKindOfClass:NSDictionary.class] ||
        ![binding isKindOfClass:NSDictionary.class] ||
        ![[NSSet setWithArray:completion.allKeys] isEqualToSet:AQReceiptCompletionKeys()] ||
        !AQReceiptEqualBinding(completion, binding)) return NO;

    for (NSString *key in @[@"schema_version", @"sequence", @"deadline_ns",
                             @"generation", @"member_count"]) {
        if (!AQReceiptIsIntegerNumber(completion[key])) return NO;
    }
    id durable = completion[@"durable"];
    if (![completion[@"schema_version"] isEqual:@1] ||
        ![completion[@"status"] isEqual:@"VERIFIED_RECEIVER_COMPLETION"] ||
        ![completion[@"code"] isEqual:@"BROKER_RECEIVER_RECEIPT_DURABLE"] ||
        ![durable isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)durable) != CFBooleanGetTypeID() ||
        ![durable boolValue]) return NO;

    for (NSString *key in @[@"request_id", @"session_id", @"service_boot_id"]) {
        if (![completion[key] isKindOfClass:NSString.class] ||
            [completion[key] length] == 0) return NO;
    }
    for (NSString *key in @[@"manifest_sha256", @"authorization_sha256",
                             @"frame_sha256", @"receipt_sha256"]) {
        if (!AQReceiptIsLowercaseSHA256(completion[key])) return NO;
    }
    NSArray *members = completion[@"members"];
    NSNumber *memberCount = completion[@"member_count"] ?: @0;
    if (![members isKindOfClass:NSArray.class] || members.count == 0 ||
        memberCount.unsignedIntegerValue != members.count ||
        !AQReceiptIsLowercaseSHA256(completion[@"members_sha256"])) return NO;
    NSString *membersDigest = AQDigest(@"", members, error);
    if (membersDigest == nil ||
        ![completion[@"members_sha256"] isEqual:membersDigest]) return NO;

    NSString *receiptPath = completion[@"receipt_path"];
    if (![receiptPath isKindOfClass:NSString.class] || !receiptPath.isAbsolutePath ||
        [receiptPath rangeOfString:@"\0"].location != NSNotFound) return NO;

    NSMutableDictionary *digestPayload = [completion mutableCopy];
    [digestPayload removeObjectForKey:@"service_boot_id"];
    [digestPayload removeObjectForKey:@"sequence"];
    [digestPayload removeObjectForKey:@"receipt_sha256"];
    [digestPayload removeObjectForKey:@"receipt_path"];
    NSString *receiptDigest = AQDigest(@"", digestPayload, error);
    return receiptDigest != nil && [completion[@"receipt_sha256"] isEqual:receiptDigest];
}

static BOOL AQReceiptValidSessionID(NSString *sessionID) {
    if (![sessionID isKindOfClass:NSString.class] ||
        sessionID.length == 0 || sessionID.length > 128) return NO;
    for (NSUInteger index = 0; index < sessionID.length; ++index) {
        unichar character = [sessionID characterAtIndex:index];
        BOOL valid = (character >= 'a' && character <= 'z') ||
            (character >= 'A' && character <= 'Z') ||
            (character >= '0' && character <= '9') || character == '-' || character == '_';
        if (!valid) return NO;
    }
    return YES;
}

static BOOL AQReceiptHasDigestName(NSString *name, NSString *prefix, NSString *suffix) {
    if (![name hasPrefix:prefix] || ![name hasSuffix:suffix] ||
        name.length != prefix.length + 64 + suffix.length) return NO;
    return AQReceiptIsLowercaseSHA256(
        [name substringWithRange:NSMakeRange(prefix.length, 64)]);
}

static BOOL AQReceiptIsTemporaryName(NSString *name) {
    NSString *prefix = @".receipt-";
    if (name.length != prefix.length + 64 + 6 + 36 + 4 ||
        ![name hasPrefix:prefix] || ![name hasSuffix:@".tmp"] ||
        !AQReceiptIsLowercaseSHA256(
            [name substringWithRange:NSMakeRange(prefix.length, 64)]) ||
        ![[name substringWithRange:NSMakeRange(prefix.length + 64, 6)] isEqual:@".json-"]) {
        return NO;
    }
    NSString *uuid = [name substringWithRange:
        NSMakeRange(prefix.length + 64 + 6, 36)];
    for (NSUInteger index = 0; index < uuid.length; ++index) {
        unichar character = [uuid characterAtIndex:index];
        if (index == 8 || index == 13 || index == 18 || index == 23) {
            if (character != '-') return NO;
        } else if (!((character >= '0' && character <= '9') ||
                     (character >= 'a' && character <= 'f') ||
                     (character >= 'A' && character <= 'F'))) {
            return NO;
        }
    }
    return YES;
}

static int AQReceiptLockDirectory(int directoryFD) {
    int descriptor = openat(directoryFD, ".capacity.lock",
        O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    struct stat metadata = {0};
    if (descriptor < 0 || fstat(descriptor, &metadata) != 0 ||
        !S_ISREG(metadata.st_mode) || metadata.st_uid != geteuid() ||
        metadata.st_nlink != 1 || (metadata.st_mode & 0777) != 0600 ||
        flock(descriptor, LOCK_EX) != 0) {
        if (descriptor >= 0) close(descriptor);
        return -1;
    }
    return descriptor;
}

static BOOL AQReceiptUnlockDirectory(int descriptor) {
    BOOL success = flock(descriptor, LOCK_UN) == 0;
    if (close(descriptor) != 0) success = NO;
    return success;
}

static BOOL AQReceiptRecoverTemporaryFiles(int directoryFD) {
    int lockFD = AQReceiptLockDirectory(directoryFD);
    if (lockFD < 0) return NO;
    int duplicate = openat(directoryFD, ".",
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    DIR *directory = duplicate < 0 ? NULL : fdopendir(duplicate);
    BOOL success = directory != NULL;
    BOOL removedAny = NO;
    NSUInteger entryCount = 0;
    struct dirent *entry = NULL;
    while (success && (entry = readdir(directory)) != NULL) {
        NSString *name = [NSString stringWithUTF8String:entry->d_name];
        if (name == nil) {
            success = NO;
            break;
        }
        if ([name isEqual:@"."] || [name isEqual:@".."] ||
            [name isEqual:@".capacity.lock"]) continue;
        if (++entryCount > AQReceiptRecoveryMaximumEntries) {
            success = NO;
            break;
        }
        if (![name hasPrefix:@".receipt-"]) continue;
        if (!AQReceiptIsTemporaryName(name)) {
            success = NO;
            break;
        }

        struct stat namedInfo = {0};
        if (fstatat(directoryFD, name.fileSystemRepresentation, &namedInfo,
                    AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(namedInfo.st_mode) ||
            namedInfo.st_uid != geteuid() || namedInfo.st_nlink != 1 ||
            (namedInfo.st_mode & 0777) != 0600 || namedInfo.st_size < 0 ||
            (uint64_t)namedInfo.st_size > AQReceiptMaximumBytes) {
            success = NO;
            break;
        }
        int temporaryFD = openat(directoryFD, name.fileSystemRepresentation,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        struct stat openedInfo = {0};
        struct stat currentInfo = {0};
        BOOL sameFile = temporaryFD >= 0 && fstat(temporaryFD, &openedInfo) == 0 &&
            S_ISREG(openedInfo.st_mode) && openedInfo.st_uid == geteuid() &&
            openedInfo.st_nlink == 1 && (openedInfo.st_mode & 0777) == 0600 &&
            openedInfo.st_size >= 0 &&
            (uint64_t)openedInfo.st_size <= AQReceiptMaximumBytes &&
            openedInfo.st_dev == namedInfo.st_dev && openedInfo.st_ino == namedInfo.st_ino &&
            openedInfo.st_size == namedInfo.st_size &&
            fstatat(directoryFD, name.fileSystemRepresentation, &currentInfo,
                    AT_SYMLINK_NOFOLLOW) == 0 && S_ISREG(currentInfo.st_mode) &&
            currentInfo.st_uid == geteuid() && currentInfo.st_nlink == 1 &&
            (currentInfo.st_mode & 0777) == 0600 &&
            currentInfo.st_dev == openedInfo.st_dev && currentInfo.st_ino == openedInfo.st_ino &&
            currentInfo.st_size == openedInfo.st_size;
        if (temporaryFD >= 0 && close(temporaryFD) != 0) sameFile = NO;
        if (!sameFile || unlinkat(directoryFD, name.fileSystemRepresentation, 0) != 0) {
            success = NO;
            break;
        }
        removedAny = YES;
    }
    if (directory != NULL) closedir(directory);
    else if (duplicate >= 0) close(duplicate);
    if (success && removedAny) success = fsync(directoryFD) == 0;
    BOOL unlocked = AQReceiptUnlockDirectory(lockFD);
    return success && unlocked;
}

static BOOL AQReceiptMeasureCapacity(int directoryFD, uint64_t *usedBytes,
                                     NSUInteger *usedEntries) {
    int duplicate = openat(directoryFD, ".",
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (duplicate < 0) return NO;
    DIR *directory = fdopendir(duplicate);
    if (directory == NULL) {
        close(duplicate);
        return NO;
    }
    uint64_t bytes = 0;
    NSUInteger entries = 0;
    BOOL valid = YES;
    struct dirent *entry = NULL;
    while (valid && (entry = readdir(directory)) != NULL) {
        NSString *name = [NSString stringWithUTF8String:entry->d_name];
        if (name == nil || [name isEqual:@"."] || [name isEqual:@".."] ||
            [name isEqual:@".capacity.lock"]) continue;
        struct stat metadata = {0};
        if (fstatat(directoryFD, name.fileSystemRepresentation, &metadata,
                    AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(metadata.st_mode) ||
            metadata.st_uid != geteuid() || metadata.st_nlink != 1 ||
            (metadata.st_mode & 0777) != 0600 || metadata.st_size < 0) {
            valid = NO;
            break;
        }

        uint64_t charge = (uint64_t)metadata.st_size;
        if (AQReceiptHasDigestName(name, @"receipt-", @".json")) {
            if (charge == 0 || charge > AQReceiptMaximumBytes) valid = NO;
        } else if (AQReceiptHasDigestName(name, @"reserve-", @".json")) {
            if (charge != 0) valid = NO;
            charge = AQReceiptReservationBytes;
        } else if (AQReceiptIsTemporaryName(name)) {
            if (charge > AQReceiptMaximumBytes) valid = NO;
        } else {
            valid = NO;
        }
        if (!valid || bytes > UINT64_MAX - charge || entries == NSUIntegerMax) {
            valid = NO;
            break;
        }
        bytes += charge;
        entries++;
    }
    closedir(directory);
    if (!valid) return NO;
    *usedBytes = bytes;
    *usedEntries = entries;
    return YES;
}

static NSString *AQReceiptReservationName(NSString *sessionID, NSError **error) {
    if (!AQReceiptValidSessionID(sessionID)) {
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    NSString *digest = AQDigest(
        @"argus.fixture-staging.service-receipt-reservation.v1", sessionID, error);
    return digest == nil ? nil : [NSString stringWithFormat:@"reserve-%@.json", digest];
}

@implementation AQServiceReceiptJournal
- (nullable instancetype)initWithProtectedRootFD:(int)rootFD error:(NSError **)error {
    struct stat rootInfo = {0};
    if (rootFD < 0 || fstat(rootFD, &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode) ||
        rootInfo.st_uid != geteuid() || (rootInfo.st_mode & 0777) != 0700) {
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    if (mkdirat(rootFD, "receipts", 0700) != 0 && errno != EEXIST) {
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    int descriptor = openat(rootFD, "receipts",
                             O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat metadata = {0};
    if (descriptor < 0 || fstat(descriptor, &metadata) != 0 ||
        !S_ISDIR(metadata.st_mode) || metadata.st_uid != geteuid() ||
        (metadata.st_mode & 0777) != 0700) {
        if (descriptor >= 0) close(descriptor);
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    if (!AQReceiptRecoverTemporaryFiles(descriptor)) {
        close(descriptor);
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    self = [super init];
    if (self != nil) self.directoryFD = descriptor;
    else close(descriptor);
    return self;
}

- (nullable instancetype)initWithDirectory:(NSString *)directory error:(NSError **)error {
    if (directory.length == 0 || ![directory hasPrefix:@"/"]) {
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    int descriptor = open(directory.fileSystemRepresentation,
                          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat metadata = {0};
    if (descriptor < 0 || fstat(descriptor, &metadata) != 0 ||
        !S_ISDIR(metadata.st_mode) || metadata.st_uid != geteuid() ||
        (metadata.st_mode & 0777) != 0700) {
        if (descriptor >= 0) close(descriptor);
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    if (!AQReceiptRecoverTemporaryFiles(descriptor)) {
        close(descriptor);
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    self = [super init];
    if (self != nil) self.directoryFD = descriptor;
    else close(descriptor);
    return self;
}

- (void)dealloc {
    if (self.directoryFD >= 0) close(self.directoryFD);
}

- (nullable NSString *)nameForBinding:(NSDictionary *)binding error:(NSError **)error {
    for (NSString *key in AQReceiptBindingKeys()) {
        if (binding[key] == nil) {
            if (error != NULL) *error = AQReceiptError();
            return nil;
        }
    }
    NSString *digest = AQDigest(@"argus.fixture-staging.service-receipt.v1", binding, error);
    return digest == nil ? nil : [NSString stringWithFormat:@"receipt-%@.json", digest];
}

- (BOOL)reserveCapacityForSessionID:(NSString *)sessionID error:(NSError **)error {
    BOOL created = NO;
    return [self reserveCapacityForSessionID:sessionID created:&created error:error];
}

- (BOOL)reserveCapacityForSessionID:(NSString *)sessionID
                            created:(BOOL *)created
                              error:(NSError **)error {
    if (created != NULL) *created = NO;
    NSString *name = AQReceiptReservationName(sessionID, error);
    if (name == nil) return NO;
    int lockFD = AQReceiptLockDirectory(self.directoryFD);
    if (lockFD < 0) {
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }

    struct stat existing = {0};
    if (fstatat(self.directoryFD, name.fileSystemRepresentation, &existing,
                AT_SYMLINK_NOFOLLOW) == 0) {
        BOOL valid = S_ISREG(existing.st_mode) && existing.st_uid == geteuid() &&
            existing.st_nlink == 1 && (existing.st_mode & 0777) == 0600 &&
            existing.st_size == 0;
        BOOL unlocked = AQReceiptUnlockDirectory(lockFD);
        if (!valid || !unlocked) {
            if (error != NULL) *error = AQReceiptError();
            return NO;
        }
        return YES;
    }
    if (errno != ENOENT) {
        (void)AQReceiptUnlockDirectory(lockFD);
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }

    uint64_t usedBytes = 0;
    NSUInteger usedEntries = 0;
    BOOL withinCapacity = AQReceiptMeasureCapacity(
        self.directoryFD, &usedBytes, &usedEntries) &&
        usedEntries < AQReceiptAggregateMaximumEntries &&
        usedBytes <= AQReceiptAggregateMaximumBytes - AQReceiptReservationBytes;
    if (!withinCapacity) {
        (void)AQReceiptUnlockDirectory(lockFD);
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }

    int reservationFD = openat(self.directoryFD, name.fileSystemRepresentation,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    struct stat metadata = {0};
    BOOL success = reservationFD >= 0 && fstat(reservationFD, &metadata) == 0 &&
        S_ISREG(metadata.st_mode) && metadata.st_uid == geteuid() &&
        metadata.st_nlink == 1 && (metadata.st_mode & 0777) == 0600 &&
        metadata.st_size == 0 && fsync(reservationFD) == 0;
    if (reservationFD >= 0 && close(reservationFD) != 0) success = NO;
    if (success) success = fsync(self.directoryFD) == 0;
    if (!success) (void)unlinkat(self.directoryFD, name.fileSystemRepresentation, 0);
    BOOL unlocked = AQReceiptUnlockDirectory(lockFD);
    if (!success || !unlocked) {
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }
    if (created != NULL) *created = YES;
    return YES;
}

/** Isolates the reservation-release directory sync so tests can inject a
 * failure without adding test controls to the production journal API. */
- (BOOL)syncDirectoryForReservationRelease {
    return fsync(self.directoryFD) == 0;
}

- (BOOL)releaseCapacityForSessionID:(NSString *)sessionID error:(NSError **)error {
    if (error != NULL) *error = nil;
    NSString *name = AQReceiptReservationName(sessionID, error);
    if (name == nil) return NO;
    int lockFD = AQReceiptLockDirectory(self.directoryFD);
    if (lockFD < 0) {
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }
    struct stat metadata = {0};
    if (fstatat(self.directoryFD, name.fileSystemRepresentation, &metadata,
                AT_SYMLINK_NOFOLLOW) != 0) {
        int failure = errno;
        BOOL unlocked = AQReceiptUnlockDirectory(lockFD);
        if (failure == ENOENT && unlocked) return YES;
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }
    BOOL valid = S_ISREG(metadata.st_mode) && metadata.st_uid == geteuid() &&
        metadata.st_nlink == 1 && (metadata.st_mode & 0777) == 0600 && metadata.st_size == 0;
    BOOL removed = valid && unlinkat(self.directoryFD, name.fileSystemRepresentation, 0) == 0;
    BOOL removalDurable = NO;
    if (removed) {
        removalDurable = [self syncDirectoryForReservationRelease];
        if (!removalDurable) {
            // An unsuccessful directory sync leaves unlink durability uncertain.
            // Re-establish the empty reservation durably before failing closed.
            int reservationFD = openat(self.directoryFD, name.fileSystemRepresentation,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
            if (reservationFD >= 0) {
                BOOL fileDurable = fsync(reservationFD) == 0;
                BOOL fileClosed = close(reservationFD) == 0;
                if (fileDurable && fileClosed) (void)fsync(self.directoryFD);
            }
        }
    }
    BOOL unlocked = AQReceiptUnlockDirectory(lockFD);
    if (!valid || !removed || !removalDurable || !unlocked) {
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }
    return YES;
}

- (nullable NSDictionary *)receiptForBinding:(NSDictionary *)binding error:(NSError **)error {
    NSString *name = [self nameForBinding:binding error:error];
    if (name == nil) return nil;
    int descriptor = openat(self.directoryFD, name.fileSystemRepresentation,
        O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) {
        if (errno != ENOENT && error != NULL) *error = AQReceiptError();
        return nil;
    }
    struct stat metadata = {0};
    BOOL valid = fstat(descriptor, &metadata) == 0 && S_ISREG(metadata.st_mode) &&
        metadata.st_uid == geteuid() && metadata.st_nlink == 1 &&
        (metadata.st_mode & 0777) == 0600 && metadata.st_size > 0 &&
        (NSUInteger)metadata.st_size <= AQReceiptMaximumBytes;
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[2048];
    while (valid) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { valid = NO; break; }
        if (count == 0) break;
        [data appendBytes:buffer length:(NSUInteger)count];
        if (data.length > AQReceiptMaximumBytes) valid = NO;
    }
    close(descriptor);
    NSDictionary *record = valid ?
        AQParseJSONWithMaximumBytes(data, AQReceiptMaximumBytes, error) : nil;
    if (![record isKindOfClass:NSDictionary.class] ||
        ![record[@"binding"] isKindOfClass:NSDictionary.class] ||
        !AQReceiptEqualBinding(record[@"binding"], binding) ||
        ![record[@"completion"] isKindOfClass:NSDictionary.class]) {
        if (error != NULL) *error = AQReceiptError();
        return nil;
    }
    return record[@"completion"];
}

- (BOOL)recordBrokerCompletion:(NSDictionary *)completion
                       binding:(NSDictionary *)binding
                         error:(NSError **)error {
    if (!AQReceiptCompletionMatchesBinding(completion, binding, error)) {
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }
    NSString *name = [self nameForBinding:binding error:error];
    NSData *encoded = AQCanonicalJSONWithMaximumBytes(
        @{@"binding": binding, @"completion": completion}, AQReceiptMaximumBytes, error);
    if (name == nil || encoded == nil || encoded.length > AQReceiptMaximumBytes) return NO;

    NSString *reservation = AQReceiptReservationName(completion[@"session_id"], error);
    if (reservation == nil) return NO;
    int lockFD = AQReceiptLockDirectory(self.directoryFD);
    if (lockFD < 0) {
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }

    NSDictionary *existingReceipt = [self receiptForBinding:binding error:NULL];
    if (existingReceipt != nil) {
        BOOL same = [existingReceipt isEqual:completion];
        /* A reservation may belong to a later export in the same session.
         * Do not consume it while acknowledging an older idempotent receipt. */
        BOOL unlocked = AQReceiptUnlockDirectory(lockFD);
        if (!same || !unlocked) {
            if (error != NULL) *error = AQReceiptError();
            return NO;
        }
        return YES;
    }

    struct stat reservationInfo = {0};
    BOOL reserved = fstatat(self.directoryFD, reservation.fileSystemRepresentation,
        &reservationInfo, AT_SYMLINK_NOFOLLOW) == 0 &&
        S_ISREG(reservationInfo.st_mode) && reservationInfo.st_uid == geteuid() &&
        reservationInfo.st_nlink == 1 && (reservationInfo.st_mode & 0777) == 0600 &&
        reservationInfo.st_size == 0;
    uint64_t usedBytes = 0;
    NSUInteger usedEntries = 0;
    BOOL capacityValid = reserved && AQReceiptMeasureCapacity(
        self.directoryFD, &usedBytes, &usedEntries) &&
        usedBytes >= AQReceiptReservationBytes && usedEntries > 0 &&
        usedBytes - AQReceiptReservationBytes <=
            AQReceiptAggregateMaximumBytes - encoded.length;
    if (!capacityValid) {
        (void)AQReceiptUnlockDirectory(lockFD);
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }

    NSString *temporary = [NSString stringWithFormat:@".receipt-%@-%@.tmp",
        [name substringFromIndex:8], NSUUID.UUID.UUIDString];
    int descriptor = openat(self.directoryFD, temporary.fileSystemRepresentation,
                            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (descriptor < 0) {
        (void)AQReceiptUnlockDirectory(lockFD);
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }
    BOOL success = AQReceiptWriteAll(descriptor, encoded) && fsync(descriptor) == 0;
    struct stat metadata = {0};
    if (success) success = fstat(descriptor, &metadata) == 0 &&
        S_ISREG(metadata.st_mode) && metadata.st_uid == geteuid() &&
        metadata.st_nlink == 1 && (metadata.st_mode & 0777) == 0600 &&
        (NSUInteger)metadata.st_size == encoded.length;
    if (close(descriptor) != 0) success = NO;
    if (success) success = linkat(self.directoryFD, temporary.fileSystemRepresentation,
                                  self.directoryFD, name.fileSystemRepresentation, 0) == 0;
    if (unlinkat(self.directoryFD, temporary.fileSystemRepresentation, 0) != 0) success = NO;
    if (success) success = fsync(self.directoryFD) == 0;
    if (success) {
        if (unlinkat(self.directoryFD, reservation.fileSystemRepresentation, 0) != 0 ||
            fsync(self.directoryFD) != 0) success = NO;
    }
    BOOL unlocked = AQReceiptUnlockDirectory(lockFD);
    if (!success || !unlocked) {
        if (error != NULL) *error = AQReceiptError();
        return NO;
    }
    return YES;
}
@end
