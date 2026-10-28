#import "AQBrokerProtocol.h"
#import "../core/AQContract.h"
#import <CommonCrypto/CommonDigest.h>

#import "AQJSON.h"
#import "AQServiceProtocol.h"
#import "AQStore.h"
#import "AQTiming.h"

#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#if defined(AQ_BROKER_TESTING)
static BOOL AQBrokerTestWriteFailureArmed;
static NSUInteger AQBrokerTestWriteBytesBeforeFailure;
#endif

NSString *const AQBrokerErrorDomain = @"com.argusromtoolkit.fixture-staging.broker";

static NSString *const AQBrokerReceiptSchema = @"argus.fixture-staging.receiver-receipt.v1";

static NSError *AQBrokerError(AQBrokerErrorCode code) {
    NSString *description = nil;
    switch (code) {
        case AQBrokerInvalidFrame: description = @"INVALID_EXPORT_FRAME"; break;
        case AQBrokerFrameTooLarge: description = @"EXPORT_FRAME_LIMIT"; break;
        case AQBrokerFrameDigestMismatch: description = @"EXPORT_DIGEST_MISMATCH"; break;
        case AQBrokerFrameMemberMismatch: description = @"EXPORT_MEMBER_MISMATCH"; break;
        case AQBrokerBindingMismatch: description = @"EXPORT_BINDING_MISMATCH"; break;
        case AQBrokerSpoolUnavailable: description = @"EXPORT_SPOOL_UNAVAILABLE"; break;
        case AQBrokerSpoolCapacityDenied: description = @"EXPORT_SPOOL_CAPACITY_DENIED"; break;
        case AQBrokerUncertainEffect: description = @"UNCERTAIN_EFFECT_RETAINED"; break;
        case AQBrokerReconnectRequired: description = @"RECONNECT_REQUIRED"; break;
    case AQBrokerInvalidRequest: description = @"INVALID_BROKER_REQUEST"; break;
    case AQBrokerDeadlineExpired: description = @"OPERATION_DEADLINE_EXPIRED"; break;
    case AQBrokerOperationInProgress: description = @"OPERATION_IN_PROGRESS"; break;
    case AQBrokerLateReply: description = @"LATE_REPLY_REJECTED"; break;
    case AQBrokerSequenceMismatch: description = @"REQUEST_SEQUENCE_INVALID"; break;
    case AQBrokerSessionOwnershipMismatch: description = @"SESSION_OWNERSHIP_MISMATCH"; break;
    case AQBrokerFreshAuthenticationRequired:
        description = @"FRESH_AUTHENTICATION_REQUIRED";
        break;
        case AQBrokerDurableReceiptFailed:
            description = @"DURABLE_RECEIVER_RECEIPT_FAILED";
            break;
    }
    return [NSError errorWithDomain:AQBrokerErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

NSError *AQBrokerErrorForCode(AQBrokerErrorCode code) {
    return AQBrokerError(code);
}

static BOOL AQBrokerFail(NSError **error, AQBrokerErrorCode code) {
    if (error != NULL) *error = AQBrokerError(code);
    return NO;
}

static BOOL AQBrokerToken(id value);

static BOOL AQBrokerWriteFailure(NSError **error, int errorNumber) {
    int resolvedError = errorNumber != 0 ? errorNumber : EIO;
    if (error != NULL) {
        NSString *description = [NSString stringWithFormat:@"BROKER_OUTPUT_WRITE_FAILED: %s",
                                 strerror(resolvedError)];
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:resolvedError
                                userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    return NO;
}

static BOOL AQBrokerSyncFailure(NSError **error, int errorNumber) {
    int resolvedError = errorNumber != 0 ? errorNumber : EIO;
    if (error != NULL) {
        NSString *description = [NSString stringWithFormat:@"BROKER_OUTPUT_SYNC_FAILED: %s",
                                 strerror(resolvedError)];
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:resolvedError
                                userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    return NO;
}

static BOOL AQBrokerWriteAllUsing(int fd, NSData *bytes,
                                  ssize_t (^operation)(int, const void *, size_t),
                                  NSError **error) {
    if (operation == nil) return AQBrokerWriteFailure(error, EINVAL);
    if (bytes.length == 0) {
        if (error != NULL) *error = nil;
        return YES;
    }

    const uint8_t *cursor = bytes.bytes;
    NSUInteger remaining = bytes.length;
    while (remaining != 0) {
        ssize_t count;
        do {
            errno = 0;
            count = operation(fd, cursor, (size_t)remaining);
        } while (count < 0 && errno == EINTR);
        int writeError = errno;
        if (count == 0) return AQBrokerWriteFailure(error, EIO);
        if (count < 0) return AQBrokerWriteFailure(error, writeError);
        if ((NSUInteger)count > remaining) return AQBrokerWriteFailure(error, EPROTO);
        cursor += (NSUInteger)count;
        remaining -= (NSUInteger)count;
    }
    if (error != NULL) *error = nil;
    return YES;
}

BOOL AQBrokerWriteAll(int fd, NSData *bytes, NSError **error) {
    return AQBrokerWriteAllUsing(fd, bytes, ^ssize_t(int outputFD, const void *buffer,
                                                    size_t length) {
        return write(outputFD, buffer, length);
    }, error);
}

BOOL AQBrokerWriteAllUntilDeadline(int fd, NSData *bytes,
                                   uint64_t deadlineNanoseconds,
                                   AQBrokerMonotonicClock clock,
                                   NSError **error) {
    if (error != NULL) *error = nil;
    if (fd < 0 || clock == nil) return AQBrokerWriteFailure(error, EINVAL);

    const uint8_t *cursor = bytes.bytes;
    NSUInteger remainingBytes = bytes.length;
    int originalFlags = fcntl(fd, F_GETFL);
    if (originalFlags < 0) return AQBrokerWriteFailure(error, errno);
    if ((originalFlags & O_NONBLOCK) == 0 && fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) != 0) {
        return AQBrokerWriteFailure(error, errno);
    }

    BOOL success = YES;
    NSError *localError = nil;
#if defined(AQ_BROKER_TESTING)
    NSUInteger writtenBytes = 0;
#endif
    while (remainingBytes != 0) {
        uint64_t remainingNanoseconds = 0;
        if (!AQBrokerDeadlineRemaining(deadlineNanoseconds, clock(),
                                       &remainingNanoseconds, &localError)) {
            success = NO;
            break;
        }

        uint64_t timeout = remainingNanoseconds / NSEC_PER_MSEC;
        if (timeout != 0) {
            int timeoutMilliseconds = timeout > (uint64_t)INT_MAX ? INT_MAX : (int)timeout;
            struct pollfd descriptor = {.fd = fd, .events = POLLOUT};
            int ready = poll(&descriptor, 1, timeoutMilliseconds);
            if (ready < 0 && errno == EINTR) continue;
            if (ready < 0) {
                AQBrokerWriteFailure(&localError, errno);
                success = NO;
                break;
            }
            if (ready == 0) {
                AQBrokerFail(&localError, AQBrokerDeadlineExpired);
                success = NO;
                break;
            }
            if ((descriptor.revents & (POLLERR | POLLNVAL)) != 0) {
                AQBrokerWriteFailure(&localError, EIO);
                success = NO;
                break;
            }
        }

        size_t writeLength = (size_t)remainingBytes;
#if defined(AQ_BROKER_TESTING)
        if (AQBrokerTestWriteFailureArmed) {
            if (writtenBytes >= AQBrokerTestWriteBytesBeforeFailure) {
                AQBrokerTestWriteFailureArmed = NO;
                AQBrokerWriteFailure(&localError, EIO);
                success = NO;
                break;
            }
            NSUInteger untilFailure = AQBrokerTestWriteBytesBeforeFailure - writtenBytes;
            if (writeLength > untilFailure) writeLength = (size_t)untilFailure;
        }
#endif
        /* Readiness can race with expiry; never dispatch a write on a stale poll. */
        if (!AQBrokerDeadlineRemaining(deadlineNanoseconds, clock(),
                                       &remainingNanoseconds, &localError)) {
            success = NO;
            break;
        }
        ssize_t count = write(fd, cursor, writeLength);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            if (timeout == 0) {
                AQBrokerFail(&localError, AQBrokerDeadlineExpired);
                success = NO;
                break;
            }
            continue;
        }
        int writeError = errno;
        if (count == 0) {
            AQBrokerWriteFailure(&localError, EIO);
            success = NO;
            break;
        }
        if (count < 0) {
            AQBrokerWriteFailure(&localError, writeError);
            success = NO;
            break;
        }
        if ((NSUInteger)count > remainingBytes) {
            AQBrokerWriteFailure(&localError, EPROTO);
            success = NO;
            break;
        }
        cursor += (NSUInteger)count;
        remainingBytes -= (NSUInteger)count;
#if defined(AQ_BROKER_TESTING)
        writtenBytes += (NSUInteger)count;
#endif
    }

    if ((originalFlags & O_NONBLOCK) == 0) {
        /* Restore even after a failed write; keep the original error in that case. */
        int restoreResult = fcntl(fd, F_SETFL, originalFlags);
        if (restoreResult != 0 && success) {
            AQBrokerWriteFailure(&localError, errno);
            success = NO;
        }
    }
    if (error != NULL) *error = localError;
    return success;
}

#if defined(AQ_BROKER_TESTING)
BOOL AQBrokerTestWriteAll(int fd, NSData *bytes,
                          AQBrokerTestWriteOperation operation, NSError **error) {
    return AQBrokerWriteAllUsing(fd, bytes, operation, error);
}
#endif

static BOOL AQBrokerDigest(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 64) return NO;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return [value rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound;
}

static BOOL AQBrokerInteger(id value, uint64_t *result) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    long long integer = [value longLongValue];
    if (integer < 0) return NO;
    if (result != NULL) *result = (uint64_t)integer;
    return YES;
}

static BOOL AQBrokerSafePath(NSString *path) {
    if (path.length == 0 || path.length > 4096 || [path hasPrefix:@"/"] ||
        [path hasSuffix:@"/"] || [path containsString:@"//"] ||
        [path containsString:@"\\"] || [path containsString:@":"] ||
        [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqual:@"."] || [part isEqual:@".."]) return NO;
    }
    return YES;
}

typedef NS_ENUM(NSInteger, AQBrokerFrameStage) {
    AQBrokerFrameMagic = 1, AQBrokerFrameLength, AQBrokerFrameHeader,
    AQBrokerFrameMembers, AQBrokerFrameTrailer, AQBrokerFrameDigest, AQBrokerFrameComplete
};

enum { AQBrokerSpoolChunkBytes = 64 * 1024 };
static const uint64_t AQBrokerSpoolReserveBytes = 2ULL * 1024 * 1024 * 1024;

#if defined(AQ_BROKER_TESTING)
static BOOL AQBrokerTestHasAvailableBytes;
static BOOL AQBrokerTestForceSpoolUnavailable;
static uint64_t AQBrokerTestAvailableBytes;
static int AQBrokerTestLastSpoolFD = -1;
static char AQBrokerTestLastSpoolPathname[PATH_MAX];
static int AQBrokerTestNextSyncError;
static NSUInteger AQBrokerTestSyncSuccessesBeforeFailure;
#endif

/** Synchronizes an inode while preserving errno for the caller. Test builds
 * may inject exactly one failure so receipt and spool failure paths remain
 * deterministic without weakening production code. */
static BOOL AQBrokerSyncDescriptor(int fd, NSError **error) {
#if defined(AQ_BROKER_TESTING)
    if (AQBrokerTestNextSyncError != 0) {
        if (AQBrokerTestSyncSuccessesBeforeFailure != 0) {
            AQBrokerTestSyncSuccessesBeforeFailure--;
        } else {
            int injectedError = AQBrokerTestNextSyncError;
            AQBrokerTestNextSyncError = 0;
            return AQBrokerSyncFailure(error, injectedError);
        }
    }
#endif
    int result = 0;
    do {
        result = fsync(fd);
    } while (result != 0 && errno == EINTR);
    if (result != 0) return AQBrokerSyncFailure(error, errno);
    if (error != NULL) *error = nil;
    return YES;
}

static BOOL AQBrokerExistingReceiptMatches(int directoryFD, const char *name,
                                            NSData *expected, NSError **error) {
    int fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return NO;
    struct stat info = {0};
    BOOL valid = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) &&
        info.st_uid == geteuid() && info.st_nlink == 1 &&
        (info.st_mode & 0777) == (S_IRUSR | S_IWUSR) && info.st_size >= 0 &&
        (NSUInteger)info.st_size == expected.length;
    NSMutableData *actual = valid ? [NSMutableData dataWithLength:expected.length] : nil;
    NSUInteger offset = 0;
    while (valid && offset < expected.length) {
        ssize_t count = read(fd, (uint8_t *)actual.mutableBytes + offset,
                             expected.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { valid = NO; break; }
        offset += (NSUInteger)count;
    }
    if (valid) valid = [actual isEqualToData:expected];
    if (valid) valid = AQBrokerSyncDescriptor(fd, error);
    int closeResult = close(fd);
    if (valid && closeResult != 0) valid = AQBrokerWriteFailure(error, errno);
    if (!valid && error != NULL && *error == nil)
        AQBrokerWriteFailure(error, EIO);
    return valid;
}

static void AQBrokerRemoveOwnedTemporary(int directoryFD, const char *name,
                                         dev_t device, ino_t inode) {
    struct stat current = {0};
    if (fstatat(directoryFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0 &&
        current.st_dev == device && current.st_ino == inode)
        (void)unlinkat(directoryFD, name, 0);
}


static BOOL AQBrokerAddBytes(uint64_t left, uint64_t right, uint64_t *result) {
    if (result == NULL || UINT64_MAX - left < right) return NO;
    *result = left + right;
    return YES;
}

/** Closes an owned descriptor exactly once. Descriptor identity is cleared
 * before close so an interrupted close cannot be repeated against a reused
 * descriptor number. */
static void AQBrokerCloseSpoolDescriptor(int *fd) {
    if (fd == NULL || *fd < 0) return;
    int descriptor = *fd;
    *fd = -1;
    (void)close(descriptor);
}

static BOOL AQBrokerSpoolMetadataValid(int fd, struct stat *metadataOut) {
    struct stat info = {0};
    if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) ||
        info.st_nlink != 0 || info.st_uid != geteuid() ||
        (info.st_mode & 0777) != (S_IRUSR | S_IWUSR)) {
        return NO;
    }
    int descriptorFlags = fcntl(fd, F_GETFD);
    if (descriptorFlags < 0 || (descriptorFlags & FD_CLOEXEC) == 0) return NO;
    if (metadataOut != NULL) *metadataOut = info;
    return YES;
}

/** Opens the configured receipt directory for descriptor-relative receipt
 * creation. The final path component cannot be a symlink, and the open
 * directory must remain owned by the current user with mode 0700. */
static BOOL AQBrokerOpenReceiptDirectory(NSString *path, int *descriptor,
                                         NSError **error) {
    if (descriptor == NULL || path.length == 0 || path.length > PATH_MAX ||
        !path.isAbsolutePath) {
        return AQBrokerFail(error, AQBrokerDurableReceiptFailed);
    }
    const char *fileSystemPath = path.fileSystemRepresentation;
    if (fileSystemPath == NULL) return AQBrokerFail(error, AQBrokerDurableReceiptFailed);
    int fd = open(fileSystemPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return AQBrokerWriteFailure(error, errno);
    int descriptorFlags = fcntl(fd, F_GETFD);
    struct stat info = {0};
    BOOL valid = fstat(fd, &info) == 0 && S_ISDIR(info.st_mode) &&
        info.st_uid == geteuid() && (info.st_mode & 0777) == (S_IRWXU) &&
        descriptorFlags >= 0 && (descriptorFlags & FD_CLOEXEC) != 0;
    if (!valid) {
        close(fd);
        return AQBrokerFail(error, AQBrokerDurableReceiptFailed);
    }
    *descriptor = fd;
    if (error != NULL) *error = nil;
    return YES;
}

/** Creates a spool only in synthetic test builds. The production target fails
 * closed because its macOS deployment target has no supported anonymous from
 * inception spool primitive or enforced boundary for a named temporary file. */
static BOOL AQBrokerCreateSpool(int *fd, NSError **error) {
#if !defined(AQ_BROKER_TESTING)
    (void)fd;
    return AQBrokerFail(error, AQBrokerSpoolUnavailable);
#else
    char directory[PATH_MAX] = {0};
    size_t directoryLength = confstr(_CS_DARWIN_USER_TEMP_DIR, directory, sizeof(directory));
    if (directoryLength == 0 || directoryLength > sizeof(directory)) {
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    NSString *template = [[NSString stringWithUTF8String:directory]
        stringByAppendingPathComponent:@"argus-broker-export.XXXXXX"];
    char name[PATH_MAX] = {0};
    if (![template getFileSystemRepresentation:name maxLength:sizeof(name)]) {
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    AQBrokerTestLastSpoolFD = -1;
    AQBrokerTestLastSpoolPathname[0] = '\0';
    if (AQBrokerTestForceSpoolUnavailable) {
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    int spool = mkstemp(name);
    if (spool >= 0) strlcpy(AQBrokerTestLastSpoolPathname, name,
                           sizeof(AQBrokerTestLastSpoolPathname));
    if (spool < 0 || unlink(name) != 0) {
        AQBrokerCloseSpoolDescriptor(&spool);
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    BOOL valid = fchmod(spool, S_IRUSR | S_IWUSR) == 0 &&
        fcntl(spool, F_SETFD, FD_CLOEXEC) == 0 &&
        AQBrokerSpoolMetadataValid(spool, NULL);
    if (!valid) {
        AQBrokerCloseSpoolDescriptor(&spool);
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    AQBrokerTestLastSpoolFD = spool;
    *fd = spool;
    return YES;
#endif
}

static BOOL AQBrokerApprovedMembers(NSDictionary *manifest,
                                    NSArray<NSDictionary *> **membersOut,
                                    NSString **manifestDigestOut,
                                    NSError **error) {
    if (![manifest isKindOfClass:NSDictionary.class]) {
        return AQBrokerFail(error, AQBrokerBindingMismatch);
    }
    NSArray *selected = manifest[@"selected_fixture_ids"];
    NSArray *fixtures = manifest[@"fixtures"];
    if (![selected isKindOfClass:NSArray.class] || ![fixtures isKindOfClass:NSArray.class] ||
        selected.count == 0 || selected.count != fixtures.count || fixtures.count > 1024) {
        return AQBrokerFail(error, AQBrokerBindingMismatch);
    }
    NSString *manifestDigest = AQDigest(@"", manifest, NULL);
    if (!AQBrokerDigest(manifestDigest)) {
        return AQBrokerFail(error, AQBrokerBindingMismatch);
    }
    NSMutableArray<NSDictionary *> *members = [NSMutableArray array];
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    for (NSUInteger fixtureIndex = 0; fixtureIndex < fixtures.count; ++fixtureIndex) {
        NSDictionary *fixture = fixtures[fixtureIndex];
        if (![fixture isKindOfClass:NSDictionary.class]) {
            return AQBrokerFail(error, AQBrokerBindingMismatch);
        }
        NSString *fixtureID = fixture[@"fixture_id"];
        NSArray *files = fixture[@"files"];
        if (![fixtureID isKindOfClass:NSString.class] ||
            ![selected[fixtureIndex] isEqual:fixtureID] || ![files isKindOfClass:NSArray.class] ||
            files.count == 0) {
            return AQBrokerFail(error, AQBrokerBindingMismatch);
        }
        for (id entry in files) {
            if (![entry isKindOfClass:NSDictionary.class]) {
                return AQBrokerFail(error, AQBrokerBindingMismatch);
            }
            NSString *relativePath = entry[@"path"];
            if (![relativePath isKindOfClass:NSString.class]) {
                return AQBrokerFail(error, AQBrokerBindingMismatch);
            }
            NSString *path = [fixtureID stringByAppendingFormat:@"/%@", relativePath];
            uint64_t size = 0;
            if (!AQBrokerSafePath(path) || !AQBrokerInteger(entry[@"size"], &size) ||
                !AQBrokerDigest(entry[@"sha256"]) ||
                [paths containsObject:path.lowercaseString]) {
                return AQBrokerFail(error, AQBrokerBindingMismatch);
            }
            [paths addObject:path.lowercaseString];
            [members addObject:@{@"path": path, @"size": @(size),
                                  @"sha256": (NSString *)entry[@"sha256"]}];
        }
    }
    if (members.count == 0) return AQBrokerFail(error, AQBrokerBindingMismatch);
    *membersOut = [members copy];
    *manifestDigestOut = manifestDigest;
    return YES;
}

@interface AQBrokerExportVerifier ()
@property(nonatomic, copy, nullable) AQBrokerExportSink sink;
@property(nonatomic, copy) NSString *expectedSessionID;
@property(nonatomic) uint64_t expectedGeneration;
@property(nonatomic, copy) NSString *expectedManifestSHA256;
@property(nonatomic, copy) NSString *authorizationSHA256;
@property(nonatomic, copy) NSArray<NSDictionary *> *expectedMembers;
@property(nonatomic, copy) NSString *requestID;
@property(nonatomic) uint64_t deadlineNanoseconds;
@property(nonatomic, copy) AQBrokerMonotonicClock clock;
@property(nonatomic, copy) NSString *receiptDirectory;
@property(nonatomic) AQBrokerFrameStage stage;
@property(nonatomic, strong) NSMutableData *buffer;
@property(nonatomic) CC_SHA256_CTX digest;
@property(nonatomic) CC_SHA256_CTX memberDigest;
@property(nonatomic) uint64_t headerLength;
@property(nonatomic) uint64_t memberRemaining;
@property(nonatomic) uint64_t memberOffset;
@property(nonatomic) NSUInteger memberIndex;
@property(nonatomic, copy, nullable) NSArray<NSDictionary *> *members;
@property(nonatomic, readwrite, copy, nullable) NSDictionary *header;
@property(nonatomic, readwrite, copy, nullable) NSDictionary *transportCompletion;
@property(nonatomic, readwrite, copy, nullable) NSDictionary *completion;
@property(nonatomic) int spoolFD;
@property(nonatomic) uint64_t spooledBytes;
@property(nonatomic) uint64_t expectedFrameBytes;
@property(nonatomic) uint64_t payloadStart;
@property(nonatomic) uint64_t payloadBytes;
@property(nonatomic, copy, nullable) NSString *frameSHA256;
@property(nonatomic) BOOL failed;
@property(nonatomic) BOOL emitted;
@end

@implementation AQBrokerExportVerifier
- (instancetype)initWithSink:(AQBrokerExportSink)sink
          expectedSessionID:(NSString *)sessionID
         expectedGeneration:(uint64_t)generation
          expectedManifestSHA256:(NSString *)manifestSHA256
                authorizationSHA256:(NSString *)authorizationSHA256
           approvedManifest:(NSDictionary *)manifest
                  requestID:(NSString *)requestID
          deadlineNanoseconds:(uint64_t)deadlineNanoseconds
                       clock:(AQBrokerMonotonicClock)clock
            receiptDirectory:(NSString *)receiptDirectory
                      error:(NSError **)error {
    if (!(self = [super init])) return nil;
    NSArray<NSDictionary *> *members = nil;
    NSString *manifestDigest = nil;
    if (!AQBrokerToken(sessionID) || !AQBrokerToken(requestID) ||
        !AQBrokerDigest(manifestSHA256) || !AQBrokerDigest(authorizationSHA256) ||
        generation == 0 || deadlineNanoseconds == 0 || clock == nil ||
        ![receiptDirectory isKindOfClass:NSString.class] || receiptDirectory.length == 0 ||
        receiptDirectory.length > PATH_MAX ||
        !AQBrokerApprovedMembers(manifest, &members, &manifestDigest, error)) {
        return nil;
    }
    if (![manifestDigest isEqual:manifestSHA256]) {
        AQBrokerFail(error, AQBrokerBindingMismatch);
        return nil;
    }
    uint64_t remaining = 0;
    if (!AQBrokerDeadlineRemaining(deadlineNanoseconds, clock(), &remaining, error)) return nil;
    _sink = [sink copy];
    _expectedSessionID = [sessionID copy];
    _expectedGeneration = generation;
    _expectedManifestSHA256 = [manifestDigest copy];
    _authorizationSHA256 = [authorizationSHA256 copy];
    _expectedMembers = [members copy];
    _requestID = [requestID copy];
    _deadlineNanoseconds = deadlineNanoseconds;
    _clock = [clock copy];
    _receiptDirectory = [receiptDirectory copy];
    _buffer = [NSMutableData data];
    _stage = AQBrokerFrameMagic;
    _spoolFD = -1;
    CC_SHA256_Init(&_digest);
    return self;
}

- (void)dealloc {
    AQBrokerCloseSpoolDescriptor(&_spoolFD);
}

- (BOOL)checkDeadlineWithError:(NSError **)error {
    uint64_t remaining = 0;
    return AQBrokerDeadlineRemaining(self.deadlineNanoseconds, self.clock(),
                                     &remaining, error);
}

- (void)discardSpool {
    AQBrokerCloseSpoolDescriptor(&_spoolFD);
    _failed = YES;
    [self.buffer setLength:0];
}

- (void)closeVerifiedSpool {
    AQBrokerCloseSpoolDescriptor(&_spoolFD);
}

- (BOOL)ensureSpoolWithError:(NSError **)error {
    if (self.spoolFD >= 0) return YES;
    int fd = -1;
    if (!AQBrokerCreateSpool(&fd, error)) return NO;
    self.spoolFD = fd;
    return YES;
}

- (BOOL)writeSpoolData:(NSData *)data error:(NSError **)error {
    NSUInteger written = 0;
    while (written < data.length) {
        ssize_t count = pwrite(self.spoolFD, (const uint8_t *)data.bytes + written,
                               data.length - written, (off_t)(self.spooledBytes + written));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            AQBrokerErrorCode code = errno == ENOSPC ? AQBrokerSpoolCapacityDenied
                                                     : AQBrokerSpoolUnavailable;
            return AQBrokerFail(error, code);
        }
        written += (NSUInteger)count;
    }
    self.spooledBytes += data.length;
    return YES;
}

- (BOOL)admitFrameCapacityWithPayloadBytes:(uint64_t)payloadBytes error:(NSError **)error {
    uint64_t frameBytes = 0;
    uint64_t payloadStart = 16;
    if (!AQBrokerAddBytes(payloadStart, self.headerLength, &payloadStart) ||
        !AQBrokerAddBytes(payloadStart, payloadBytes, &frameBytes) ||
        !AQBrokerAddBytes(frameBytes, 40, &frameBytes) ||
        frameBytes > (uint64_t)INT64_MAX) {
        return AQBrokerFail(error, AQBrokerFrameTooLarge);
    }
    uint64_t available = 0;
#if defined(AQ_BROKER_TESTING)
    if (AQBrokerTestHasAvailableBytes) {
        available = AQBrokerTestAvailableBytes;
    } else
#endif
    {
        struct statvfs capacity = {0};
        if (fstatvfs(self.spoolFD, &capacity) != 0 || capacity.f_frsize == 0 ||
            capacity.f_bavail > UINT64_MAX / capacity.f_frsize) {
            return AQBrokerFail(error, AQBrokerSpoolCapacityDenied);
        }
        available = (uint64_t)capacity.f_bavail * capacity.f_frsize;
    }
    uint64_t remaining = self.spooledBytes < frameBytes ? frameBytes - self.spooledBytes : 0;
    if ((available < remaining || available - remaining < AQBrokerSpoolReserveBytes) &&
        self.spooledBytes <= frameBytes) {
        return AQBrokerFail(error, AQBrokerSpoolCapacityDenied);
    }
    self.expectedFrameBytes = frameBytes;
    self.payloadStart = payloadStart;
    self.payloadBytes = payloadBytes;
    return YES;
}

- (BOOL)validateHeader:(NSData *)data error:(NSError **)error {
    id parsed = AQParseJSON(data, error);
    if (![parsed isKindOfClass:NSDictionary.class]) return NO;
    NSData *canonical = AQCanonicalJSON(parsed, error);
    if (canonical == nil || ![canonical isEqualToData:data]) {
        return AQBrokerFail(error, AQBrokerInvalidFrame);
    }
    NSDictionary *header = parsed;
    NSSet *keys = [NSSet setWithArray:@[@"schema_version", @"session_id", @"manifest_sha256",
                                         @"generation", @"members"]];
    uint64_t version = 0, generation = 0;
    if (![[NSSet setWithArray:header.allKeys] isEqualToSet:keys] ||
        !AQBrokerInteger(header[@"schema_version"], &version) || version != 1 ||
        ![header[@"session_id"] isKindOfClass:NSString.class] ||
        [header[@"session_id"] length] == 0 || [header[@"session_id"] length] > 256 ||
        !AQBrokerDigest(header[@"manifest_sha256"]) ||
        !AQBrokerInteger(header[@"generation"], &generation) ||
        ![header[@"members"] isKindOfClass:NSArray.class] ||
        [header[@"members"] count] == 0) return AQBrokerFail(error, AQBrokerInvalidFrame);
    NSMutableArray<NSDictionary *> *members = [NSMutableArray array];
    uint64_t payloadBytes = 0;
    for (id entry in header[@"members"]) {
        uint64_t size = 0;
        if (![entry isKindOfClass:NSDictionary.class] ||
            ![[NSSet setWithArray:[entry allKeys]] isEqualToSet:
                [NSSet setWithArray:@[@"path", @"size", @"sha256"]]] ||
            !AQBrokerSafePath(entry[@"path"]) || !AQBrokerInteger(entry[@"size"], &size) ||
            !AQBrokerDigest(entry[@"sha256"]) ||
            !AQBrokerAddBytes(payloadBytes, size, &payloadBytes)) {
            return AQBrokerFail(error, AQBrokerInvalidFrame);
        }
        [members addObject:entry];
    }
    if (![header[@"session_id"] isEqual:self.expectedSessionID] ||
        generation != self.expectedGeneration ||
        ![header[@"manifest_sha256"] isEqual:self.expectedManifestSHA256] ||
        ![members isEqualToArray:self.expectedMembers]) {
        return AQBrokerFail(error, AQBrokerBindingMismatch);
    }
    self.members = members;
    self.memberIndex = 0;
    self.memberOffset = 0;
    self.headerLength = data.length;
    if (![self admitFrameCapacityWithPayloadBytes:payloadBytes error:error]) return NO;
    _header = [header copy];
    return YES;
}

- (void)advanceMember {
    self.memberIndex++;
    if (self.memberIndex == self.members.count) {
        self.stage = AQBrokerFrameTrailer;
        return;
    }
    uint64_t size = 0;
    AQBrokerInteger(self.members[self.memberIndex][@"size"], &size);
    self.memberRemaining = size;
    self.memberOffset = 0;
    CC_SHA256_Init(&_memberDigest);
}

- (nullable NSString *)membersSHA256 {
    NSArray<NSDictionary *> *members = self.members;
    if (members == nil) return nil;
    return AQDigest(@"argus.fixture-staging.export-members.v1", members, NULL);
}

- (BOOL)advanceMembersWithError:(NSError **)error {
    while (self.stage == AQBrokerFrameMembers) {
        NSDictionary *member = self.members[self.memberIndex];
        if (self.memberRemaining == 0) {
            unsigned char output[CC_SHA256_DIGEST_LENGTH] = {0};
            CC_SHA256_Final(output, &_memberDigest);
            NSMutableString *digest = [NSMutableString string];
            for (NSUInteger index = 0; index < sizeof(output); ++index) {
                [digest appendFormat:@"%02x", output[index]];
            }
            if (![digest isEqual:member[@"sha256"]]) {
                return AQBrokerFail(error, AQBrokerFrameMemberMismatch);
            }
            [self advanceMember];
            continue;
        }
        if (self.buffer.length == 0) return YES;
        NSUInteger amount = (NSUInteger)MIN((uint64_t)self.buffer.length, self.memberRemaining);
        NSData *chunk = [self.buffer subdataWithRange:NSMakeRange(0, amount)];
        CC_SHA256_Update(&_digest, chunk.bytes, (CC_LONG)chunk.length);
        CC_SHA256_Update(&_memberDigest, chunk.bytes, (CC_LONG)chunk.length);
        self.memberOffset += amount;
        self.memberRemaining -= amount;
        [self.buffer replaceBytesInRange:NSMakeRange(0, amount) withBytes:NULL length:0];
    }
    return YES;
}

- (BOOL)processBufferWithError:(NSError **)error {
    while (YES) {
        if (self.stage == AQBrokerFrameComplete) {
            return self.buffer.length == 0 ? YES : AQBrokerFail(error, AQBrokerInvalidFrame);
        }
        if (self.stage == AQBrokerFrameMembers) {
            if (![self advanceMembersWithError:error]) return NO;
            if (self.stage == AQBrokerFrameMembers && self.buffer.length == 0) return YES;
            continue;
        }
        NSUInteger needed = 0;
        if (self.stage == AQBrokerFrameMagic || self.stage == AQBrokerFrameLength ||
            self.stage == AQBrokerFrameTrailer) needed = 8;
        else if (self.stage == AQBrokerFrameDigest) needed = CC_SHA256_DIGEST_LENGTH;
        else if (self.stage == AQBrokerFrameHeader) needed = (NSUInteger)self.headerLength;
        if (needed == 0 || self.buffer.length < needed) return YES;

        if (self.stage == AQBrokerFrameMagic) {
            static const unsigned char magic[8] = {'A','Q','S','N','A','P','1','\n'};
            if (memcmp(self.buffer.bytes, magic, 8) != 0) {
                return AQBrokerFail(error, AQBrokerInvalidFrame);
            }
            CC_SHA256_Update(&_digest, self.buffer.bytes, 8);
            [self.buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            self.stage = AQBrokerFrameLength;
        } else if (self.stage == AQBrokerFrameLength) {
            const unsigned char *bytes = self.buffer.bytes;
            uint64_t length = 0;
            for (NSUInteger index = 0; index < 8; ++index) length = (length << 8) | bytes[index];
            if (length < 2 || length > AQStoreMaximumExportMetadataHeaderBytes) {
                return AQBrokerFail(error, AQBrokerFrameTooLarge);
            }
            CC_SHA256_Update(&_digest, self.buffer.bytes, 8);
            [self.buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            self.headerLength = length;
            self.stage = AQBrokerFrameHeader;
        } else if (self.stage == AQBrokerFrameHeader) {
            NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, needed)];
            CC_SHA256_Update(&_digest, headerData.bytes, (CC_LONG)headerData.length);
            [self.buffer replaceBytesInRange:NSMakeRange(0, needed) withBytes:NULL length:0];
            if (![self validateHeader:headerData error:error]) return NO;
            uint64_t size = 0;
            AQBrokerInteger(self.members[0][@"size"], &size);
            self.memberRemaining = size;
            self.memberOffset = 0;
            CC_SHA256_Init(&_memberDigest);
            self.stage = AQBrokerFrameMembers;
        } else if (self.stage == AQBrokerFrameTrailer) {
            static const unsigned char trailer[8] = {'A','Q','E','N','D','1','\r','\n'};
            if (memcmp(self.buffer.bytes, trailer, 8) != 0) {
                return AQBrokerFail(error, AQBrokerInvalidFrame);
            }
            [self.buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            self.stage = AQBrokerFrameDigest;
        } else if (self.stage == AQBrokerFrameDigest) {
            unsigned char expected[CC_SHA256_DIGEST_LENGTH] = {0};
            CC_SHA256_Final(expected, &_digest);
            if (memcmp(self.buffer.bytes, expected, sizeof(expected)) != 0) {
                return AQBrokerFail(error, AQBrokerFrameDigestMismatch);
            }
            NSMutableString *frameDigest = [NSMutableString string];
            for (NSUInteger index = 0; index < sizeof(expected); ++index) {
                [frameDigest appendFormat:@"%02x", expected[index]];
            }
            NSString *membersDigest = [self membersSHA256];
            NSArray<NSDictionary *> *members = self.members;
            if (membersDigest == nil || members == nil) {
                return AQBrokerFail(error, AQBrokerInvalidFrame);
            }
            self.frameSHA256 = frameDigest;
            self.transportCompletion = @{
                @"schema_version": @1,
                @"status": @"VERIFIED_TRANSPORT_COMPLETION",
                @"code": @"BROKER_FRAME_VERIFIED",
                @"request_id": self.requestID,
                @"session_id": self.expectedSessionID,
                @"generation": @(self.expectedGeneration),
                @"manifest_sha256": self.expectedManifestSHA256,
                @"deadline_ns": @(self.deadlineNanoseconds),
                @"frame_sha256": frameDigest,
                @"members": members,
                @"members_sha256": membersDigest,
                @"member_count": @(members.count)
            };
            [self.buffer replaceBytesInRange:NSMakeRange(0, sizeof(expected))
                                    withBytes:NULL length:0];
            self.stage = AQBrokerFrameComplete;
            if (self.buffer.length != 0) return AQBrokerFail(error, AQBrokerInvalidFrame);
        }
    }
}

- (BOOL)consumeData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) return YES;
    if (self.failed) return AQBrokerFail(error, AQBrokerInvalidFrame);
    if (![self checkDeadlineWithError:error]) {
        [self discardSpool];
        return NO;
    }
    if (self.stage == AQBrokerFrameComplete) {
        [self discardSpool];
        return AQBrokerFail(error, AQBrokerInvalidFrame);
    }
    if (![self ensureSpoolWithError:error]) {
        self.failed = YES;
        return NO;
    }
    NSUInteger inputOffset = 0;
    while (inputOffset < data.length) {
        if (![self checkDeadlineWithError:error]) {
            [self discardSpool];
            return NO;
        }
        if (self.stage == AQBrokerFrameComplete) {
            [self discardSpool];
            return AQBrokerFail(error, AQBrokerInvalidFrame);
        }
        NSUInteger take = MIN(AQBrokerSpoolChunkBytes, data.length - inputOffset);
        if (self.expectedFrameBytes != 0) {
            uint64_t remaining = self.expectedFrameBytes - self.spooledBytes;
            if (remaining == 0) {
                [self discardSpool];
                return AQBrokerFail(error, AQBrokerInvalidFrame);
            }
            take = (NSUInteger)MIN((uint64_t)take, remaining);
        }
        NSData *piece = [data subdataWithRange:NSMakeRange(inputOffset, take)];
        if (![self writeSpoolData:piece error:error]) {
            [self discardSpool];
            return NO;
        }
        [self.buffer appendData:piece];
        inputOffset += take;
        if (![self processBufferWithError:error]) {
            [self discardSpool];
            return NO;
        }
    }
    return YES;
}

- (BOOL)verifySpoolMemberDigestsWithError:(NSError **)error {
    uint8_t buffer[AQBrokerSpoolChunkBytes];
    uint64_t offset = self.payloadStart;
    for (NSDictionary *member in self.members) {
        uint64_t remaining = 0;
        if (!AQBrokerInteger(member[@"size"], &remaining)) {
            return AQBrokerFail(error, AQBrokerInvalidFrame);
        }
        CC_SHA256_CTX digestContext;
        CC_SHA256_Init(&digestContext);
        while (remaining != 0) {
            if (![self checkDeadlineWithError:error]) return NO;
            size_t requested = (size_t)MIN((uint64_t)sizeof(buffer), remaining);
            ssize_t count = pread(self.spoolFD, buffer, requested, (off_t)offset);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) return AQBrokerFail(error, AQBrokerSpoolUnavailable);
            CC_SHA256_Update(&digestContext, buffer, (CC_LONG)count);
            offset += (uint64_t)count;
            remaining -= (uint64_t)count;
        }
        unsigned char digestBytes[CC_SHA256_DIGEST_LENGTH] = {0};
        CC_SHA256_Final(digestBytes, &digestContext);
        NSMutableString *digest = [NSMutableString stringWithCapacity:64];
        for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
            [digest appendFormat:@"%02x", digestBytes[index]];
        }
        if (![digest isEqual:member[@"sha256"]]) {
            return AQBrokerFail(error, AQBrokerFrameMemberMismatch);
        }
    }
    return YES;
}

- (BOOL)emitVerifiedPayloadWithError:(NSError **)error {
    if (self.sink == nil) {
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    if (![self verifySpoolMemberDigestsWithError:error]) return NO;
    uint8_t buffer[AQBrokerSpoolChunkBytes];
    uint64_t offset = self.payloadStart;
    for (NSDictionary *member in self.members) {
        uint64_t remaining = 0;
        AQBrokerInteger(member[@"size"], &remaining);
        uint64_t memberOffset = 0;
            CC_SHA256_CTX deliveredMemberDigest;
            CC_SHA256_Init(&deliveredMemberDigest);
        while (remaining != 0) {
            if (![self checkDeadlineWithError:error]) return NO;
            size_t requested = (size_t)MIN((uint64_t)sizeof(buffer), remaining);
            ssize_t count = pread(self.spoolFD, buffer, requested, (off_t)offset);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) return AQBrokerFail(error, AQBrokerSpoolUnavailable);
            NSData *chunk = [[NSData alloc] initWithBytes:buffer length:(NSUInteger)count];
            if (!self.sink((NSString *)member[@"path"], chunk, memberOffset)) {
                return AQBrokerFail(error, AQBrokerSpoolUnavailable);
            }
                CC_SHA256_Update(&deliveredMemberDigest, chunk.bytes,
                                 (CC_LONG)chunk.length);
            if (![self checkDeadlineWithError:error]) return NO;
            offset += (uint64_t)count;
            memberOffset += (uint64_t)count;
            remaining -= (uint64_t)count;
        }
            unsigned char deliveredDigestBytes[CC_SHA256_DIGEST_LENGTH] = {0};
            CC_SHA256_Final(deliveredDigestBytes, &deliveredMemberDigest);
            NSMutableString *deliveredDigest = [NSMutableString stringWithCapacity:64];
            for (NSUInteger digestIndex = 0;
                 digestIndex < CC_SHA256_DIGEST_LENGTH; digestIndex++) {
                [deliveredDigest appendFormat:@"%02x", deliveredDigestBytes[digestIndex]];
            }
            if (![deliveredDigest isEqual:member[@"sha256"]]) {
                return AQBrokerFail(error, AQBrokerFrameMemberMismatch);
            }
    }
    return YES;
}

- (BOOL)persistReceiverReceiptInDirectory:(int)directoryFD error:(NSError **)error {
    if (self.transportCompletion == nil || self.frameSHA256 == nil ||
        ![self checkDeadlineWithError:error]) {
        return NO;
    }
    NSString *frameSHA256 = self.frameSHA256;
    NSArray<NSDictionary *> *members = self.members;
    NSString *membersSHA256 = self.transportCompletion[@"members_sha256"];
    if (frameSHA256 == nil || members == nil || !AQBrokerDigest(membersSHA256)) {
        return AQBrokerFail(error, AQBrokerDurableReceiptFailed);
    }
    NSDictionary *binding = @{
        @"schema_version": @1,
        @"request_id": self.requestID,
        @"session_id": self.expectedSessionID,
        @"generation": @(self.expectedGeneration),
        @"manifest_sha256": self.expectedManifestSHA256,
        @"authorization_sha256": self.authorizationSHA256,
        @"deadline_ns": @(self.deadlineNanoseconds),
        @"frame_sha256": frameSHA256,
        @"members": members
    };
    NSString *bindingDigest = AQDigest(@"argus.fixture-staging.receiver-receipt-name.v1",
                                        binding, NULL);
    if (bindingDigest == nil) return AQBrokerFail(error, AQBrokerDurableReceiptFailed);
    NSString *receiptName = [NSString stringWithFormat:@"export-%@.receipt.json",
                                                       [bindingDigest substringToIndex:32]];

    const char *receiptNameBytes = receiptName.UTF8String;
    if (receiptNameBytes == NULL) return AQBrokerFail(error, AQBrokerDurableReceiptFailed);
    NSMutableDictionary *receipt = [self.transportCompletion mutableCopy];
    receipt[@"schema_version"] = @1;
    receipt[@"status"] = @"VERIFIED_RECEIVER_COMPLETION";
    receipt[@"code"] = @"BROKER_RECEIVER_RECEIPT_DURABLE";
    receipt[@"authorization_sha256"] = self.authorizationSHA256;
    receipt[@"durable"] = @YES;
    NSData *receiptData = AQCanonicalJSONWithMaximumBytes(
        receipt, AQServiceMaximumReceiptBytes, error);
    if (receiptData == nil) return NO;

    /* A previous attempt may have published this exact complete receipt before
     * losing its acknowledgement. Accept only byte-identical durable content. */
    if (faccessat(directoryFD, receiptNameBytes, F_OK, AT_SYMLINK_NOFOLLOW) == 0) {
        if (!AQBrokerExistingReceiptMatches(directoryFD, receiptNameBytes,
                                            receiptData, error) ||
            !AQBrokerSyncDescriptor(directoryFD, error)) return NO;
        goto receipt_is_durable;
    }

    char temporaryName[NAME_MAX + 1] = {0};
    int fd = -1;
    for (unsigned attempt = 0; attempt < 32; ++attempt) {
        snprintf(temporaryName, sizeof(temporaryName), ".%s.%016llx.tmp",
                 receiptNameBytes, (unsigned long long)arc4random());
        fd = openat(directoryFD, temporaryName,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd >= 0 || errno != EEXIST) break;
    }
    if (fd < 0) return AQBrokerWriteFailure(error, errno);
    struct stat owned = {0};
    BOOL ownsTemporary = fstat(fd, &owned) == 0 && S_ISREG(owned.st_mode) &&
        owned.st_uid == geteuid() && owned.st_nlink == 1;
    BOOL success = ownsTemporary &&
        AQBrokerWriteAllUntilDeadline(fd, receiptData, self.deadlineNanoseconds,
                                      self.clock, error);
    if (success && ![self checkDeadlineWithError:error]) success = NO;
    if (success) success = AQBrokerSyncDescriptor(fd, error);

    struct stat info = {0};
    if (success) {
        if (fstat(fd, &info) != 0) {
            AQBrokerWriteFailure(error, errno);
            success = NO;
        } else if (!S_ISREG(info.st_mode) || info.st_uid != geteuid() ||
                   info.st_nlink != 1 || (info.st_mode & 0777) != (S_IRUSR | S_IWUSR) ||
                   info.st_size < 0 || (NSUInteger)info.st_size != receiptData.length) {
            AQBrokerWriteFailure(error, EIO);
            success = NO;
        }
    }
    int closeResult = close(fd);
    if (success && closeResult != 0) {
        AQBrokerWriteFailure(error, errno);
        success = NO;
    }
    if (success && ![self checkDeadlineWithError:error]) success = NO;
    BOOL publishedByThisAttempt = NO;
    if (success) {
        if (linkat(directoryFD, temporaryName, directoryFD, receiptNameBytes, 0) == 0) {
            publishedByThisAttempt = YES;
        } else if (errno == EEXIST &&
                   AQBrokerExistingReceiptMatches(directoryFD, receiptNameBytes,
                                                  receiptData, error)) {
            success = YES;
        } else {
            AQBrokerWriteFailure(error, errno);
            success = NO;
        }
    }
    if (success) success = AQBrokerSyncDescriptor(directoryFD, error);
    if (success) {
        struct stat current = {0};
        if (fstatat(directoryFD, temporaryName, &current, AT_SYMLINK_NOFOLLOW) == 0 &&
            current.st_dev == owned.st_dev && current.st_ino == owned.st_ino)
            (void)unlinkat(directoryFD, temporaryName, 0);
        success = AQBrokerSyncDescriptor(directoryFD, error);
    }
    if (!success) {
        AQBrokerRemoveOwnedTemporary(directoryFD, temporaryName,
                                    owned.st_dev, owned.st_ino);
        /* A failed directory sync makes this attempt unacknowledgeable. Remove
         * only the final link published from this verified temporary inode so
         * its deterministic name cannot turn a failed attempt into a retry
         * blocker. A pre-existing or concurrently published receipt is kept. */
        if (publishedByThisAttempt) {
            struct stat current = {0};
            if (fstatat(directoryFD, receiptNameBytes, &current,
                        AT_SYMLINK_NOFOLLOW) == 0 &&
                current.st_dev == owned.st_dev && current.st_ino == owned.st_ino &&
                unlinkat(directoryFD, receiptNameBytes, 0) == 0) {
                (void)AQBrokerSyncDescriptor(directoryFD, NULL);
            }
        }
        return NO;
    }

receipt_is_durable:
    ;

    NSString *receiptDigest = AQDigest(@"", receipt, error);
    if (receiptDigest == nil) return NO;
    NSString *receiptPath = [self.receiptDirectory stringByAppendingPathComponent:receiptName];
    self.completion = @{
        @"schema_version": @1,
        @"status": @"VERIFIED_RECEIVER_COMPLETION",
        @"code": @"BROKER_RECEIVER_RECEIPT_DURABLE",
        @"request_id": self.requestID,
        @"session_id": self.expectedSessionID,
        @"generation": @(self.expectedGeneration),
        @"manifest_sha256": self.expectedManifestSHA256,
        @"authorization_sha256": self.authorizationSHA256,
        @"deadline_ns": @(self.deadlineNanoseconds),
        @"frame_sha256": frameSHA256,
        @"members": members,
        @"members_sha256": membersSHA256,
        @"member_count": @(members.count),
        @"durable": @YES,
        @"receipt_path": receiptPath,
        @"receipt_sha256": receiptDigest
    };
    return YES;
}

- (BOOL)finishWithError:(NSError **)error {
    if (self.emitted) return self.completion != nil;
    if (self.failed || self.stage != AQBrokerFrameComplete || self.buffer.length != 0 ||
        self.expectedFrameBytes == 0 || self.spooledBytes != self.expectedFrameBytes) {
        [self discardSpool];
        return AQBrokerFail(error, AQBrokerInvalidFrame);
    }
    if (![self checkDeadlineWithError:error]) {
        [self discardSpool];
        return NO;
    }
    if (self.sink == nil) {
        [self discardSpool];
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    struct stat info = {0};
    if (!AQBrokerSpoolMetadataValid(self.spoolFD, &info) || info.st_size < 0 ||
        (uint64_t)info.st_size != self.expectedFrameBytes) {
        [self discardSpool];
        return AQBrokerFail(error, AQBrokerSpoolUnavailable);
    }
    int receiptDirectoryFD = -1;
    if (!AQBrokerOpenReceiptDirectory(self.receiptDirectory, &receiptDirectoryFD, error)) {
        [self discardSpool];
        return NO;
    }
    if (!AQBrokerSyncDescriptor(self.spoolFD, error)) {
        close(receiptDirectoryFD);
        [self discardSpool];
        return NO;
    }
    if (![self emitVerifiedPayloadWithError:error]) {
        close(receiptDirectoryFD);
        [self discardSpool];
        return NO;
    }
    BOOL receiptPersisted = [self persistReceiverReceiptInDirectory:receiptDirectoryFD error:error];
    int directoryCloseResult = close(receiptDirectoryFD);
    if (receiptPersisted && directoryCloseResult != 0) {
        AQBrokerWriteFailure(error, errno);
        receiptPersisted = NO;
    }
    if (!receiptPersisted) {
        [self discardSpool];
        return NO;
    }
    self.emitted = YES;
    [self closeVerifiedSpool];
    return YES;
}
@end

#if defined(AQ_BROKER_TESTING)
int AQBrokerTestSpoolDescriptor(AQBrokerExportVerifier *verifier) {
    return verifier.spoolFD;
}

NSString *AQBrokerTestSpoolPath(AQBrokerExportVerifier *verifier) {
    if (verifier.spoolFD < 0 || verifier.spoolFD != AQBrokerTestLastSpoolFD ||
        AQBrokerTestLastSpoolPathname[0] == '\0') {
        return nil;
    }
    return [NSString stringWithUTF8String:AQBrokerTestLastSpoolPathname];
}

void AQBrokerTestSetSpoolAvailableBytes(uint64_t availableBytes) {
    AQBrokerTestAvailableBytes = availableBytes;
    AQBrokerTestHasAvailableBytes = YES;
}

void AQBrokerTestClearSpoolAvailableBytes(void) {
    AQBrokerTestAvailableBytes = 0;
    AQBrokerTestHasAvailableBytes = NO;
}

void AQBrokerTestForceSpoolUnavailableForTesting(BOOL unavailable) {
    AQBrokerTestForceSpoolUnavailable = unavailable;
}

void AQBrokerTestSetNextSyncFailure(int errorNumber) {
    AQBrokerTestSetSyncFailureAfter(0, errorNumber);
}

void AQBrokerTestSetSyncFailureAfter(NSUInteger successfulSyncs, int errorNumber) {
    AQBrokerTestNextSyncError = errorNumber != 0 ? errorNumber : EIO;
    AQBrokerTestSyncSuccessesBeforeFailure = successfulSyncs;
}

void AQBrokerTestSetWriteFailureAfterBytes(NSUInteger bytes) {
    AQBrokerTestWriteBytesBeforeFailure = bytes;
    AQBrokerTestWriteFailureArmed = YES;
}
#endif

static BOOL AQBrokerToken(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] == 0 || [value length] > 256) {
        return NO;
    }
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"];
    });
    return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static BOOL AQBrokerKnownOperation(NSString *operation) {
    static NSSet<NSString *> *operations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        operations = [NSSet setWithArray:@[
            @"readiness", @"hello", @"admit", @"stage", @"eligibility",
            @"export", @"cleanup", @"inspect", @"recovery"
        ]];
    });
    return [operations containsObject:operation];
}

static BOOL AQBrokerInspectionOperation(NSString *operation) {
    return [operation isEqual:@"readiness"] || [operation isEqual:@"hello"] ||
           [operation isEqual:@"eligibility"] || [operation isEqual:@"inspect"] ||
           [operation isEqual:@"recovery"];
}

static BOOL AQBrokerDecodeFreshness(NSDictionary *request, NSDictionary **freshness,
                                    NSError **error) {
    id encoded = request[@"freshness_envelope"];
    if (![encoded isKindOfClass:NSString.class] || [encoded length] == 0 ||
        [encoded length] > (NSUInteger)2 * AQServiceMaximumRequestBytes) {
        return AQBrokerFail(error, AQBrokerInvalidRequest);
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (data.length == 0 || data.length > AQServiceMaximumRequestBytes ||
        ![encoded isEqual:[data base64EncodedStringWithOptions:0]]) {
        return AQBrokerFail(error, AQBrokerInvalidRequest);
    }
    id parsed = AQParseJSON(data, error);
    if (![parsed isKindOfClass:NSDictionary.class] ||
        ![AQCanonicalJSON(parsed, NULL) isEqualToData:data]) {
        return AQBrokerFail(error, AQBrokerInvalidRequest);
    }
    *freshness = parsed;
    return YES;
}

static BOOL AQBrokerRequestDeadline(NSDictionary *request, uint64_t *deadline,
                                    NSError **error) {
    uint64_t topLevelDeadline = 0;
    BOOL hasTopLevelDeadline = AQBrokerInteger(request[@"deadline_ns"], &topLevelDeadline) &&
                               topLevelDeadline > 0;
    NSDictionary *freshness = nil;
    if (request[@"freshness_envelope"] == nil) {
        if (!hasTopLevelDeadline) return AQBrokerFail(error, AQBrokerInvalidRequest);
        if (deadline != NULL) *deadline = topLevelDeadline;
        return YES;
    }
    if (!AQBrokerDecodeFreshness(request, &freshness, error)) return NO;
    uint64_t signedDeadline = 0;
    if (!AQBrokerInteger(freshness[@"deadline_ns"], &signedDeadline) || signedDeadline == 0 ||
        (hasTopLevelDeadline && topLevelDeadline != signedDeadline)) {
        return AQBrokerFail(error, AQBrokerBindingMismatch);
    }
    if (deadline != NULL) *deadline = signedDeadline;
    return YES;
}

static BOOL AQBrokerRequestClaimsMatchFreshness(NSDictionary *request, NSError **error) {
    if (request[@"freshness_envelope"] == nil) return YES;
    NSDictionary *freshness = nil;
    if (!AQBrokerDecodeFreshness(request, &freshness, error)) return NO;
    if (![freshness[@"request_id"] isEqual:request[@"request_id"]] ||
        ![freshness[@"operation"] isEqual:request[@"operation"]] ||
        ![freshness[@"session_id"] isEqual:request[@"session_id"]] ||
        ![freshness[@"connection_id"] isEqual:request[@"connection_id"]]) {
        return AQBrokerFail(error, AQBrokerBindingMismatch);
    }
    for (NSString *key in @[ @"authorization_sha256", @"manifest_sha256",
                              @"plan_sha256", @"rules_sha256" ]) {
        id claimed = request[key];
        id signedValue = freshness[key];
        if (claimed != nil &&
            (!AQBrokerDigest(signedValue) || ![claimed isEqual:signedValue])) {
            return AQBrokerFail(error, AQBrokerBindingMismatch);
        }
    }
    return YES;
}

static BOOL AQBrokerRequestSequence(NSDictionary *request, uint64_t *sequence,
                                    NSError **error) {
    NSDictionary *freshness = nil;
    if (!AQBrokerDecodeFreshness(request, &freshness, error)) return NO;
    if (!AQBrokerInteger(freshness[@"sequence"], sequence) || *sequence == 0) {
        return AQBrokerFail(error, AQBrokerSequenceMismatch);
    }
    return YES;
}

static BOOL AQBrokerOwnerBindingForRequest(NSDictionary *request,
                                           NSDictionary **bindingOut,
                                           NSError **error) {
    NSString *operation = request[@"operation"];
    NSDictionary *source = request;
    if (![operation isEqual:@"hello"] && ![operation isEqual:@"readiness"]) {
        if (!AQBrokerDecodeFreshness(request, &source, error)) return NO;
    }

    NSMutableDictionary *binding = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"installation_id", @"service_boot_id", @"broker_revision",
                            @"owner_key_id"]) {
        if (!AQBrokerToken(source[key])) return AQBrokerFail(error, AQBrokerInvalidRequest);
        binding[key] = source[key];
    }
    if ([operation isEqual:@"hello"]) {
        if (!AQBrokerToken(request[@"grant_id"])) {
            return AQBrokerFail(error, AQBrokerInvalidRequest);
        }
        binding[@"grant_id"] = request[@"grant_id"];
    }
    *bindingOut = [binding copy];
    return YES;
}

static BOOL AQBrokerBindingsMatch(NSDictionary *expected, NSDictionary *actual) {
    for (NSString *key in expected) {
        if ([key isEqual:@"grant_id"] && actual[key] == nil) continue;
        if (![expected[key] isEqual:actual[key]]) return NO;
    }
    return YES;
}

uint64_t AQBrokerSystemClockNanoseconds(void) {
    uint64_t now = 0;
    return AQServiceMonotonicNanosecondsNow(&now) ? now : UINT64_MAX;
}

BOOL AQBrokerDeadlineRemaining(uint64_t deadlineNanoseconds,
                               uint64_t nowNanoseconds,
                               uint64_t *remainingNanoseconds,
                               NSError **error) {
    if (remainingNanoseconds == NULL || deadlineNanoseconds == 0 ||
        nowNanoseconds == UINT64_MAX || nowNanoseconds >= deadlineNanoseconds) {
        return AQBrokerFail(error, AQBrokerDeadlineExpired);
    }
    *remainingNanoseconds = deadlineNanoseconds - nowNanoseconds;
    return YES;
}

@interface AQBrokerReconnectGuard () {
    NSLock *_lock;
    BOOL _connectionOpen;
    BOOL _operationInFlight;
    BOOL _mutationInFlight;
    BOOL _uncertainEffect;
    BOOL _outcomeUnknown;
    NSUInteger _generation;
}
@end

@implementation AQBrokerReconnectGuard
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _lock = [[NSLock alloc] init];
    _connectionOpen = YES;
    _generation = 1;
    return self;
}

- (BOOL)connectionOpened {
    [_lock lock];
    BOOL accepted = !_operationInFlight;
    if (accepted) _connectionOpen = YES;
    [_lock unlock];
    return accepted;
}

- (BOOL)dispatchInspection {
    [_lock lock];
    BOOL accepted = _connectionOpen && !_operationInFlight;
    if (accepted) _operationInFlight = YES;
    [_lock unlock];
    return accepted;
}

- (BOOL)dispatchMutation {
    [_lock lock];
    BOOL accepted = _connectionOpen && !_operationInFlight && !_uncertainEffect;
    if (accepted) {
        _operationInFlight = YES;
        _mutationInFlight = YES;
    }
    [_lock unlock];
    return accepted;
}

- (void)operationCompleted {
    [_lock lock];
    _operationInFlight = NO;
    _mutationInFlight = NO;
    [_lock unlock];
}

- (void)connectionLostWithOutcomeKnown:(BOOL)known {
    [_lock lock];
    if (!known) {
        if (_operationInFlight) _outcomeUnknown = YES;
        if (_mutationInFlight) _uncertainEffect = YES;
    }
    _operationInFlight = NO;
    _mutationInFlight = NO;
    if (_connectionOpen) {
        _connectionOpen = NO;
        _generation++;
    }
    [_lock unlock];
}

- (BOOL)canDispatchInspection {
    [_lock lock];
    BOOL allowed = _connectionOpen && !_operationInFlight;
    [_lock unlock];
    return allowed;
}

- (BOOL)canDispatchMutation {
    [_lock lock];
    BOOL allowed = _connectionOpen && !_operationInFlight && !_uncertainEffect;
    [_lock unlock];
    return allowed;
}

- (BOOL)isOperationInFlight {
    [_lock lock];
    BOOL value = _operationInFlight;
    [_lock unlock];
    return value;
}

- (BOOL)uncertainEffect {
    [_lock lock];
    BOOL value = _uncertainEffect;
    [_lock unlock];
    return value;
}

- (BOOL)outcomeUnknown {
    [_lock lock];
    BOOL value = _outcomeUnknown;
    [_lock unlock];
    return value;
}

- (NSUInteger)generation {
    [_lock lock];
    NSUInteger value = _generation;
    [_lock unlock];
    return value;
}
@end

@interface AQBrokerSequentialSession () {
    NSLock *_lock;
    AQBrokerMonotonicClock _clock;
    AQBrokerReconnectGuard *_reconnectGuard;
    BOOL _enforcesOrdering;
    BOOL _hasActiveRequest;
    BOOL _activeMutation;
    BOOL _activeResponseAccepted;
    BOOL _helloCompleted;
    BOOL _requiresFreshAuthentication;
    BOOL _outcomeUnknown;
    uint64_t _nextToken;
    uint64_t _activeToken;
    uint64_t _activeSequence;
    uint64_t _activeDeadline;
    uint64_t _sessionDeadline;
    uint64_t _nextSequence;
    NSString *_activeRequestID;
    NSDictionary *_activeRequest;
    NSDictionary *_activeResponse;
    NSDictionary *_ownerBinding;
    NSString *_sessionID;
    NSString *_connectionID;
    NSMutableSet<NSString *> *_dispatchedRequestIDs;
}
@end

static BOOL AQBrokerOwnerContinuationFail(NSError **error, NSString *description) {
    (void)description;
    if (error != NULL) *error = AQBrokerError(AQBrokerBindingMismatch);
    return NO;
}

static NSString *AQBrokerOwnerContinuationSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static BOOL AQBrokerOwnerContinuationString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 &&
        [value length] <= 64 * 1024;
}

@interface AQBrokerOwnerExportContinuation ()
@property(nonatomic, copy) NSString *installationID;
@property(nonatomic, copy) NSString *serviceBootID;
@property(nonatomic, copy) NSString *brokerRevision;
@property(nonatomic, copy) NSString *ownerKeyID;
@property(nonatomic, copy) NSString *connectionID;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *authorizationSHA256;
@property(nonatomic, copy, readwrite) NSString *attemptSHA256;
@property(nonatomic, copy) NSArray<NSDictionary *> *workflow;
@property(nonatomic, copy) NSString *activeOperation;
@property(nonatomic) NSUInteger nextOperationIndex;
@property(nonatomic) BOOL journalAcknowledged;
@property(nonatomic, readwrite, getter=isDispatchComplete) BOOL dispatchComplete;
@end

@implementation AQBrokerOwnerExportContinuation

- (nullable instancetype)initWithHelloResponse:(NSDictionary *)helloResponse
                               installationID:(NSString *)installationID
                                brokerRevision:(NSString *)brokerRevision
                                     ownerKeyID:(NSString *)ownerKeyID
                          authorizationSHA256:(NSString *)authorizationSHA256 {
    NSString *connectionID = helloResponse[@"connection_id"];
    NSString *sessionID = helloResponse[@"session_id"];
    NSString *serviceBootID = helloResponse[@"service_boot_id"];
    if (![helloResponse isKindOfClass:NSDictionary.class] ||
        !AQBrokerToken(installationID) || !AQBrokerToken(brokerRevision) ||
        !AQBrokerToken(ownerKeyID) || !AQBrokerDigest(authorizationSHA256) ||
        !AQBrokerToken(connectionID) || !AQBrokerToken(sessionID) ||
        !AQBrokerToken(serviceBootID)) {
        return nil;
    }
    self = [super init];
    if (self) {
        _installationID = [installationID copy];
        _serviceBootID = [serviceBootID copy];
        _brokerRevision = [brokerRevision copy];
        _ownerKeyID = [ownerKeyID copy];
        _connectionID = [connectionID copy];
        _sessionID = [sessionID copy];
        _authorizationSHA256 = [authorizationSHA256 copy];
    }
    return self;
}

- (BOOL)prepareAttempt:(NSDictionary *)attempt
              workflow:(NSArray<NSDictionary *> *)workflow
                 error:(NSError **)error {
    NSArray<NSString *> *operations = @[@"admit", @"stage", @"export"];
    if (self.workflow != nil || ![attempt isKindOfClass:NSDictionary.class] ||
        ![workflow isKindOfClass:NSArray.class] || workflow.count != 4 ||
        ![attempt[@"operation"] isEqual:@"export"] ||
        ![attempt[@"installation_id"] isEqual:self.installationID] ||
        ![attempt[@"service_boot_id"] isEqual:self.serviceBootID] ||
        ![attempt[@"broker_revision"] isEqual:self.brokerRevision] ||
        ![attempt[@"owner_key_id"] isEqual:self.ownerKeyID] ||
        ![attempt[@"connection_id"] isEqual:self.connectionID] ||
        ![attempt[@"session_id"] isEqual:self.sessionID] ||
        ![attempt[@"authorization_sha256"] isEqual:self.authorizationSHA256] ||
        !AQBrokerToken(attempt[@"request_id"]) ||
        !AQBrokerDigest(attempt[@"manifest_sha256"]) ||
        !AQBrokerDigest(attempt[@"request_sha256"])) {
        return AQBrokerOwnerContinuationFail(error, @"OWNER_EXPORT_PREPARATION_INVALID");
    }
    NSDictionary *hello = workflow.firstObject;
    if (![hello isKindOfClass:NSDictionary.class] ||
        ![hello[@"operation"] isEqual:@"hello"]) {
        return AQBrokerOwnerContinuationFail(error, @"OWNER_EXPORT_HELLO_BINDING_INVALID");
    }
    for (NSUInteger index = 0; index < operations.count; index++) {
        NSDictionary *request = workflow[index + 1];
        if (![request isKindOfClass:NSDictionary.class] ||
            ![request[@"operation"] isEqual:operations[index]] ||
            ![request[@"installation_id"] isEqual:self.installationID] ||
            ![request[@"service_boot_id"] isEqual:self.serviceBootID] ||
            ![request[@"broker_revision"] isEqual:self.brokerRevision] ||
            ![request[@"owner_key_id"] isEqual:self.ownerKeyID] ||
            ![request[@"connection_id"] isEqual:self.connectionID] ||
            ![request[@"session_id"] isEqual:self.sessionID] ||
            !AQBrokerOwnerContinuationString(request[@"freshness_envelope"]) ||
            !AQBrokerOwnerContinuationString(request[@"freshness_signature"]) ||
            !AQBrokerOwnerContinuationString(request[@"consent_signature"])) {
            return AQBrokerOwnerContinuationFail(error, @"OWNER_EXPORT_AUTHORITY_MISSING");
        }
    }
    NSDictionary *exportRequest = workflow.lastObject;
    if (![exportRequest[@"request_id"] isEqual:attempt[@"request_id"]] ||
        ![exportRequest[@"sequence"] isEqual:attempt[@"sequence"]] ||
        ![exportRequest[@"deadline_ns"] isEqual:attempt[@"deadline_ns"]] ||
        ![exportRequest[@"manifest_sha256"] isEqual:attempt[@"manifest_sha256"]]) {
        return AQBrokerOwnerContinuationFail(error, @"OWNER_EXPORT_ATTEMPT_BINDING_INVALID");
    }
    NSError *serializationError = nil;
    NSData *attemptData = AQCanonicalJSON(attempt, &serializationError);
    if (attemptData == nil || attemptData.length == 0) {
        if (error != NULL) *error = serializationError;
        return NO;
    }
    self.attemptSHA256 = AQBrokerOwnerContinuationSHA256(attemptData);
    self.workflow = workflow;
    return YES;
}

- (BOOL)acknowledgeJournalAttemptSHA256:(NSString *)attemptSHA256 error:(NSError **)error {
    if (self.workflow == nil || self.journalAcknowledged ||
        ![attemptSHA256 isEqual:self.attemptSHA256]) {
        return AQBrokerOwnerContinuationFail(error, @"OWNER_JOURNAL_ACK_INVALID");
    }
    self.journalAcknowledged = YES;
    return YES;
}

- (BOOL)beginDispatchOperation:(NSString *)operation
                       request:(NSDictionary *)request
                         error:(NSError **)error {
    NSArray<NSString *> *operations = @[@"admit", @"stage", @"export"];
    if (!self.journalAcknowledged || self.workflow == nil ||
        self.activeOperation != nil || self.nextOperationIndex >= operations.count ||
        ![operation isEqual:operations[self.nextOperationIndex]] ||
        ![request isEqual:self.workflow[self.nextOperationIndex + 1]]) {
        return AQBrokerOwnerContinuationFail(error, @"OWNER_EXPORT_DISPATCH_ORDER_INVALID");
    }
    self.activeOperation = operation;
    return YES;
}

- (BOOL)completeDispatchOperation:(NSString *)operation error:(NSError **)error {
    NSArray<NSString *> *operations = @[@"admit", @"stage", @"export"];
    if (self.activeOperation == nil || ![self.activeOperation isEqual:operation] ||
        self.nextOperationIndex >= operations.count) {
        return AQBrokerOwnerContinuationFail(error, @"OWNER_EXPORT_DISPATCH_COMPLETION_INVALID");
    }
    self.activeOperation = nil;
    self.nextOperationIndex++;
    self.dispatchComplete = self.nextOperationIndex == operations.count;
    return YES;
}

@end

@implementation AQBrokerSequentialSession
- (instancetype)init {
    return [self initWithClock:^uint64_t {
        return AQBrokerSystemClockNanoseconds();
    } enforceOrdering:YES];
}

- (instancetype)initWithClock:(AQBrokerMonotonicClock)clock {
    return [self initWithClock:clock enforceOrdering:YES];
}

- (instancetype)initWithClock:(AQBrokerMonotonicClock)clock
               enforceOrdering:(BOOL)enforceOrdering {
    if (clock == nil) return nil;
    if (!(self = [super init])) return nil;
    _lock = [[NSLock alloc] init];
    _clock = [clock copy];
    _reconnectGuard = [[AQBrokerReconnectGuard alloc] init];
    _enforcesOrdering = enforceOrdering;
    _nextToken = 1;
    _dispatchedRequestIDs = [NSMutableSet set];
    return self;
}

- (BOOL)beginRequest:(NSDictionary *)request
                token:(uint64_t *)token
                error:(NSError **)error {
    if (token == NULL) return AQBrokerFail(error, AQBrokerInvalidRequest);
    *token = 0;
    if (error != NULL) *error = nil;
    [_lock lock];
    BOOL success = NO;
    NSError *localError = nil;
    NSString *requestID = nil;
    NSString *operation = nil;
    NSDictionary *ownerBinding = nil;

    if (_hasActiveRequest) {
        AQBrokerFail(&localError, AQBrokerOperationInProgress);
        goto finished;
    }
    if (![request isKindOfClass:NSDictionary.class]) {
        AQBrokerFail(&localError, AQBrokerInvalidRequest);
        goto finished;
    }
    requestID = request[@"request_id"];
    operation = request[@"operation"];
    if (!AQBrokerToken(requestID) || !AQBrokerToken(operation) ||
        !AQBrokerKnownOperation(operation)) {
        AQBrokerFail(&localError, AQBrokerInvalidRequest);
        goto finished;
    }
    if ([_dispatchedRequestIDs containsObject:requestID]) {
        AQBrokerFail(&localError, AQBrokerSequenceMismatch);
        goto finished;
    }
    if (!AQBrokerRequestClaimsMatchFreshness(request, &localError)) goto finished;

    uint64_t deadline = 0;
    if (!AQBrokerRequestDeadline(request, &deadline, &localError)) goto finished;
    if (_sessionDeadline != 0 && deadline != _sessionDeadline) {
        AQBrokerFail(&localError, AQBrokerBindingMismatch);
        goto finished;
    }
    uint64_t now = _clock();
    uint64_t remaining = 0;
    if (!AQBrokerDeadlineRemaining(deadline, now, &remaining, &localError)) goto finished;

    uint64_t sequence = 0;
    if (_enforcesOrdering) {
        if (_requiresFreshAuthentication &&
            ![operation isEqual:@"readiness"] && ![operation isEqual:@"hello"]) {
            AQBrokerFail(&localError, AQBrokerFreshAuthenticationRequired);
            goto finished;
        }
        if (!_helloCompleted) {
            if (![operation isEqual:@"readiness"] && ![operation isEqual:@"hello"]) {
                AQBrokerFail(&localError, AQBrokerSessionOwnershipMismatch);
                goto finished;
            }
        } else if (![operation isEqual:@"readiness"] && ![operation isEqual:@"hello"]) {
            if (![request[@"session_id"] isEqual:_sessionID]) {
                AQBrokerFail(&localError, AQBrokerSessionOwnershipMismatch);
                goto finished;
            }
            if (![request[@"connection_id"] isEqual:_connectionID]) {
                AQBrokerFail(&localError, AQBrokerSessionOwnershipMismatch);
                goto finished;
            }
            if (!AQBrokerRequestSequence(request, &sequence, &localError)) goto finished;
            if (sequence != _nextSequence) {
                AQBrokerFail(&localError, AQBrokerSequenceMismatch);
                goto finished;
            }
        }
        if ([operation isEqual:@"hello"]) {
            if (_helloCompleted && !_requiresFreshAuthentication) {
                AQBrokerFail(&localError, AQBrokerSessionOwnershipMismatch);
                goto finished;
            }
            if (!AQBrokerInteger(request[@"sequence"], &sequence) || sequence == 0) {
                AQBrokerFail(&localError, AQBrokerSequenceMismatch);
                goto finished;
            }
        }
        if (![operation isEqual:@"readiness"] &&
            !AQBrokerOwnerBindingForRequest(request, &ownerBinding, &localError)) {
            goto finished;
        }
        if (_ownerBinding != nil && ownerBinding != nil &&
            !AQBrokerBindingsMatch(_ownerBinding, ownerBinding)) {
            AQBrokerFail(&localError, AQBrokerSessionOwnershipMismatch);
            goto finished;
        }
    }

    BOOL mutation = !AQBrokerInspectionOperation(operation);
    BOOL guardAccepted = mutation ? [_reconnectGuard dispatchMutation] :
                                   [_reconnectGuard dispatchInspection];
    if (!guardAccepted) {
        AQBrokerErrorCode code = mutation && _reconnectGuard.uncertainEffect
            ? AQBrokerUncertainEffect : AQBrokerReconnectRequired;
        AQBrokerFail(&localError, code);
        goto finished;
    }

    uint64_t acceptedToken = _nextToken++;
    if (acceptedToken == 0) {
        [_reconnectGuard operationCompleted];
        AQBrokerFail(&localError, AQBrokerInvalidRequest);
        goto finished;
    }
    _hasActiveRequest = YES;
    _activeMutation = mutation;
    _activeResponseAccepted = NO;
    _activeToken = acceptedToken;
    _activeSequence = sequence;
    _activeDeadline = deadline;
    _activeRequestID = [requestID copy];
    _activeRequest = [request copy];
    _activeResponse = nil;
    if ([operation isEqual:@"hello"] && _sessionDeadline == 0) _sessionDeadline = deadline;
    [_dispatchedRequestIDs addObject:requestID];
    *token = acceptedToken;
    success = YES;

finished:
    if (!success && _reconnectGuard.operationInFlight) {
        [_reconnectGuard operationCompleted];
    }
    [_lock unlock];
    if (error != NULL) *error = localError;
    return success;
}

- (BOOL)acceptResponseForToken:(uint64_t)token
                      response:(NSDictionary *)response
                         error:(NSError **)error {
    if (error != NULL) *error = nil;
    [_lock lock];
    BOOL success = NO;
    NSError *localError = nil;
    NSString *status = nil;
    NSDictionary *result = nil;
    if (!_hasActiveRequest || token == 0 || token != _activeToken) {
        AQBrokerFail(&localError, AQBrokerLateReply);
        goto finished;
    }
    if (_activeResponseAccepted) {
        AQBrokerFail(&localError, AQBrokerLateReply);
        goto finished;
    }
    uint64_t remaining = 0;
    if (!AQBrokerDeadlineRemaining(_activeDeadline, _clock(), &remaining, &localError)) {
        [self finishUnknownLocked];
        _requiresFreshAuthentication = YES;
        _outcomeUnknown = YES;
        goto finished;
    }
    if (![response isKindOfClass:NSDictionary.class] ||
        ![response[@"request_id"] isEqual:_activeRequestID]) {
        [self finishUnknownLocked];
        _requiresFreshAuthentication = YES;
        _outcomeUnknown = YES;
        AQBrokerFail(&localError, AQBrokerInvalidRequest);
        goto finished;
    }
    status = response[@"status"];
    if (![status isKindOfClass:NSString.class] ||
        (![status isEqual:@"OK"] && ![status isEqual:@"BLOCKED"])) {
        [self finishUnknownLocked];
        _requiresFreshAuthentication = YES;
        _outcomeUnknown = YES;
        AQBrokerFail(&localError, AQBrokerInvalidRequest);
        goto finished;
    }
    if ([_activeRequest[@"operation"] isEqual:@"hello"] && [status isEqual:@"OK"]) {
        result = response[@"result"];
        if (![result isKindOfClass:NSDictionary.class] ||
            !AQBrokerToken(result[@"session_id"]) ||
            !AQBrokerToken(result[@"connection_id"])) {
            [self finishUnknownLocked];
            _requiresFreshAuthentication = YES;
            _outcomeUnknown = YES;
            AQBrokerFail(&localError, AQBrokerInvalidRequest);
            goto finished;
        }
    }
    [_reconnectGuard connectionOpened];
    _activeResponse = [response copy];
    _activeResponseAccepted = YES;
    success = YES;

finished:
    [_lock unlock];
    if (error != NULL) *error = localError;
    return success;
}

- (BOOL)completeRequestForToken:(uint64_t)token
                  outcomeKnown:(BOOL)known
                         error:(NSError **)error {
    if (error != NULL) *error = nil;
    [_lock lock];
    BOOL success = NO;
    NSError *localError = nil;
    NSString *operation = nil;
    NSString *status = nil;
    NSDictionary *result = nil;
    NSDictionary *resultingBinding = nil;
    if (!_hasActiveRequest || token == 0 || token != _activeToken) {
        AQBrokerFail(&localError, AQBrokerLateReply);
        goto finished;
    }
    if (!known) {
        [self finishUnknownLocked];
        _requiresFreshAuthentication = YES;
        _outcomeUnknown = YES;
        success = YES;
        goto finished;
    }
    if (!_activeResponseAccepted) {
        AQBrokerFail(&localError, AQBrokerInvalidRequest);
        goto finished;
    }
    uint64_t remaining = 0;
    if (!AQBrokerDeadlineRemaining(_activeDeadline, _clock(), &remaining, &localError)) {
        [self finishUnknownLocked];
        _requiresFreshAuthentication = YES;
        _outcomeUnknown = YES;
        goto finished;
    }

    operation = _activeRequest[@"operation"];
    status = _activeResponse[@"status"];
    if (_enforcesOrdering && [status isEqual:@"OK"]) {
        if ([operation isEqual:@"hello"]) {
            result = _activeResponse[@"result"];
            _sessionID = [result[@"session_id"] copy];
            _connectionID = [result[@"connection_id"] copy];
            if (_ownerBinding == nil) {
                AQBrokerOwnerBindingForRequest(_activeRequest, &resultingBinding, NULL);
                _ownerBinding = [resultingBinding copy];
            }
            _helloCompleted = YES;
            _nextSequence = 1;
            _requiresFreshAuthentication = NO;
        } else if (![operation isEqual:@"readiness"] &&
                   _activeSequence != 0 && _activeSequence == _nextSequence) {
            _nextSequence++;
        }
    }
    if ([status isEqual:@"BLOCKED"]) _requiresFreshAuthentication = YES;
    [_reconnectGuard operationCompleted];
    [self clearActiveLocked];
    success = YES;

finished:
    [_lock unlock];
    if (error != NULL) *error = localError;
    return success;
}

- (void)connectionLostWithOutcomeKnown:(BOOL)known {
    [_lock lock];
    if (_hasActiveRequest) [self finishUnknownLocked];
    [_reconnectGuard connectionLostWithOutcomeKnown:known];
    _requiresFreshAuthentication = YES;
    if (!known) _outcomeUnknown = YES;
    [_lock unlock];
}

- (BOOL)remainingNanosecondsForToken:(uint64_t)token
                          remaining:(uint64_t *)remaining
                              error:(NSError **)error {
    if (remaining == NULL) return AQBrokerFail(error, AQBrokerInvalidRequest);
    [_lock lock];
    BOOL success = NO;
    NSError *localError = nil;
    if (!_hasActiveRequest || token == 0 || token != _activeToken) {
        AQBrokerFail(&localError, AQBrokerLateReply);
    } else {
        success = AQBrokerDeadlineRemaining(_activeDeadline, _clock(), remaining, &localError);
    }
    [_lock unlock];
    if (error != NULL) *error = localError;
    return success;
}

- (BOOL)deadlineNanosecondsForToken:(uint64_t)token
                           deadline:(uint64_t *)deadline
                              error:(NSError **)error {
    if (deadline == NULL) return AQBrokerFail(error, AQBrokerInvalidRequest);
    [_lock lock];
    BOOL success = NO;
    NSError *localError = nil;
    if (!_hasActiveRequest || token == 0 || token != _activeToken) {
        AQBrokerFail(&localError, AQBrokerLateReply);
    } else {
        *deadline = _activeDeadline;
        success = YES;
    }
    [_lock unlock];
    if (error != NULL) *error = localError;
    return success;
}

- (int)pollTimeoutMillisecondsForToken:(uint64_t)token error:(NSError **)error {
    uint64_t remaining = 0;
    if (![self remainingNanosecondsForToken:token remaining:&remaining error:error]) return -1;
    uint64_t milliseconds = remaining / NSEC_PER_MSEC;
    if (remaining % NSEC_PER_MSEC != 0) milliseconds++;
    return milliseconds > INT_MAX ? INT_MAX : (int)milliseconds;
}

- (void)finishUnknownLocked {
    [_reconnectGuard connectionLostWithOutcomeKnown:NO];
    [self clearActiveLocked];
}

- (void)clearActiveLocked {
    _hasActiveRequest = NO;
    _activeMutation = NO;
    _activeResponseAccepted = NO;
    _activeToken = 0;
    _activeSequence = 0;
    _activeDeadline = 0;
    _activeRequestID = nil;
    _activeRequest = nil;
    _activeResponse = nil;
}

- (BOOL)connectionOpened {
    [_lock lock];
    BOOL accepted = [_reconnectGuard connectionOpened];
    [_lock unlock];
    return accepted;
}

- (BOOL)enforcesOrdering { return _enforcesOrdering; }

- (BOOL)outcomeUnknown {
    [_lock lock];
    BOOL value = _outcomeUnknown;
    [_lock unlock];
    return value;
}

- (BOOL)requiresFreshAuthentication {
    [_lock lock];
    BOOL value = _requiresFreshAuthentication;
    [_lock unlock];
    return value;
}

- (nullable NSString *)sessionID {
    [_lock lock];
    NSString *value = [_sessionID copy];
    [_lock unlock];
    return value;
}

- (nullable NSString *)connectionID {
    [_lock lock];
    NSString *value = [_connectionID copy];
    [_lock unlock];
    return value;
}

- (BOOL)hasActiveRequest {
    [_lock lock];
    BOOL value = _hasActiveRequest;
    [_lock unlock];
    return value;
}

- (AQBrokerReconnectGuard *)reconnectGuard { return _reconnectGuard; }
@end
