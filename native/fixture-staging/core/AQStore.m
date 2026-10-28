#import "AQStore.h"
#import "AQJSON.h"

#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <mach/mach_time.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/acl.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *const AQStoreErrorDomain = @"AQStoreError";
const NSUInteger AQStoreIOChunkSize = 1024 * 1024;
const NSUInteger AQStoreMaximumExportMetadataHeaderBytes = 64 * 1024;
NSString *const AQStoreProductionRoot = @"/private/var/db/argus-qualification/staging";

static NSString *const AQRecordPrefix = @".aq-record-";
static NSString *const AQFramePrefix = @"AQSNAP1\n";
static NSString *const AQFrameSuffix = @"AQEND1\r\n";
static const NSUInteger AQMaximumRecordBytes = 4 * 1024 * 1024;
static const NSUInteger AQMaximumPathBytes = 4096;
static const NSUInteger AQMaximumManifestRecords = 128;

BOOL AQStoreAddBytes(uint64_t left, uint64_t right, uint64_t *result) {
    if (result == NULL || UINT64_MAX - left < right) return NO;
    *result = left + right;
    return YES;
}

BOOL AQStoreCapacityAllows(uint64_t available, uint64_t remaining,
                           uint64_t hostReserve, uint64_t destinationReserve) {
    uint64_t reserve = hostReserve > destinationReserve ? hostReserve : destinationReserve;
    uint64_t required = 0;
    return AQStoreAddBytes(remaining, reserve, &required) && available >= required;
}

static NSError *AQStoreFailure(AQStoreErrorCode code) {
    NSString *description;
    switch (code) {
        case AQStoreUnauthorizedRoot: description = @"The protected staging root is not authorized."; break;
        case AQStoreInvalidState: description = @"The requested store transition is not valid."; break;
        case AQStoreSourceDenied: description = @"A source descriptor does not satisfy the immutable-input contract."; break;
        case AQStoreCapacityDenied: description = @"Insufficient storage is available after required reserves."; break;
        case AQStoreIntegrityFailure: description = @"Snapshot bytes did not match their verified identity."; break;
        case AQStoreDeadlineExpired: description = @"The authenticated operation deadline has expired."; break;
        case AQStoreRevoked: description = @"The session has been revoked."; break;
        case AQStoreJournalCorrupt: description = @"The durable store journal cannot be trusted."; break;
        case AQStoreBusy: description = @"The session already has an operation in progress."; break;
        case AQStoreIOFailure: description = @"A protected store operation failed."; break;
        case AQStoreMetadataHeaderTooLarge: description = @"The canonical export metadata header exceeds its size limit."; break;
        case AQStoreInvalidInput:
        default: description = @"The supplied store input is invalid."; break;
    }
    return [NSError errorWithDomain:AQStoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL AQStoreFail(NSError **error, AQStoreErrorCode code) {
    if (error) *error = AQStoreFailure(code);
    return NO;
}

static BOOL AQExactKeys(NSDictionary *object, NSSet<NSString *> *required,
                        NSSet<NSString *> *optional) {
    if (![object isKindOfClass:[NSDictionary class]]) return NO;
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:object.allKeys];
    NSMutableSet<NSString *> *allowed = [required mutableCopy];
    if (allowed == nil) return NO;
    [allowed unionSet:optional];
    return [keys isSubsetOfSet:allowed] && [required isSubsetOfSet:keys];
}

static BOOL AQAddUnique(NSMutableSet *set, id object) {
    if ([set containsObject:object]) return NO;
    [set addObject:object];
    return YES;
}

static BOOL AQIntegerValue(id value, uint64_t minimum, uint64_t maximum, uint64_t *result) {
    if (![value isKindOfClass:[NSNumber class]] || result == NULL) return NO;
    CFTypeRef raw = (__bridge CFTypeRef)value;
    if (CFGetTypeID(raw) == CFBooleanGetTypeID() || CFNumberIsFloatType((CFNumberRef)raw)) return NO;
    long long signedValue = [value longLongValue];
    if (signedValue < 0) return NO;
    uint64_t converted = (uint64_t)signedValue;
    if (converted < minimum || converted > maximum) return NO;
    *result = converted;
    return YES;
}

static BOOL AQBooleanValue(id value, BOOL *result) {
    if (![value isKindOfClass:[NSNumber class]] || result == NULL) return NO;
    CFTypeRef raw = (__bridge CFTypeRef)value;
    if (CFGetTypeID(raw) != CFBooleanGetTypeID()) return NO;
    *result = [value boolValue];
    return YES;
}

static BOOL AQDigestText(id value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *text = value;
    if (text.length != 64) return NO;
    for (NSUInteger index = 0; index < text.length; ++index) {
        unichar character = [text characterAtIndex:index];
        if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'))) return NO;
    }
    return YES;
}

static BOOL AQASCIIToken(id value, NSUInteger maximumLength) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *text = value;
    if (text.length == 0 || text.length > maximumLength) return NO;
    for (NSUInteger index = 0; index < text.length; ++index) {
        unichar character = [text characterAtIndex:index];
        if (character < 0x21 || character > 0x7e) return NO;
    }
    return YES;
}

static BOOL AQDescriptionString(id value, NSUInteger maximumLength) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *text = value;
    NSCharacterSet *trimmed = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    if (text.length == 0 || text.length > maximumLength ||
        ![text isEqualToString:[text stringByTrimmingCharactersInSet:trimmed]] ||
        [text rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) return NO;
    return YES;
}

static BOOL AQIdentifier(id value) {
    if (!AQDescriptionString(value, 256)) return NO;
    NSString *text = value;
    return ![text isEqualToString:@"."] && ![text isEqualToString:@".."] &&
        [text rangeOfString:@"/"].location == NSNotFound &&
        [text rangeOfString:@"\\"].location == NSNotFound &&
        [text rangeOfString:@":"].location == NSNotFound;
}

static NSString *AQCasefold(NSString *value) {
    NSString *normalized = [value precomposedStringWithCanonicalMapping];
    return [normalized lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
}

static BOOL AQRelativePath(id value, NSArray<NSString *> **componentsOut) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *path = value;
    if (path.length == 0 || path.length > AQMaximumPathBytes || [path hasPrefix:@"/"] || [path hasSuffix:@"/"] ||
        [path rangeOfString:@"\\"].location != NSNotFound || [path rangeOfString:@":"].location != NSNotFound ||
        [path rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) return NO;
    NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
    for (NSString *component in components) {
        if (component.length == 0 || [component isEqualToString:@"."] || [component isEqualToString:@".."] ||
            [component lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > NAME_MAX) return NO;
    }
    if (componentsOut) *componentsOut = components;
    return YES;
}

static BOOL AQWriteAll(int fd, const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t written = write(fd, cursor, length);
        if (written < 0) {
            if (errno == EINTR) continue;
            return NO;
        }
        if (written == 0) return NO;
        cursor += (size_t)written;
        length -= (size_t)written;
    }
    return YES;
}

static BOOL AQPWriteAll(int fd, const void *bytes, size_t length, off_t offset) {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t written = pwrite(fd, cursor, length, offset);
        if (written < 0) {
            if (errno == EINTR) continue;
            return NO;
        }
        if (written == 0) return NO;
        cursor += (size_t)written;
        length -= (size_t)written;
        offset += (off_t)written;
    }
    return YES;
}

static BOOL AQReadExact(int fd, void *bytes, size_t length, off_t offset) {
    uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t count = pread(fd, cursor, length, offset);
        if (count < 0) {
            if (errno == EINTR) continue;
            return NO;
        }
        if (count == 0) return NO;
        cursor += (size_t)count;
        length -= (size_t)count;
        offset += (off_t)count;
    }
    return YES;
}

static BOOL AQFullSync(int fd, BOOL fileData) {
    if (fsync(fd) != 0) return NO;
    if (!fileData) return YES;
    return fcntl(fd, F_FULLFSYNC) == 0;
}

static BOOL AQDirectorySync(int fd) {
    return AQFullSync(fd, NO);
}

static BOOL AQAvailableBytes(int fd, uint64_t *result) {
    struct statfs status;
    if (fstatfs(fd, &status) != 0 || status.f_bsize <= 0 || status.f_bavail < 0 || result == NULL) return NO;
    uint64_t blocks = (uint64_t)status.f_bavail;
    uint64_t size = (uint64_t)status.f_bsize;
    if (blocks != 0 && size > UINT64_MAX / blocks) return NO;
    *result = blocks * size;
    return YES;
}

@interface AQStoreMember : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic) uint64_t size;
@property(nonatomic, copy) NSString *sha256;
- (NSDictionary *)recordRepresentation;
@end

@implementation AQStoreMember
- (NSDictionary *)recordRepresentation {
    return @{@"path": self.path, @"size": @(self.size), @"sha256": self.sha256};
}
@end

@interface AQStoreSession : NSObject
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *grantID;
@property(nonatomic, copy) NSString *connectionID;
@property(nonatomic) uint64_t epoch;
@property(nonatomic, copy) NSString *manifestSHA256;
@property(nonatomic, copy) NSString *planSHA256;
@property(nonatomic, copy) NSString *rulesSHA256;
@property(nonatomic) uint64_t deadlineTicks;
@property(nonatomic) uint64_t hostReserveBytes;
@property(nonatomic) uint64_t destinationReserveBytes;
@property(nonatomic, copy) NSArray<NSString *> *operations;
@property(nonatomic) uint64_t sequence;
@property(nonatomic) uint64_t generation;
@property(nonatomic, copy) NSString *state;
@property(nonatomic) BOOL revoked;
@property(nonatomic, copy) NSString *effectState;
@property(nonatomic, copy) NSString *pendingName;
@property(nonatomic, copy) NSString *snapshotName;
@property(nonatomic, copy) NSArray<AQStoreMember *> *members;
@property(nonatomic, copy) NSArray<NSString *> *attemptedEntries;
@property(nonatomic, copy) NSString *requestSHA256;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, strong) NSMutableSet<NSString *> *acceptedDigests;
- (NSDictionary *)recordRepresentation;
@end

@implementation AQStoreSession
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _operations = @[];
    _members = @[];
    _attemptedEntries = @[];
    _requestSHA256 = @"";
    _lastError = @"";
    _effectState = @"none";
    _pendingName = @"";
    _snapshotName = @"";
    _state = @"admitted";
    _acceptedDigests = [NSMutableSet set];
    return self;
}

- (NSDictionary *)recordRepresentation {
    NSMutableArray *members = [NSMutableArray arrayWithCapacity:self.members.count];
    for (AQStoreMember *member in self.members) [members addObject:member.recordRepresentation];
    return @{
        @"session_id": self.sessionID,
        @"grant_id": self.grantID,
        @"connection_id": self.connectionID,
        @"epoch": @(self.epoch),
        @"manifest_sha256": self.manifestSHA256,
        @"plan_sha256": self.planSHA256,
        @"rules_sha256": self.rulesSHA256,
        @"deadline_ticks": @(self.deadlineTicks),
        @"host_reserve_bytes": @(self.hostReserveBytes),
        @"destination_reserve_bytes": @(self.destinationReserveBytes),
        @"operations": self.operations,
        @"sequence": @(self.sequence),
        @"generation": @(self.generation),
        @"state": self.state,
        @"revoked": @(self.revoked),
        @"effect_state": self.effectState,
        @"pending_name": self.pendingName,
        @"snapshot_name": self.snapshotName,
        @"members": members,
        @"attempted_entries": self.attemptedEntries,
        @"request_sha256": self.requestSHA256,
        @"last_error": self.lastError,
    };
}
@end

static NSArray<AQStoreMember *> *AQMembersFromArray(id value) {
    if (![value isKindOfClass:[NSArray class]] || [value count] == 0) return nil;
    NSSet *required = [NSSet setWithArray:@[@"path", @"size", @"sha256"]];
    NSMutableArray<AQStoreMember *> *members = [NSMutableArray arrayWithCapacity:[value count]];
    for (id item in value) {
        if (!AQExactKeys(item, required, [NSSet set])) return nil;
        uint64_t size = 0;
        if (!AQRelativePath(item[@"path"], NULL) || !AQDigestText(item[@"sha256"]) ||
            !AQIntegerValue(item[@"size"], 0, (uint64_t)INT64_MAX, &size)) return nil;
        AQStoreMember *member = [AQStoreMember new];
        member.path = item[@"path"];
        member.size = size;
        member.sha256 = item[@"sha256"];
        [members addObject:member];
    }
    return [members copy];
}

static AQStoreSession *AQSessionFromRecord(NSDictionary *object) {
    NSSet *required = [NSSet setWithArray:@[
        @"session_id", @"grant_id", @"connection_id", @"epoch", @"manifest_sha256",
        @"plan_sha256", @"rules_sha256", @"deadline_ticks", @"host_reserve_bytes",
        @"destination_reserve_bytes", @"operations", @"sequence", @"generation", @"state",
        @"revoked", @"effect_state", @"pending_name", @"snapshot_name", @"members",
        @"attempted_entries", @"request_sha256", @"last_error"
    ]];
    if (!AQExactKeys(object, required, [NSSet set])) return nil;
    if (!AQASCIIToken(object[@"session_id"], 256) || !AQASCIIToken(object[@"grant_id"], 256) ||
        !AQASCIIToken(object[@"connection_id"], 256) || !AQDigestText(object[@"manifest_sha256"]) ||
        !AQDigestText(object[@"plan_sha256"]) || !AQDigestText(object[@"rules_sha256"])) return nil;
    uint64_t epoch = 0, deadline = 0, hostReserve = 0, destinationReserve = 0, sequence = 0, generation = 0;
    if (!AQIntegerValue(object[@"epoch"], 0, (uint64_t)INT64_MAX, &epoch) ||
        !AQIntegerValue(object[@"deadline_ticks"], 1, (uint64_t)INT64_MAX, &deadline) ||
        !AQIntegerValue(object[@"host_reserve_bytes"], 0, (uint64_t)INT64_MAX, &hostReserve) ||
        !AQIntegerValue(object[@"destination_reserve_bytes"], 0, (uint64_t)INT64_MAX, &destinationReserve) ||
        !AQIntegerValue(object[@"sequence"], 0, (uint64_t)INT64_MAX, &sequence) ||
        !AQIntegerValue(object[@"generation"], 0, (uint64_t)INT64_MAX, &generation)) return nil;
    id operationValue = object[@"operations"];
    if (![operationValue isKindOfClass:[NSArray class]] || [operationValue count] == 0) return nil;
    NSMutableSet *operationSet = [NSMutableSet set];
    NSSet *allowedOperations = [NSSet setWithArray:@[@"stage", @"eligibility", @"export", @"cleanup"]];
    for (id operation in operationValue) {
        if (![allowedOperations containsObject:operation] || !AQAddUnique(operationSet, operation)) return nil;
    }
    NSArray<AQStoreMember *> *members = AQMembersFromArray(object[@"members"]);
    id attemptedValue = object[@"attempted_entries"];
    if (members == nil || ![attemptedValue isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSString *> *attempted = [NSMutableArray arrayWithCapacity:[attemptedValue count]];
    NSMutableSet *attemptedSet = [NSMutableSet set];
    for (id entry in attemptedValue) {
        if (![entry isKindOfClass:[NSString class]] || ((NSString *)entry).length == 0 ||
            ![(NSString *)entry isEqualToString:[(NSString *)entry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]] ||
            !AQAddUnique(attemptedSet, entry)) return nil;
        [attempted addObject:entry];
    }
    BOOL revoked = NO;
    if (!AQBooleanValue(object[@"revoked"], &revoked)) return nil;
    NSString *state = object[@"state"];
    NSSet *states = [NSSet setWithArray:@[@"admitted", @"eligibility", @"export", @"cleanup",
                                           @"eligible", @"blocked_retained", @"revoked", @"cleaned"]];
    if (![states containsObject:state] || ![object[@"effect_state"] isKindOfClass:[NSString class]] ||
        ![object[@"pending_name"] isKindOfClass:[NSString class]] ||
        ![object[@"snapshot_name"] isKindOfClass:[NSString class]] ||
        ![object[@"last_error"] isKindOfClass:[NSString class]]) return nil;
    NSString *requestDigest = object[@"request_sha256"];
    if (![requestDigest isKindOfClass:[NSString class]] ||
        (requestDigest.length != 0 && !AQDigestText(requestDigest))) return nil;
    AQStoreSession *session = [AQStoreSession new];
    session.sessionID = object[@"session_id"];
    session.grantID = object[@"grant_id"];
    session.connectionID = object[@"connection_id"];
    session.epoch = epoch;
    session.manifestSHA256 = object[@"manifest_sha256"];
    session.planSHA256 = object[@"plan_sha256"];
    session.rulesSHA256 = object[@"rules_sha256"];
    session.deadlineTicks = deadline;
    session.hostReserveBytes = hostReserve;
    session.destinationReserveBytes = destinationReserve;
    session.operations = [operationValue copy];
    session.sequence = sequence;
    session.generation = generation;
    session.state = state;
    session.revoked = revoked;
    session.effectState = object[@"effect_state"];
    session.pendingName = object[@"pending_name"];
    session.snapshotName = object[@"snapshot_name"];
    session.members = members;
    session.attemptedEntries = [attempted copy];
    session.requestSHA256 = requestDigest;
    session.lastError = object[@"last_error"];
    for (NSString *entry in attempted) [session.acceptedDigests addObject:[@"cleanup:" stringByAppendingString:entry]];
    return session;
}

static BOOL AQStoreReplayEventTransitionValid(NSString *event, NSString *previousEvent,
                                               AQStoreSession *previous,
                                               AQStoreSession *session) {
    if (previous == nil) {
        return [event isEqual:@"admitted"] && session.sequence == 0 &&
            session.generation == 0 && [session.state isEqual:@"admitted"] &&
            [session.effectState isEqual:@"none"] && !session.revoked &&
            session.requestSHA256.length == 0 && session.pendingName.length == 0 &&
            session.snapshotName.length == 0 &&
            session.attemptedEntries.count == 0;
    }

    if (![session.operations isEqualToArray:previous.operations] ||
        session.hostReserveBytes != previous.hostReserveBytes ||
        session.destinationReserveBytes != previous.destinationReserveBytes) return NO;

    BOOL dispatch = [event isEqual:@"dispatch"];
    if (dispatch) {
        BOOL priorOperationCompleted =
            [previousEvent isEqual:@"admitted"] ||
            [previousEvent isEqual:@"stage_eligible"] ||
            [previousEvent isEqual:@"eligibility_verified"] ||
            [previousEvent isEqual:@"export_completed"];
        return priorOperationCompleted && previous.sequence < UINT64_MAX &&
            session.sequence == previous.sequence + 1 &&
            session.generation == previous.generation &&
            !previous.revoked && !session.revoked &&
            ![session.requestSHA256 isEqual:previous.requestSHA256] &&
            [session.state isEqual:previous.state] &&
            [session.effectState isEqual:previous.effectState] &&
            [session.pendingName isEqual:previous.pendingName] &&
            [session.snapshotName isEqual:previous.snapshotName] &&
            [session.recordRepresentation[@"members"]
                isEqual:previous.recordRepresentation[@"members"]] &&
            [session.attemptedEntries isEqual:previous.attemptedEntries] &&
            [session.lastError isEqual:previous.lastError];
    }

    if (session.sequence != previous.sequence ||
        ![session.requestSHA256 isEqual:previous.requestSHA256]) return NO;
    BOOL stageEligible = [event isEqual:@"stage_eligible"];
    if (stageEligible) {
        if (previous.generation == UINT64_MAX ||
            session.generation != previous.generation + 1) return NO;
    } else if (session.generation != previous.generation) {
        return NO;
    }

    if ([event isEqual:@"stage_intent"]) {
        return [previousEvent isEqual:@"dispatch"] && !previous.revoked &&
            [previous.state isEqual:@"admitted"] &&
            [session.state isEqual:previous.state] &&
            [session.effectState isEqual:previous.effectState] &&
            previous.pendingName.length == 0 && previous.snapshotName.length == 0 &&
            session.pendingName.length > 0 && session.snapshotName.length > 0 &&
            [session.recordRepresentation[@"members"]
                isEqual:previous.recordRepresentation[@"members"]] &&
            [session.attemptedEntries isEqual:previous.attemptedEntries] &&
            !session.revoked;
    }
    if ([event isEqual:@"stage_eligible"]) {
        return [previousEvent isEqual:@"stage_intent"] && !session.revoked &&
            [session.state isEqual:@"eligible"] &&
            [session.effectState isEqual:@"none"] && session.pendingName.length == 0 &&
            [session.snapshotName isEqual:previous.snapshotName] &&
            [session.attemptedEntries isEqual:previous.attemptedEntries];
    }
    if ([event isEqual:@"stage_blocked"]) {
        return [previousEvent isEqual:@"stage_intent"] && !session.revoked &&
            [session.state isEqual:@"blocked_retained"] &&
            [session.effectState isEqual:@"retained"];
    }
    if ([event isEqual:@"eligibility_verified"]) {
        return [previousEvent isEqual:@"dispatch"] && !session.revoked &&
            [session.state isEqual:@"eligible"] && [session.effectState isEqual:@"none"] &&
            [session.recordRepresentation[@"members"]
                isEqual:previous.recordRepresentation[@"members"]];
    }
    if ([event isEqual:@"eligibility_failed"] || [event isEqual:@"export_failed"] ||
        [event isEqual:@"cleanup_failed"]) {
        BOOL failurePredecessor = [previousEvent isEqual:@"dispatch"] ||
            [previousEvent isEqual:@"stage_intent"] ||
            [previousEvent isEqual:@"cleanup_attempt"] ||
            [previousEvent isEqual:@"cleanup_member_done"];
        return failurePredecessor && !session.revoked &&
            [session.state isEqual:@"blocked_retained"] &&
            [session.effectState isEqual:@"retained"];
    }
    if ([event isEqual:@"export_started"]) {
        return [previousEvent isEqual:@"dispatch"] && !session.revoked &&
            [session.state isEqual:@"export"] &&
            [session.effectState isEqual:@"pending"];
    }
    if ([event isEqual:@"export_completed"]) {
        return ([previousEvent isEqual:@"dispatch"] ||
                [previousEvent isEqual:@"export_started"]) && !session.revoked &&
            [session.state isEqual:@"eligible"] && [session.effectState isEqual:@"none"];
    }
    if ([event isEqual:@"cleanup_attempt"]) {
        BOOL cleanupPredecessor = [previousEvent isEqual:@"dispatch"] ||
            [previousEvent isEqual:@"cleanup_member_done"];
        return cleanupPredecessor && !session.revoked &&
            [session.state isEqual:@"eligible"] &&
            [session.effectState isEqual:@"pending"] &&
            session.attemptedEntries.count > previous.attemptedEntries.count;
    }
    if ([event isEqual:@"cleanup_member_done"]) {
        return ([previousEvent isEqual:@"cleanup_attempt"] ||
                [previousEvent isEqual:@"cleanup_member_done"]) && !session.revoked &&
            [session.state isEqual:@"eligible"] &&
            [session.effectState isEqual:@"cleanup_progress"] &&
            [session.attemptedEntries isEqual:previous.attemptedEntries];
    }
    if ([event isEqual:@"cleanup_complete"]) {
        return ([previousEvent isEqual:@"cleanup_attempt"] ||
                [previousEvent isEqual:@"cleanup_member_done"]) && !session.revoked &&
            [session.state isEqual:@"cleaned"] && [session.effectState isEqual:@"none"] &&
            [session.attemptedEntries isEqual:previous.attemptedEntries];
    }
    if ([event isEqual:@"revoked"]) {
        return !previous.revoked && session.revoked &&
            [session.state isEqual:@"revoked"] &&
            [session.effectState isEqual:@"retained"];
    }
    return NO;
}

static BOOL AQPathsConflict(NSMutableSet<NSString *> *files, NSMutableSet<NSString *> *directories,
                            NSString *path) {
    NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
    NSMutableString *prefix = [NSMutableString string];
    for (NSUInteger index = 0; index < components.count; ++index) {
        if (prefix.length > 0) [prefix appendString:@"/"];
        [prefix appendString:components[index]];
        NSString *key = AQCasefold(prefix);
        BOOL final = index + 1 == components.count;
        if ((final && [directories containsObject:key]) || (!final && [files containsObject:key])) return YES;
        if (!final) [directories addObject:key];
    }
    NSString *key = AQCasefold(path);
    if ([files containsObject:key]) return YES;
    [files addObject:key];
    return NO;
}

static NSArray<AQStoreMember *> *AQMembersFromManifest(NSDictionary *manifest, NSError **error) {
    NSSet *required = [NSSet setWithArray:@[
        @"schema_version", @"source_authority", @"plan_sha256", @"rules_sha256", @"coverage_mode",
        @"selected_fixture_ids", @"fixtures"
    ]];
    if (!AQExactKeys(manifest, required, [NSSet set])) return AQStoreFail(error, AQStoreInvalidInput), nil;
    uint64_t schemaVersion = 0;
    if (!AQIntegerValue(manifest[@"schema_version"], 2, 2, &schemaVersion) ||
        ![manifest[@"source_authority"] isEqual:@"service_protected_snapshot_v1"] ||
        !AQDigestText(manifest[@"plan_sha256"]) || !AQDigestText(manifest[@"rules_sha256"]) ||
        !([manifest[@"coverage_mode"] isEqual:@"mandatory_full_plan"] ||
          [manifest[@"coverage_mode"] isEqual:@"authorized_partial_plan"])) {
        return AQStoreFail(error, AQStoreInvalidInput), nil;
    }
    NSArray *selected = manifest[@"selected_fixture_ids"];
    NSArray *fixtures = manifest[@"fixtures"];
    if (![selected isKindOfClass:[NSArray class]] || ![fixtures isKindOfClass:[NSArray class]] ||
        selected.count == 0 || fixtures.count != selected.count || fixtures.count > AQMaximumManifestRecords) {
        return AQStoreFail(error, AQStoreInvalidInput), nil;
    }
    NSMutableSet<NSString *> *selectedSet = [NSMutableSet set];
    for (id fixtureID in selected) {
        if (!AQIdentifier(fixtureID) || !AQAddUnique(selectedSet, AQCasefold(fixtureID))) {
            return AQStoreFail(error, AQStoreInvalidInput), nil;
        }
    }
    NSMutableSet<NSString *> *fixtureKeys = [NSMutableSet set];
    NSMutableSet<NSString *> *files = [NSMutableSet set];
    NSMutableSet<NSString *> *directories = [NSMutableSet set];
    NSMutableArray<AQStoreMember *> *allMembers = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *groupOrders = [NSMutableDictionary dictionary];
    NSSet *fixtureRequired = [NSSet setWithArray:@[
        @"fixture_id", @"platform", @"representation", @"group_id", @"identity", @"order",
        @"entrypoint", @"files", @"companions", @"identity_evidence", @"oracle_pin"
    ]];
    NSSet *fixtureOptional = [NSSet setWithObject:@"facts"];
    NSSet *fileKeys = [NSSet setWithArray:@[@"path", @"role", @"size", @"sha256"]];
    NSSet *companionKeys = [NSSet setWithArray:@[@"source", @"target"]];
    NSSet *oracleKeys = [NSSet setWithArray:@[@"schema_version", @"oracle_ref", @"revision", @"sha256"]];
    for (NSUInteger fixtureIndex = 0; fixtureIndex < fixtures.count; ++fixtureIndex) {
        id rawFixture = fixtures[fixtureIndex];
        if (!AQExactKeys(rawFixture, fixtureRequired, fixtureOptional)) return AQStoreFail(error, AQStoreInvalidInput), nil;
        NSDictionary *fixture = rawFixture;
        NSString *fixtureID = fixture[@"fixture_id"];
        if (!AQIdentifier(fixtureID) || ![fixtureID isEqual:selected[fixtureIndex]] ||
            !AQAddUnique(fixtureKeys, AQCasefold(fixtureID)) ||
            !AQDescriptionString(fixture[@"platform"], 256) || !AQDescriptionString(fixture[@"representation"], 256) ||
            !AQDescriptionString(fixture[@"group_id"], 256) || !AQDescriptionString(fixture[@"identity"], 512)) {
            return AQStoreFail(error, AQStoreInvalidInput), nil;
        }
        uint64_t order = 0;
        if (!AQIntegerValue(fixture[@"order"], 0, (uint64_t)INT64_MAX, &order)) return AQStoreFail(error, AQStoreInvalidInput), nil;
        NSString *groupKey = AQCasefold(fixture[@"group_id"]);
        if (groupOrders[groupKey] && order <= groupOrders[groupKey].unsignedLongLongValue) {
            return AQStoreFail(error, AQStoreInvalidInput), nil;
        }
        groupOrders[groupKey] = @(order);
        NSArray *listedFiles = fixture[@"files"];
        NSArray *companions = fixture[@"companions"];
        if (![listedFiles isKindOfClass:[NSArray class]] || listedFiles.count == 0 ||
            ![companions isKindOfClass:[NSArray class]] || listedFiles.count + fixtures.count > AQMaximumManifestRecords) {
            return AQStoreFail(error, AQStoreInvalidInput), nil;
        }
        NSMutableSet<NSString *> *fixturePaths = [NSMutableSet set];
        NSMutableDictionary<NSString *, AQStoreMember *> *memberByPath = [NSMutableDictionary dictionary];
        for (id rawFile in listedFiles) {
            if (!AQExactKeys(rawFile, fileKeys, [NSSet set])) return AQStoreFail(error, AQStoreInvalidInput), nil;
            NSDictionary *file = rawFile;
            NSArray<NSString *> *components = nil;
            uint64_t size = 0;
            if (!AQRelativePath(file[@"path"], &components) || !AQDescriptionString(file[@"role"], 64) ||
                !AQIntegerValue(file[@"size"], 0, (uint64_t)INT64_MAX, &size) || !AQDigestText(file[@"sha256"])) {
                return AQStoreFail(error, AQStoreInvalidInput), nil;
            }
            NSString *memberPath = [fixtureID stringByAppendingFormat:@"/%@", file[@"path"]];
            if (!AQAddUnique(fixturePaths, AQCasefold(file[@"path"])) ||
                AQPathsConflict(files, directories, memberPath)) return AQStoreFail(error, AQStoreInvalidInput), nil;
            AQStoreMember *member = [AQStoreMember new];
            member.path = memberPath;
            member.size = size;
            member.sha256 = file[@"sha256"];
            memberByPath[(NSString *)file[@"path"]] = member;
            [allMembers addObject:member];
        }
        NSString *entrypoint = fixture[@"entrypoint"];
        if (!AQRelativePath(entrypoint, NULL) || memberByPath[entrypoint] == nil) return AQStoreFail(error, AQStoreInvalidInput), nil;
        NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *edges = [NSMutableDictionary dictionary];
        NSMutableSet<NSString *> *edgeSet = [NSMutableSet set];
        for (id rawCompanion in companions) {
            if (!AQExactKeys(rawCompanion, companionKeys, [NSSet set])) return AQStoreFail(error, AQStoreInvalidInput), nil;
            NSString *source = rawCompanion[@"source"];
            NSString *target = rawCompanion[@"target"];
            if (!AQRelativePath(source, NULL) || !AQRelativePath(target, NULL) ||
                memberByPath[source] == nil || memberByPath[target] == nil) return AQStoreFail(error, AQStoreInvalidInput), nil;
            NSString *edgeKey = [[AQCasefold(source) stringByAppendingString:@"\0"] stringByAppendingString:AQCasefold(target)];
            if (!AQAddUnique(edgeSet, edgeKey)) return AQStoreFail(error, AQStoreInvalidInput), nil;
            if (!edges[source]) edges[source] = [NSMutableSet set];
            [edges[source] addObject:target];
        }
        NSMutableSet<NSString *> *reached = [NSMutableSet set];
        NSMutableArray<NSString *> *pending = [NSMutableArray arrayWithObject:entrypoint];
        while (pending.count > 0) {
            NSString *current = pending.lastObject;
            [pending removeLastObject];
            if (![reached containsObject:current]) [reached addObject:current]; else continue;
            NSSet<NSString *> *outgoing = edges[current];
            if (outgoing != nil) [pending addObjectsFromArray:outgoing.allObjects];
        }
        if (![reached isEqualToSet:[NSSet setWithArray:memberByPath.allKeys]]) return AQStoreFail(error, AQStoreInvalidInput), nil;
        if (!([fixture[@"identity_evidence"] isEqual:@"synthetic_expectation_v2"] ||
              [fixture[@"identity_evidence"] isEqual:@"independent_reference_pinned_v1"])) {
            return AQStoreFail(error, AQStoreInvalidInput), nil;
        }
        NSDictionary *oraclePin = fixture[@"oracle_pin"];
        uint64_t oracleVersion = 0;
        if (!AQExactKeys(oraclePin, oracleKeys, [NSSet set]) ||
            !AQIntegerValue(oraclePin[@"schema_version"], 1, 1, &oracleVersion) ||
            !AQDescriptionString(oraclePin[@"oracle_ref"], 256) ||
            !AQDescriptionString(oraclePin[@"revision"], 256) || !AQDigestText(oraclePin[@"sha256"])) {
            return AQStoreFail(error, AQStoreInvalidInput), nil;
        }
        if (fixture[@"facts"]) {
            NSDictionary *facts = fixture[@"facts"];
            NSSet *factKeys = [NSSet setWithArray:@[@"edition", @"region", @"disc_set"]];
            if (!AQExactKeys(facts, factKeys, [NSSet set])) return AQStoreFail(error, AQStoreInvalidInput), nil;
            for (id key in facts) if (!AQDescriptionString(facts[key], 256)) return AQStoreFail(error, AQStoreInvalidInput), nil;
        }
    }
    if (![fixtureKeys isEqualToSet:selectedSet]) return AQStoreFail(error, AQStoreInvalidInput), nil;
    return [allMembers copy];
}

@interface AQMachStoreClock : NSObject <AQStoreClock>
@end

@implementation AQMachStoreClock
- (uint64_t)continuousTicks { return mach_continuous_time(); }
@end

#if defined(AQ_STORE_TESTING)
@implementation AQStoreTestHooks
@end
#endif

static NSData *AQStoreCanonicalExportHeader(NSString *sessionID, NSString *manifestSHA256,
                                            uint64_t generation,
                                            NSArray<NSDictionary *> *members,
                                            NSError **error) {
    if (error) *error = nil;
    if (!AQASCIIToken(sessionID, 256) || !AQDigestText(manifestSHA256) ||
        generation > INT64_MAX || ![members isKindOfClass:[NSArray class]]) {
        return AQStoreFail(error, AQStoreInvalidInput), nil;
    }
    NSDictionary *header = @{
        @"schema_version": @1,
        @"session_id": sessionID,
        @"manifest_sha256": manifestSHA256,
        @"generation": @(generation),
        @"members": members,
    };
    NSError *canonicalError = nil;
    NSData *data = AQCanonicalJSON(header, &canonicalError);
    if (data == nil) {
        if ([canonicalError.domain isEqual:AQContractErrorDomain] &&
            canonicalError.code == AQLimitExceeded) {
            return AQStoreFail(error, AQStoreMetadataHeaderTooLarge), nil;
        }
        return AQStoreFail(error, AQStoreInvalidInput), nil;
    }
    if (data.length > AQStoreMaximumExportMetadataHeaderBytes) {
        return AQStoreFail(error, AQStoreMetadataHeaderTooLarge), nil;
    }
    return data;
}

#if defined(AQ_STORE_TESTING)
BOOL AQStoreExportHeaderWithinLimitForTesting(NSDictionary *manifest, NSString *sessionID,
                                              NSString *manifestSHA256, uint64_t generation,
                                              NSError **error) {
    if (error) *error = nil;
    NSArray<AQStoreMember *> *members = AQMembersFromManifest(manifest, error);
    if (members == nil) return NO;
    NSMutableArray<NSDictionary *> *headerMembers = [NSMutableArray arrayWithCapacity:members.count];
    for (AQStoreMember *member in members) {
        [headerMembers addObject:@{@"path": member.path, @"size": @(member.size),
                                   @"sha256": member.sha256}];
    }
    return AQStoreCanonicalExportHeader(sessionID, manifestSHA256, generation,
                                        headerMembers, error) != nil;
}
#endif

typedef BOOL (^AQStoreRequestPreflight)(AQStoreSession *session, NSError **error);

@interface AQStore () {
    int _rootFD;
    dev_t _pinnedDevice;
    ino_t _pinnedInode;
    NSString *_installationIdentity;
    BOOL _productionMode;
    id<AQStoreClock> _clock;
    NSMutableDictionary<NSString *, AQStoreSession *> *_sessions;
    NSMutableSet<NSString *> *_requestSequences;
    NSMutableSet<NSString *> *_observedRootNames;
    // The reentrant store lock protects session state and serializes the
    // matching immutable journal snapshot with its durable append.
    NSObject *_storeLock;
    uint64_t _nextRecordOrdinal;
    BOOL _rootBlocked;
    NSString *_rootBlockReason;
    BOOL _recoveredSessions;
    BOOL _freshAdmissionConsumed;
    NSMutableSet<NSString *> *_consumedGrantIDs;
    NSString *_activeSessionID;
    NSString *_activeOperation;
#if defined(AQ_STORE_TESTING)
    AQStoreTestHooks *_hooks;
#endif
}
- (nullable instancetype)initInternalWithRootFD:(int)rootFD
                           installationIdentity:(NSString *)installationIdentity
                                      production:(BOOL)production
                                           clock:(id<AQStoreClock>)clock
#if defined(AQ_STORE_TESTING)
                                           hooks:(nullable AQStoreTestHooks *)hooks
#endif
                                           error:(NSError **)error;
- (BOOL)loadJournalWithError:(NSError **)error;
- (BOOL)boundaryAllows:(NSString *)name;
- (BOOL)appendEvent:(NSString *)event session:(AQStoreSession *)session error:(NSError **)error;
- (BOOL)acceptRequest:(NSDictionary *)request session:(AQStoreSession **)sessionOut
             operation:(NSString *)operation
            preflight:(nullable AQStoreRequestPreflight)preflight
                error:(NSError **)error;
- (void)finishOperationForSession:(NSString *)sessionID;
- (BOOL)markSession:(AQStoreSession *)session state:(NSString *)state effectState:(NSString *)effectState
             lastError:(NSString *)lastError event:(NSString *)event error:(NSError **)error;
- (NSDictionary<NSString *, NSNumber *> *)duplicateSourceDescriptors:(NSDictionary<NSString *, NSNumber *> *)sourceFDs
                                                              members:(NSArray<AQStoreMember *> *)members
                                                                error:(NSError **)error;
- (BOOL)copyMember:(AQStoreMember *)member sourceFD:(int)sourceFD stageFD:(int)stageFD
          remaining:(uint64_t *)remaining session:(AQStoreSession *)session error:(NSError **)error;
- (BOOL)verifySnapshotNamed:(NSString *)snapshotName members:(NSArray<AQStoreMember *> *)members
                       error:(NSError **)error;
- (BOOL)verifySnapshotNamed:(NSString *)snapshotName members:(NSArray<AQStoreMember *> *)members
            entryIdentities:(NSMutableDictionary<NSString *, NSDictionary *> *)entryIdentities
                       error:(NSError **)error;
- (BOOL)verifyDirectoryFD:(int)directoryFD prefix:(NSString *)prefix
             expectedFiles:(NSDictionary<NSString *, AQStoreMember *> *)expectedFiles
              expectedDirs:(NSSet<NSString *> *)expectedDirs
                 seenFiles:(NSMutableSet<NSString *> *)seenFiles
            entryIdentities:(NSMutableDictionary<NSString *, NSDictionary *> *)entryIdentities
                       error:(NSError **)error;
- (BOOL)recordCleanupAttempt:(NSString *)entry session:(AQStoreSession *)session error:(NSError **)error;
@end

static BOOL AQRecordNameMatches(NSString *name, uint64_t *ordinal) {
    if (![name hasPrefix:AQRecordPrefix]) return NO;
    NSString *suffix = [name substringFromIndex:AQRecordPrefix.length];
    if (suffix.length != 20) return NO;
    uint64_t value = 0;
    for (NSUInteger index = 0; index < suffix.length; ++index) {
        unichar character = [suffix characterAtIndex:index];
        if (character < '0' || character > '9') return NO;
        uint64_t digit = (uint64_t)(character - '0');
        if (value > (UINT64_MAX - digit) / 10) return NO;
        value = value * 10 + digit;
    }
    if (value == 0) return NO;
    if (ordinal) *ordinal = value;
    return YES;
}

static NSString *AQRecordName(uint64_t ordinal) {
    return [NSString stringWithFormat:@"%@%020llu", AQRecordPrefix, (unsigned long long)ordinal];
}

static NSDictionary *AQParseRecord(NSData *data, NSError **error) {
    if (data.length == 0 || data.length > AQMaximumRecordBytes) return AQStoreFail(error, AQStoreJournalCorrupt), nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) return AQStoreFail(error, AQStoreJournalCorrupt), nil;
    NSError *canonicalError = nil;
    NSData *canonical = AQCanonicalJSONWithMaximumBytes(
        object, AQMaximumRecordBytes, &canonicalError);
    if (canonical == nil || ![canonical isEqualToData:data]) return AQStoreFail(error, AQStoreJournalCorrupt), nil;
    return object;
}

static NSArray<NSString *> *AQSortedNamesInDirectory(int directoryFD, BOOL *okay) {
    if (okay) *okay = NO;
    int duplicate = fcntl(directoryFD, F_DUPFD_CLOEXEC, 3);
    if (duplicate < 0) return nil;
    DIR *directory = fdopendir(duplicate);
    if (!directory) {
        close(duplicate);
        return nil;
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    rewinddir(directory);
    errno = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        NSString *name = [NSString stringWithUTF8String:entry->d_name];
        if (name == nil) {
            closedir(directory);
            return nil;
        }
        [names addObject:name];
        errno = 0;
    }
    BOOL readError = errno != 0;
    if (closedir(directory) != 0) readError = YES;
    if (readError) return nil;
    if (okay) *okay = YES;
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

static int AQOpenSubdirectory(int baseFD, NSArray<NSString *> *components, NSUInteger count) {
    int current = fcntl(baseFD, F_DUPFD_CLOEXEC, 3);
    if (current < 0) return -1;
    for (NSUInteger index = 0; index < count; ++index) {
        int next = openat(current, components[index].fileSystemRepresentation,
                          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        close(current);
        if (next < 0) return -1;
        current = next;
    }
    return current;
}

static NSString *AQRandomName(NSString *prefix) {
    unsigned char bytes[16];
    arc4random_buf(bytes, sizeof(bytes));
    NSMutableString *name = [NSMutableString stringWithString:prefix];
    for (NSUInteger index = 0; index < sizeof(bytes); ++index) [name appendFormat:@"%02x", bytes[index]];
    return name;
}

static void AQCloseDescriptors(NSDictionary<NSString *, NSNumber *> *descriptors) {
    for (NSNumber *descriptor in descriptors.allValues) close(descriptor.intValue);
}

static BOOL AQWritePipeBytes(int fd, const void *bytes, size_t length, BOOL (^stillLive)(void)) {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        if (!stillLive()) return NO;
        ssize_t count = write(fd, cursor, length);
        if (count > 0) {
            cursor += (size_t)count;
            length -= (size_t)count;
            continue;
        }
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd event = {fd, POLLOUT, 0};
            int polled = poll(&event, 1, 100);
            if (polled < 0 && errno != EINTR) return NO;
            if (polled == 0) continue;
            if ((event.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) return NO;
            continue;
        }
        return NO;
    }
    return YES;
}

static void AQBigEndian64(uint64_t value, uint8_t bytes[8]) {
    for (NSUInteger index = 0; index < 8; ++index) bytes[index] = (uint8_t)(value >> (56 - index * 8));
}

static BOOL AQHashMatchesDescriptor(int fd, uint64_t expectedSize, NSString *expectedSHA256,
                                    NSError **error);

static BOOL AQCleanupEntryMatchesIdentity(int parentFD, NSString *name, NSDictionary *identity,
                                           AQStoreMember *member, NSError **error) {
    struct stat status;
    if (fstatat(parentFD, name.fileSystemRepresentation, &status, AT_SYMLINK_NOFOLLOW) != 0 ||
        status.st_uid != geteuid() || status.st_dev != [identity[@"device"] longLongValue] ||
        status.st_ino != [identity[@"inode"] unsignedLongLongValue] ||
        status.st_mode != [identity[@"mode"] unsignedIntValue]) {
        return AQStoreFail(error, AQStoreIntegrityFailure);
    }
    if ([identity[@"kind"] isEqual:@"directory"]) {
        if (!S_ISDIR(status.st_mode)) return AQStoreFail(error, AQStoreIntegrityFailure);
        return YES;
    }
    if (![identity[@"kind"] isEqual:@"file"] || member == nil || !S_ISREG(status.st_mode) ||
        status.st_nlink != 1 || status.st_size < 0 || (uint64_t)status.st_size != member.size) {
        return AQStoreFail(error, AQStoreIntegrityFailure);
    }
    int fileFD = openat(parentFD, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fileFD < 0) return AQStoreFail(error, AQStoreIntegrityFailure);
    struct stat opened;
    BOOL valid = fstat(fileFD, &opened) == 0 && opened.st_dev == status.st_dev &&
        opened.st_ino == status.st_ino && opened.st_nlink == 1 && opened.st_mode == status.st_mode &&
        AQHashMatchesDescriptor(fileFD, member.size, member.sha256, error);
    close(fileFD);
    return valid;
}

/* unlinkat removes a name, not a previously checked inode. Keep the store
 * root inaccessible to the operator and other UIDs so an untrusted process
 * cannot replace a checked entry before the unlink syscall. Production also
 * verifies the root's protected ancestry before passing this descriptor.
 */
static BOOL AQStoreDirectoryHasEmptyACL(int fd) {
    errno = 0;
    acl_t acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
    BOOL empty = acl == NULL && (errno == EINVAL || errno == ENOENT);
    if (!acl && !empty) return NO;
    if (acl) {
        acl_entry_t entry;
        BOOL valid = acl_valid(acl) == 0;
        errno = 0;
        empty = valid && acl_get_entry(acl, ACL_FIRST_ENTRY, &entry) == -1 && errno == EINVAL;
        acl_free(acl);
    }
    return empty;
}

static BOOL AQRemoveSnapshotEntry(int rootFD, NSString *snapshotName, NSString *relativePath,
                                  BOOL directory, NSDictionary *identity, AQStoreMember *member,
                                  BOOL (^beforeUnlink)(NSString *entry), NSError **error) {
    if (relativePath.length == 0) {
        if (beforeUnlink != nil && !beforeUnlink(@"root")) return AQStoreFail(error, AQStoreIOFailure);
        if (!AQCleanupEntryMatchesIdentity(rootFD, snapshotName, identity, nil, error)) return NO;
        if (unlinkat(rootFD, snapshotName.fileSystemRepresentation, AT_REMOVEDIR) != 0 ||
            !AQDirectorySync(rootFD)) return AQStoreFail(error, AQStoreIOFailure);
        return YES;
    }
    int snapshotFD = openat(rootFD, snapshotName.fileSystemRepresentation,
                            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (snapshotFD < 0) return AQStoreFail(error, AQStoreIOFailure);
    NSArray<NSString *> *components = [relativePath componentsSeparatedByString:@"/"];
    int parentFD = AQOpenSubdirectory(snapshotFD, components, components.count - 1);
    close(snapshotFD);
    if (parentFD < 0) return AQStoreFail(error, AQStoreIOFailure);
    NSString *leaf = components.lastObject;
    if (beforeUnlink != nil && !beforeUnlink(relativePath)) {
        close(parentFD);
        return AQStoreFail(error, AQStoreIOFailure);
    }
    if (!AQCleanupEntryMatchesIdentity(parentFD, leaf, identity, member, error)) {
        close(parentFD);
        return NO;
    }
    int flags = directory ? AT_REMOVEDIR : 0;
    BOOL removed = unlinkat(parentFD, leaf.fileSystemRepresentation, flags) == 0;
    if (removed) removed = AQDirectorySync(parentFD);
    close(parentFD);
    return removed ? YES : AQStoreFail(error, AQStoreIOFailure);
}

static NSString *AQHashDescriptor(int fd, NSError **error) {
    CC_SHA256_CTX context;
    if (CC_SHA256_Init(&context) != 1) return AQStoreFail(error, AQStoreIOFailure), nil;
    NSMutableData *buffer = [NSMutableData dataWithLength:AQStoreIOChunkSize];
    off_t offset = 0;
    for (;;) {
        ssize_t count = pread(fd, buffer.mutableBytes, buffer.length, offset);
        if (count < 0) {
            if (errno == EINTR) continue;
            return AQStoreFail(error, AQStoreIOFailure), nil;
        }
        if (count == 0) break;
        CC_SHA256_Update(&context, buffer.bytes, (CC_LONG)count);
        offset += (off_t)count;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *text = [NSMutableString stringWithCapacity:64];
    for (NSUInteger index = 0; index < sizeof(digest); ++index) [text appendFormat:@"%02x", digest[index]];
    return text;
}

static BOOL AQHashMatchesDescriptor(int fd, uint64_t expectedSize, NSString *expectedSHA256,
                                    NSError **error) {
    struct stat status;
    if (fstat(fd, &status) != 0 || !S_ISREG(status.st_mode) || status.st_size < 0 ||
        (uint64_t)status.st_size != expectedSize) return AQStoreFail(error, AQStoreIntegrityFailure);
    NSString *digest = AQHashDescriptor(fd, error);
    if (digest == nil) return NO;
    if (![digest isEqual:expectedSHA256]) return AQStoreFail(error, AQStoreIntegrityFailure);
    return YES;
}

static NSArray<NSString *> *AQParentDirectories(NSString *path) {
    NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *parents = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSUInteger index = 0; index + 1 < components.count; ++index) {
        if (current.length > 0) [current appendString:@"/"];
        [current appendString:components[index]];
        [parents addObject:[current copy]];
    }
    return parents;
}

@implementation AQStore

- (instancetype)initWithRootFD:(int)rootFD
           installationIdentity:(NSString *)installationIdentity
                          error:(NSError **)error {
#if defined(AQ_STORE_TESTING)
    return [self initInternalWithRootFD:rootFD installationIdentity:installationIdentity
                             production:YES clock:[AQMachStoreClock new] hooks:nil error:error];
#else
    return [self initInternalWithRootFD:rootFD installationIdentity:installationIdentity
                             production:YES clock:[AQMachStoreClock new] error:error];
#endif
}

#if defined(AQ_STORE_TESTING)
- (instancetype)initForTestingWithRootFD:(int)rootFD
                    installationIdentity:(NSString *)installationIdentity
                                   clock:(id<AQStoreClock>)clock
                                   hooks:(AQStoreTestHooks *)hooks
                                   error:(NSError **)error {
    return [self initInternalWithRootFD:rootFD installationIdentity:installationIdentity
                             production:NO clock:clock hooks:hooks error:error];
}
#endif

- (instancetype)initInternalWithRootFD:(int)rootFD
                  installationIdentity:(NSString *)installationIdentity
                             production:(BOOL)production
                                  clock:(id<AQStoreClock>)clock
#if defined(AQ_STORE_TESTING)
                                  hooks:(AQStoreTestHooks *)hooks
#endif
                                  error:(NSError **)error {
    if (error) *error = nil;
    if (rootFD < 0 || clock == nil || !AQDigestText(installationIdentity)) {
        AQStoreFail(error, AQStoreInvalidInput);
        return nil;
    }
    if (!(self = [super init])) return nil;
    _rootFD = -1;
    _storeLock = [NSObject new];
    _sessions = [NSMutableDictionary dictionary];
    _requestSequences = [NSMutableSet set];
    _observedRootNames = [NSMutableSet set];
    _consumedGrantIDs = [NSMutableSet set];
    _nextRecordOrdinal = 1;
    _installationIdentity = [installationIdentity copy];
    _productionMode = production;
    _clock = clock;
#if defined(AQ_STORE_TESTING)
    _hooks = hooks;
#endif
    int duplicate = fcntl(rootFD, F_DUPFD_CLOEXEC, 3);
    if (duplicate < 0) {
        AQStoreFail(error, AQStoreUnauthorizedRoot);
        return nil;
    }
    _rootFD = duplicate;
    struct stat rootStatus;
    if (fstat(_rootFD, &rootStatus) != 0 || !S_ISDIR(rootStatus.st_mode) ||
        rootStatus.st_uid != geteuid() || (rootStatus.st_mode & 07777) != 0700 ||
        !AQStoreDirectoryHasEmptyACL(_rootFD)) {
        AQStoreFail(error, AQStoreUnauthorizedRoot);
        return nil;
    }
    if (production) {
        char path[PATH_MAX];
        if (rootStatus.st_uid != geteuid() || fcntl(_rootFD, F_GETPATH, path) != 0 ||
            strcmp(path, AQStoreProductionRoot.fileSystemRepresentation) != 0) {
            AQStoreFail(error, AQStoreUnauthorizedRoot);
            return nil;
        }
    }
    _pinnedDevice = rootStatus.st_dev;
    _pinnedInode = rootStatus.st_ino;
    if (![self loadJournalWithError:error]) return nil;
    return self;
}

- (void)dealloc {
    if (_rootFD >= 0) close(_rootFD);
}

- (BOOL)loadJournalWithError:(NSError **)error {
    BOOL listed = NO;
    NSArray<NSString *> *names = AQSortedNamesInDirectory(_rootFD, &listed);
    if (!listed) return AQStoreFail(error, AQStoreIOFailure);
    uint64_t expectedOrdinal = 1;
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *digestSequences =
        [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *sessionEvents = [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        if (![name hasPrefix:AQRecordPrefix]) continue;
        [_observedRootNames addObject:name];
        uint64_t ordinal = 0;
        if (!AQRecordNameMatches(name, &ordinal) || ordinal != expectedOrdinal) {
            _rootBlocked = YES;
            _rootBlockReason = @"journal_name_or_gap";
            break;
        }
        int recordFD = openat(_rootFD, name.fileSystemRepresentation,
                              O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        if (recordFD < 0) {
            _rootBlocked = YES;
            _rootBlockReason = @"journal_open";
            break;
        }
        struct stat recordStatus;
        if (fstat(recordFD, &recordStatus) != 0 || !S_ISREG(recordStatus.st_mode) ||
            recordStatus.st_nlink != 1 || recordStatus.st_uid != geteuid() ||
            (recordStatus.st_mode & 0077) != 0 || recordStatus.st_size <= 0 ||
            (uint64_t)recordStatus.st_size > AQMaximumRecordBytes) {
            close(recordFD);
            _rootBlocked = YES;
            _rootBlockReason = @"journal_metadata";
            break;
        }
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)recordStatus.st_size];
        BOOL read = AQReadExact(recordFD, data.mutableBytes, data.length, 0);
        close(recordFD);
        if (!read) {
            _rootBlocked = YES;
            _rootBlockReason = @"journal_read";
            break;
        }
        NSError *recordError = nil;
        NSDictionary *record = AQParseRecord(data, &recordError);
        NSSet *recordKeys = [NSSet setWithArray:@[@"record_version", @"installation_identity", @"event",
                                                  @"request_sha256", @"session"]];
        uint64_t recordVersion = 0;
        if (record == nil || !AQExactKeys(record, recordKeys, [NSSet set]) ||
            !AQIntegerValue(record[@"record_version"], 1, 1, &recordVersion) ||
            ![record[@"installation_identity"] isEqual:_installationIdentity] ||
            ![record[@"event"] isKindOfClass:[NSString class]] ||
            ![record[@"request_sha256"] isKindOfClass:[NSString class]]) {
            _rootBlocked = YES;
            _rootBlockReason = @"journal_schema";
            break;
        }
        AQStoreSession *session = AQSessionFromRecord(record[@"session"]);
        NSString *requestDigest = record[@"request_sha256"];
        NSString *event = record[@"event"];
        NSSet *events = [NSSet setWithArray:@[@"admitted", @"dispatch", @"stage_intent", @"stage_eligible", @"stage_blocked",
                                              @"eligibility_verified", @"eligibility_failed", @"export_started", @"export_completed",
                                              @"export_failed", @"cleanup_attempt", @"cleanup_member_done",
                                              @"cleanup_complete", @"cleanup_failed", @"revoked"]];
        if (session == nil || event == nil || ![events containsObject:event] ||
            ![requestDigest isEqual:session.requestSHA256] ||
            (requestDigest.length != 0 && !AQDigestText(requestDigest))) {
            _rootBlocked = YES;
            _rootBlockReason = @"journal_session";
            break;
        }
        AQStoreSession *previous = _sessions[session.sessionID];
        NSString *previousEvent = sessionEvents[session.sessionID];
        // Journal ordinals are global, while each session starts independently.
        if (previous == nil) {
            if (![record[@"event"] isEqual:@"admitted"] || session.sequence != 0 || session.generation != 0) {
                _rootBlocked = YES;
                _rootBlockReason = @"journal_first_event";
                break;
            }
            if ([_consumedGrantIDs containsObject:session.grantID]) {
                _rootBlocked = YES;
                _rootBlockReason = @"journal_reused_grant";
                break;
            }
            [_consumedGrantIDs addObject:session.grantID];
        } else if (
                   (![previous.grantID isEqual:session.grantID]) ||
                   (![previous.connectionID isEqual:session.connectionID]) || previous.epoch != session.epoch ||
                   (![previous.manifestSHA256 isEqual:session.manifestSHA256]) ||
                   (![previous.planSHA256 isEqual:session.planSHA256]) ||
                   (![previous.rulesSHA256 isEqual:session.rulesSHA256]) ||
                   previous.deadlineTicks != session.deadlineTicks ||
                   previous.sequence + 1 < session.sequence || session.sequence < previous.sequence ||
                   previous.generation + 1 < session.generation || session.generation < previous.generation ||
                   (session.generation > previous.generation &&
                    ![record[@"event"] isEqual:@"stage_eligible"])) {
            _rootBlocked = YES;
            _rootBlockReason = @"journal_binding_or_generation";
            break;
        }
        if (!AQStoreReplayEventTransitionValid(event, previousEvent, previous, session)) {
            _rootBlocked = YES;
            _rootBlockReason = @"journal_transition";
            break;
        }
        // Request digests are single-use within one session. Different sessions
        // may legitimately use the same caller-computed digest.
        if (requestDigest.length > 0) {
            NSMutableDictionary<NSString *, NSNumber *> *sessionDigests = digestSequences[session.sessionID];
            if (sessionDigests == nil) {
                sessionDigests = [NSMutableDictionary dictionary];
                digestSequences[session.sessionID] = sessionDigests;
            }
            NSNumber *existing = sessionDigests[requestDigest];
            if (existing != nil && existing.unsignedLongLongValue != session.sequence) {
                _rootBlocked = YES;
                _rootBlockReason = @"journal_reused_request";
                break;
            }
            sessionDigests[requestDigest] = @(session.sequence);
        }
        _sessions[session.sessionID] = session;
        sessionEvents[session.sessionID] = event;
        expectedOrdinal += 1;
    }
    _nextRecordOrdinal = expectedOrdinal > 1 ? expectedOrdinal : 1;
    if (_rootBlocked) {
        if (error) *error = AQStoreFailure(AQStoreJournalCorrupt);
    }
    if (_sessions.count > 0) {
        _recoveredSessions = YES;
        for (AQStoreSession *session in _sessions.allValues) {
            session.state = @"blocked_retained";
            session.effectState = @"retained";
        }
    }
    return YES;
}

- (BOOL)appendEvent:(NSString *)event session:(AQStoreSession *)session error:(NSError **)error {
    @synchronized(_storeLock) {
        if (_rootBlocked) return AQStoreFail(error, AQStoreJournalCorrupt);
        if (![self boundaryAllows:@"before_record_snapshot"]) return AQStoreFail(error, AQStoreIOFailure);
        NSDictionary *sessionSnapshot = session.recordRepresentation;
        NSDictionary *record = @{
            @"record_version": @1,
            @"installation_identity": _installationIdentity,
            @"event": event,
            @"request_sha256": session.requestSHA256 ?: @"",
            @"session": sessionSnapshot,
        };
        NSData *data = AQCanonicalJSONWithMaximumBytes(record, AQMaximumRecordBytes, error);
        if (data == nil) return NO;
        if (data.length == 0 || data.length > AQMaximumRecordBytes) {
            return AQStoreFail(error, AQStoreJournalCorrupt);
        }
        NSString *name = AQRecordName(_nextRecordOrdinal);
        int fd = openat(_rootFD, name.fileSystemRepresentation,
                        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd < 0) {
            _rootBlocked = YES;
            _rootBlockReason = @"record_create";
            return AQStoreFail(error, AQStoreIOFailure);
        }
        BOOL written = AQWriteAll(fd, data.bytes, data.length);
        if (written) written = fchmod(fd, 0400) == 0;
        if (written) written = AQFullSync(fd, YES);
        if (close(fd) != 0) written = NO;
        if (written) written = AQDirectorySync(_rootFD);
        if (!written) {
            _rootBlocked = YES;
            _rootBlockReason = @"record_durability";
            return AQStoreFail(error, AQStoreIOFailure);
        }
        _nextRecordOrdinal += 1;
        [_observedRootNames addObject:name];
#if defined(AQ_STORE_TESTING)
        void (^recordWritten)(NSString *, NSDictionary *) = _hooks.recordWritten;
        if (recordWritten != nil) recordWritten(event, sessionSnapshot);
#endif
    }
    return YES;
}

- (uint64_t)currentTicks {
    return [_clock continuousTicks];
}

- (BOOL)deadlineAllowsForSession:(AQStoreSession *)session error:(NSError **)error {
    uint64_t now = [self currentTicks];
    if (now >= session.deadlineTicks) return AQStoreFail(error, AQStoreDeadlineExpired);
    return YES;
}

- (BOOL)boundaryAllows:(NSString *)name {
#if defined(AQ_STORE_TESTING)
    BOOL (^hook)(NSString *) = _hooks.boundary;
    return hook == nil || hook(name);
#else
    (void)name;
    return YES;
#endif
}

- (BOOL)availableBytes:(uint64_t *)bytes error:(NSError **)error {
#if defined(AQ_STORE_TESTING)
    NSNumber * (^hook)(void) = _hooks.availableBytes;
    if (hook != nil) {
        id value = hook();
        if (!AQIntegerValue(value, 0, UINT64_MAX, bytes)) return AQStoreFail(error, AQStoreCapacityDenied);
        return YES;
    }
#endif
    if (!AQAvailableBytes(_rootFD, bytes)) return AQStoreFail(error, AQStoreIOFailure);
    return YES;
}

- (BOOL)capacityAllows:(uint64_t)remaining session:(AQStoreSession *)session error:(NSError **)error {
    uint64_t available = 0;
    if (![self availableBytes:&available error:error]) return NO;
    if (!AQStoreCapacityAllows(available, remaining, session.hostReserveBytes,
                               session.destinationReserveBytes)) {
        return AQStoreFail(error, AQStoreCapacityDenied);
    }
    return YES;
}

- (BOOL)rootIdentityStillValid {
    struct stat status;
    return fstat(_rootFD, &status) == 0 && S_ISDIR(status.st_mode) &&
        status.st_dev == _pinnedDevice && status.st_ino == _pinnedInode;
}

- (BOOL)sessionIsLive:(AQStoreSession *)session error:(NSError **)error {
    BOOL rootBlocked = NO;
    BOOL revoked = NO;
    uint64_t deadline = 0;
    @synchronized(_storeLock) {
        rootBlocked = _rootBlocked;
        revoked = session.revoked;
        deadline = session.deadlineTicks;
    }
    if (rootBlocked) return AQStoreFail(error, AQStoreJournalCorrupt);
    if (![self rootIdentityStillValid]) return AQStoreFail(error, AQStoreUnauthorizedRoot);
    if (revoked) return AQStoreFail(error, AQStoreRevoked);
    if ([self currentTicks] >= deadline) return AQStoreFail(error, AQStoreDeadlineExpired);
    return YES;
}

- (BOOL)failureMayBeRetainedForSession:(AQStoreSession *)session {
    BOOL revoked = NO;
    uint64_t deadline = 0;
    @synchronized(_storeLock) {
        revoked = session.revoked;
        deadline = session.deadlineTicks;
    }
    return !revoked && [self currentTicks] < deadline;
}

- (NSDictionary *)admitManifest:(NSDictionary *)manifest
                      authority:(NSDictionary *)authority
                          error:(NSError **)error {
    if (error) *error = nil;
    NSArray<AQStoreMember *> *members = AQMembersFromManifest(manifest, error);
    if (members == nil) return nil;
    NSSet *authorityKeys = [NSSet setWithArray:@[
        @"session_id", @"grant_id", @"connection_id", @"epoch", @"manifest_sha256", @"plan_sha256",
        @"rules_sha256", @"deadline_ticks", @"host_reserve_bytes", @"destination_reserve_bytes", @"operations"
    ]];
    if (!AQExactKeys(authority, authorityKeys, [NSSet set]) ||
        !AQASCIIToken(authority[@"session_id"], 256) || !AQASCIIToken(authority[@"grant_id"], 256) ||
        !AQASCIIToken(authority[@"connection_id"], 256) || !AQDigestText(authority[@"manifest_sha256"]) ||
        !AQDigestText(authority[@"plan_sha256"]) || !AQDigestText(authority[@"rules_sha256"]) ||
        ![authority[@"plan_sha256"] isEqual:manifest[@"plan_sha256"]] ||
        ![authority[@"rules_sha256"] isEqual:manifest[@"rules_sha256"]]) {
        AQStoreFail(error, AQStoreInvalidInput);
        return nil;
    }
    uint64_t epoch = 0, deadline = 0, hostReserve = 0, destinationReserve = 0;
    if (!AQIntegerValue(authority[@"epoch"], 0, (uint64_t)INT64_MAX, &epoch) ||
        !AQIntegerValue(authority[@"deadline_ticks"], 1, (uint64_t)INT64_MAX, &deadline) ||
        !AQIntegerValue(authority[@"host_reserve_bytes"], 0, (uint64_t)INT64_MAX, &hostReserve) ||
        !AQIntegerValue(authority[@"destination_reserve_bytes"], 0, (uint64_t)INT64_MAX, &destinationReserve)) {
        AQStoreFail(error, AQStoreInvalidInput);
        return nil;
    }
    NSArray *rawOperations = authority[@"operations"];
    NSSet *allowedOperations = [NSSet setWithArray:@[@"stage", @"eligibility", @"export", @"cleanup"]];
    if (![rawOperations isKindOfClass:[NSArray class]] || rawOperations.count == 0) {
        AQStoreFail(error, AQStoreInvalidInput);
        return nil;
    }
    NSMutableSet *operationSet = [NSMutableSet set];
    for (id operation in rawOperations) {
        if (![allowedOperations containsObject:operation] || !AQAddUnique(operationSet, operation)) {
            AQStoreFail(error, AQStoreInvalidInput);
            return nil;
        }
    }
    AQStoreSession *session = [AQStoreSession new];
    session.sessionID = authority[@"session_id"];
    session.grantID = authority[@"grant_id"];
    session.connectionID = authority[@"connection_id"];
    session.epoch = epoch;
    session.manifestSHA256 = authority[@"manifest_sha256"];
    session.planSHA256 = authority[@"plan_sha256"];
    session.rulesSHA256 = authority[@"rules_sha256"];
    session.deadlineTicks = deadline;
    session.hostReserveBytes = hostReserve;
    session.destinationReserveBytes = destinationReserve;
    session.operations = [[operationSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    session.members = members;
    if ([session.operations containsObject:@"export"]) {
        NSMutableArray<NSDictionary *> *headerMembers =
            [NSMutableArray arrayWithCapacity:members.count];
        for (AQStoreMember *member in members) {
            [headerMembers addObject:@{@"path": member.path, @"size": @(member.size),
                @"sha256": member.sha256}];
        }
        if (AQStoreCanonicalExportHeader(session.sessionID, session.manifestSHA256, 0,
                headerMembers, error) == nil) return nil;
    }
    session.state = @"admitted";
    @synchronized(_storeLock) {
        if (_rootBlocked) {
            AQStoreFail(error, AQStoreJournalCorrupt);
            return nil;
        }
        // Recovery stays blocked globally. This process can durably admit one
        // new session without changing the older sessions or their obligations.
        if (_recoveredSessions && _freshAdmissionConsumed) {
            AQStoreFail(error, AQStoreInvalidState);
            return nil;
        }
        if ([_consumedGrantIDs containsObject:session.grantID]) {
            AQStoreFail(error, AQStoreInvalidState);
            return nil;
        }
        if (_sessions[session.sessionID] != nil) {
            AQStoreFail(error, AQStoreInvalidState);
            return nil;
        }
        if (![self appendEvent:@"admitted" session:session error:error]) return nil;
        _sessions[session.sessionID] = session;
        [_consumedGrantIDs addObject:session.grantID];
        if (_recoveredSessions) _freshAdmissionConsumed = YES;
    }
    return @{@"session_id": session.sessionID, @"state": @"admitted", @"sequence": @0, @"generation": @0,
             @"operations": session.operations, @"members": @(members.count)};
}

- (BOOL)acceptRequest:(NSDictionary *)request session:(AQStoreSession **)sessionOut
             operation:(NSString *)operation
            preflight:(nullable AQStoreRequestPreflight)preflight
                error:(NSError **)error {
    if (error) *error = nil;
    NSSet *requestKeys = [NSSet setWithArray:@[
        @"session_id", @"grant_id", @"connection_id", @"epoch", @"operation", @"sequence",
        @"request_sha256", @"expected_generation"
    ]];
    if (!AQExactKeys(request, requestKeys, [NSSet set]) ||
        !AQASCIIToken(request[@"session_id"], 256) || !AQASCIIToken(request[@"grant_id"], 256) ||
        !AQASCIIToken(request[@"connection_id"], 256) || !AQDigestText(request[@"request_sha256"]) ||
        ![request[@"operation"] isEqual:operation]) {
        return AQStoreFail(error, AQStoreInvalidInput);
    }
    uint64_t epoch = 0, sequence = 0, expectedGeneration = 0;
    if (!AQIntegerValue(request[@"epoch"], 0, (uint64_t)INT64_MAX, &epoch) ||
        !AQIntegerValue(request[@"sequence"], 1, (uint64_t)INT64_MAX, &sequence) ||
        !AQIntegerValue(request[@"expected_generation"], 0, (uint64_t)INT64_MAX, &expectedGeneration)) {
        return AQStoreFail(error, AQStoreInvalidInput);
    }
    AQStoreSession *session = nil;
    BOOL eventRecorded = NO;
    NSString *previousRequestSHA256 = nil;
    NSString *acceptedDigest = nil;
    @synchronized(_storeLock) {
        if (_rootBlocked) return AQStoreFail(error, AQStoreJournalCorrupt);
        if (_activeSessionID != nil) return AQStoreFail(error, AQStoreBusy);
        session = _sessions[(NSString *)request[@"session_id"]];
        if (session == nil || session.revoked) return AQStoreFail(error, session ? AQStoreRevoked : AQStoreInvalidState);
        if (![session.grantID isEqual:request[@"grant_id"]] ||
            ![session.connectionID isEqual:request[@"connection_id"]] || session.epoch != epoch ||
            expectedGeneration != session.generation || sequence != session.sequence + 1 ||
            ![session.operations containsObject:operation]) {
            return AQStoreFail(error, AQStoreInvalidState);
        }
        if (session.sequence == UINT64_MAX) return AQStoreFail(error, AQStoreInvalidState);
        NSString *digest = request[@"request_sha256"];
        if ([session.acceptedDigests containsObject:digest]) return AQStoreFail(error, AQStoreInvalidState);
        if ([operation isEqual:@"stage"]) {
            if (![session.state isEqual:@"admitted"] || session.pendingName.length != 0) {
                return AQStoreFail(error, AQStoreInvalidState);
            }
        } else if (![session.state isEqual:@"eligible"] || session.snapshotName.length == 0) {
            return AQStoreFail(error, AQStoreInvalidState);
        }
        if ([operation isEqual:@"cleanup"] && [session.effectState isEqual:@"uncertain"]) {
            return AQStoreFail(error, AQStoreInvalidState);
        }
    if (preflight != nil && !preflight(session, error)) return NO;
        previousRequestSHA256 = session.requestSHA256;
        acceptedDigest = digest;
        session.sequence += 1;
        session.requestSHA256 = digest;
        [session.acceptedDigests addObject:digest];
        _activeSessionID = session.sessionID;
        _activeOperation = operation;
        eventRecorded = [self appendEvent:@"dispatch" session:session error:error];
    }
    if (!eventRecorded) {
        @synchronized(_storeLock) {
            session.sequence -= 1;
            session.requestSHA256 = previousRequestSHA256;
            if (acceptedDigest != nil) [session.acceptedDigests removeObject:acceptedDigest];
        }
        [self finishOperationForSession:session.sessionID];
        return NO;
    }
    if (sessionOut) *sessionOut = session;
    return YES;
}

- (void)finishOperationForSession:(NSString *)sessionID {
    @synchronized(_storeLock) {
        if ([_activeSessionID isEqual:sessionID]) {
            _activeSessionID = nil;
            _activeOperation = nil;
        }
    }
}

- (BOOL)markSession:(AQStoreSession *)session state:(NSString *)state effectState:(NSString *)effectState
             lastError:(NSString *)lastError event:(NSString *)event error:(NSError **)error {
    @synchronized(_storeLock) {
        if (session.revoked) return AQStoreFail(error, AQStoreRevoked);
        session.state = state;
        session.effectState = effectState;
        session.lastError = lastError ?: @"";
        return [self appendEvent:event session:session error:error];
    }
}

- (NSDictionary *)inspectSession:(NSString *)sessionID {
    if (![sessionID isKindOfClass:[NSString class]]) return nil;
    @synchronized(_storeLock) {
        AQStoreSession *session = _sessions[sessionID];
        if (session == nil) return nil;
        NSMutableDictionary *result = [@{
            @"session_id": session.sessionID,
            @"grant_id": session.grantID,
            @"connection_id": session.connectionID,
            @"epoch": @(session.epoch),
            @"manifest_sha256": session.manifestSHA256,
            @"sequence": @(session.sequence),
            @"generation": @(session.generation),
            @"state": session.state,
            @"revoked": @(session.revoked),
            @"effect_state": session.effectState,
            @"cleanup_complete": @([session.state isEqual:@"cleaned"]),
        } mutableCopy];
        if (session.snapshotName.length > 0) result[@"snapshot_id"] = session.snapshotName;
        return [result copy];
    }
}

- (NSDictionary *)classifyRecovery {
    @synchronized(_storeLock) {
        if (_rootBlocked) {
            return @{@"state": @"blocked_retained", @"reason": _rootBlockReason ?: @"journal_corrupt",
                     @"sessions": @(_sessions.count)};
        }
        if (_recoveredSessions) {
            return @{@"state": @"blocked_retained", @"reason": @"restart_requires_fresh_authority",
                     @"sessions": @(_sessions.count),
                     @"fresh_admission_available": @(!_freshAdmissionConsumed)};
        }
        return @{@"state": @"clean", @"sessions": @0};
    }
}

- (NSDictionary<NSString *, NSNumber *> *)duplicateSourceDescriptors:(NSDictionary<NSString *, NSNumber *> *)sourceFDs
                                                              members:(NSArray<AQStoreMember *> *)members
                                                                error:(NSError **)error {
    if (![sourceFDs isKindOfClass:[NSDictionary class]] || sourceFDs.count != members.count) {
        AQStoreFail(error, AQStoreSourceDenied);
        return nil;
    }
    NSMutableSet<NSString *> *expected = [NSMutableSet setWithCapacity:members.count];
    for (AQStoreMember *member in members) [expected addObject:member.path];
    if (![expected isEqualToSet:[NSSet setWithArray:sourceFDs.allKeys]]) {
        AQStoreFail(error, AQStoreSourceDenied);
        return nil;
    }
    NSMutableDictionary<NSString *, NSNumber *> *duplicates = [NSMutableDictionary dictionaryWithCapacity:members.count];
    for (AQStoreMember *member in members) {
        uint64_t suppliedFD = 0;
        if (!AQIntegerValue(sourceFDs[member.path], 0, (uint64_t)INT_MAX, &suppliedFD)) {
            AQCloseDescriptors(duplicates);
            AQStoreFail(error, AQStoreSourceDenied);
            return nil;
        }
        int duplicate = fcntl((int)suppliedFD, F_DUPFD_CLOEXEC, 3);
        if (duplicate < 0) {
            AQCloseDescriptors(duplicates);
            AQStoreFail(error, AQStoreSourceDenied);
            return nil;
        }
        int flags = fcntl(duplicate, F_GETFL);
        struct stat status;
        if (flags < 0 || (flags & O_ACCMODE) != O_RDONLY || fstat(duplicate, &status) != 0 ||
            !S_ISREG(status.st_mode) || status.st_nlink != 1 || status.st_size < 0 ||
            (uint64_t)status.st_size != member.size) {
            close(duplicate);
            AQCloseDescriptors(duplicates);
            AQStoreFail(error, AQStoreSourceDenied);
            return nil;
        }
        duplicates[member.path] = @(duplicate);
    }
    return duplicates;
}

- (BOOL)copyMember:(AQStoreMember *)member sourceFD:(int)sourceFD stageFD:(int)stageFD
          remaining:(uint64_t *)remaining session:(AQStoreSession *)session error:(NSError **)error {
    NSArray<NSString *> *components = [member.path componentsSeparatedByString:@"/"];
    int parentFD = fcntl(stageFD, F_DUPFD_CLOEXEC, 3);
    if (parentFD < 0) return AQStoreFail(error, AQStoreIOFailure);
    for (NSUInteger index = 0; index + 1 < components.count; ++index) {
        if (![self sessionIsLive:session error:error] ||
            ![self capacityAllows:*remaining session:session error:error]) {
            close(parentFD);
            return NO;
        }
        int next = openat(parentFD, components[index].fileSystemRepresentation,
                          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0 && errno == ENOENT) {
            if (mkdirat(parentFD, components[index].fileSystemRepresentation, 0700) != 0 && errno != EEXIST) {
                close(parentFD);
                return AQStoreFail(error, AQStoreIOFailure);
            }
            if (!AQDirectorySync(parentFD)) {
                close(parentFD);
                return AQStoreFail(error, AQStoreIOFailure);
            }
            next = openat(parentFD, components[index].fileSystemRepresentation,
                          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        }
        if (next < 0) {
            close(parentFD);
            return AQStoreFail(error, AQStoreIOFailure);
        }
        struct stat directoryStatus;
        if (fstat(next, &directoryStatus) != 0 || !S_ISDIR(directoryStatus.st_mode) ||
            directoryStatus.st_uid != geteuid() || (directoryStatus.st_mode & 0022) != 0) {
            close(next);
            close(parentFD);
            return AQStoreFail(error, AQStoreIOFailure);
        }
        close(parentFD);
        parentFD = next;
    }
    struct stat sourceStatus;
    if (fstat(sourceFD, &sourceStatus) != 0 || !S_ISREG(sourceStatus.st_mode) || sourceStatus.st_nlink != 1 ||
        sourceStatus.st_size < 0 || (uint64_t)sourceStatus.st_size != member.size) {
        close(parentFD);
        return AQStoreFail(error, AQStoreSourceDenied);
    }
    NSString *leaf = components.lastObject;
    int targetFD = openat(parentFD, leaf.fileSystemRepresentation,
                          O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (targetFD < 0) {
        close(parentFD);
        return AQStoreFail(error, AQStoreIOFailure);
    }
    NSMutableData *buffer = [NSMutableData dataWithLength:AQStoreIOChunkSize];
    CC_SHA256_CTX context;
    BOOL okay = CC_SHA256_Init(&context) == 1;
    uint64_t copied = 0;
    while (okay && copied < member.size) {
        if (![self sessionIsLive:session error:error] ||
            ![self capacityAllows:*remaining session:session error:error]) {
            okay = NO;
            break;
        }
        uint64_t left = member.size - copied;
        size_t requested = left > AQStoreIOChunkSize ? AQStoreIOChunkSize : (size_t)left;
        ssize_t count = pread(sourceFD, buffer.mutableBytes, requested, (off_t)copied);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0 || (uint64_t)count > *remaining || !AQPWriteAll(targetFD, buffer.bytes, (size_t)count, (off_t)copied)) {
            AQStoreFail(error, AQStoreIOFailure);
            okay = NO;
            break;
        }
        CC_SHA256_Update(&context, buffer.bytes, (CC_LONG)count);
        copied += (uint64_t)count;
        *remaining -= (uint64_t)count;
        if (![self boundaryAllows:@"after_copy_chunk"]) {
            AQStoreFail(error, AQStoreIOFailure);
            okay = NO;
            break;
        }
        if (![self sessionIsLive:session error:error]) {
            okay = NO;
            break;
        }
    }
    if (okay) {
        uint8_t extra = 0;
        ssize_t extraCount = pread(sourceFD, &extra, 1, (off_t)copied);
        struct stat finalSource;
        if (extraCount != 0 || fstat(sourceFD, &finalSource) != 0 ||
            finalSource.st_dev != sourceStatus.st_dev || finalSource.st_ino != sourceStatus.st_ino ||
            finalSource.st_size != sourceStatus.st_size || finalSource.st_nlink != 1 ||
            finalSource.st_mtimespec.tv_sec != sourceStatus.st_mtimespec.tv_sec ||
            finalSource.st_mtimespec.tv_nsec != sourceStatus.st_mtimespec.tv_nsec ||
            finalSource.st_ctimespec.tv_sec != sourceStatus.st_ctimespec.tv_sec ||
            finalSource.st_ctimespec.tv_nsec != sourceStatus.st_ctimespec.tv_nsec) {
            AQStoreFail(error, AQStoreSourceDenied);
            okay = NO;
        }
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (okay) {
        CC_SHA256_Final(digest, &context);
        NSMutableString *digestText = [NSMutableString stringWithCapacity:64];
        for (NSUInteger index = 0; index < sizeof(digest); ++index) [digestText appendFormat:@"%02x", digest[index]];
        if (![digestText isEqual:member.sha256]) {
            AQStoreFail(error, AQStoreIntegrityFailure);
            okay = NO;
        }
    }
    if (okay) {
        struct timespec times[2] = {sourceStatus.st_atimespec, sourceStatus.st_mtimespec};
        if (fchmod(targetFD, 0400) != 0 || futimens(targetFD, times) != 0 || !AQFullSync(targetFD, YES)) {
            AQStoreFail(error, AQStoreIOFailure);
            okay = NO;
        }
    }
    if (close(targetFD) != 0) okay = NO;
    if (okay) {
        int readback = openat(parentFD, leaf.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        if (readback < 0 || !AQHashMatchesDescriptor(readback, member.size, member.sha256, error)) {
            if (readback >= 0) close(readback);
            close(parentFD);
            return NO;
        }
        struct stat readStatus;
        if (fstat(readback, &readStatus) != 0 || readStatus.st_nlink != 1 || (readStatus.st_mode & 0777) != 0400) {
            close(readback);
            close(parentFD);
            return AQStoreFail(error, AQStoreIntegrityFailure);
        }
        close(readback);
        if (!AQDirectorySync(parentFD)) {
            close(parentFD);
            return AQStoreFail(error, AQStoreIOFailure);
        }
    }
    close(parentFD);
    return okay;
}

- (BOOL)verifyDirectoryFD:(int)directoryFD prefix:(NSString *)prefix
             expectedFiles:(NSDictionary<NSString *, AQStoreMember *> *)expectedFiles
              expectedDirs:(NSSet<NSString *> *)expectedDirs
                 seenFiles:(NSMutableSet<NSString *> *)seenFiles
            entryIdentities:(NSMutableDictionary<NSString *, NSDictionary *> *)entryIdentities
                       error:(NSError **)error {
    BOOL listed = NO;
    NSArray<NSString *> *names = AQSortedNamesInDirectory(directoryFD, &listed);
    if (!listed) return AQStoreFail(error, AQStoreIOFailure);
    for (NSString *name in names) {
        NSString *child = prefix.length == 0 ? name : [prefix stringByAppendingFormat:@"/%@", name];
        AQStoreMember *member = expectedFiles[child];
        if (member != nil) {
            struct stat status;
            if (fstatat(directoryFD, name.fileSystemRepresentation, &status, AT_SYMLINK_NOFOLLOW) != 0 ||
                !S_ISREG(status.st_mode) || status.st_nlink != 1 || status.st_size < 0 ||
                (uint64_t)status.st_size != member.size) return AQStoreFail(error, AQStoreIntegrityFailure);
            if (entryIdentities != nil) {
                entryIdentities[child] = @{@"kind": @"file", @"device": @(status.st_dev),
                    @"inode": @(status.st_ino), @"mode": @(status.st_mode),
                    @"links": @(status.st_nlink), @"size": @(status.st_size)};
            }
            int fileFD = openat(directoryFD, name.fileSystemRepresentation,
                                O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
            if (fileFD < 0 || !AQHashMatchesDescriptor(fileFD, member.size, member.sha256, error)) {
                if (fileFD >= 0) close(fileFD);
                return NO;
            }
            close(fileFD);
            [seenFiles addObject:child];
            continue;
        }
        if (![expectedDirs containsObject:child]) return AQStoreFail(error, AQStoreIntegrityFailure);
        struct stat status;
        if (fstatat(directoryFD, name.fileSystemRepresentation, &status, AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISDIR(status.st_mode)) return AQStoreFail(error, AQStoreIntegrityFailure);
        if (entryIdentities != nil) {
            entryIdentities[child] = @{@"kind": @"directory", @"device": @(status.st_dev),
                @"inode": @(status.st_ino), @"mode": @(status.st_mode),
                @"links": @(status.st_nlink), @"size": @(status.st_size)};
        }
        int childFD = openat(directoryFD, name.fileSystemRepresentation,
                             O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (childFD < 0) return AQStoreFail(error, AQStoreIOFailure);
        BOOL valid = [self verifyDirectoryFD:childFD prefix:child expectedFiles:expectedFiles
                               expectedDirs:expectedDirs seenFiles:seenFiles
                            entryIdentities:entryIdentities error:error];
        close(childFD);
        if (!valid) return NO;
    }
    return YES;
}

- (BOOL)verifySnapshotNamed:(NSString *)snapshotName members:(NSArray<AQStoreMember *> *)members
                       error:(NSError **)error {
    return [self verifySnapshotNamed:snapshotName members:members entryIdentities:nil error:error];
}

- (BOOL)verifySnapshotNamed:(NSString *)snapshotName members:(NSArray<AQStoreMember *> *)members
            entryIdentities:(NSMutableDictionary<NSString *, NSDictionary *> *)entryIdentities
                       error:(NSError **)error {
    int snapshotFD = openat(_rootFD, snapshotName.fileSystemRepresentation,
                            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (snapshotFD < 0) return AQStoreFail(error, AQStoreIntegrityFailure);
    struct stat rootStatus;
    if (fstat(snapshotFD, &rootStatus) != 0 || !S_ISDIR(rootStatus.st_mode)) {
        close(snapshotFD);
        return AQStoreFail(error, AQStoreIntegrityFailure);
    }
    if (entryIdentities != nil) {
        entryIdentities[@""] = @{@"kind": @"directory", @"device": @(rootStatus.st_dev),
            @"inode": @(rootStatus.st_ino), @"mode": @(rootStatus.st_mode),
            @"links": @(rootStatus.st_nlink), @"size": @(rootStatus.st_size)};
    }
    NSMutableDictionary<NSString *, AQStoreMember *> *expectedFiles = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *expectedDirs = [NSMutableSet set];
    for (AQStoreMember *member in members) {
        expectedFiles[member.path] = member;
        [expectedDirs addObjectsFromArray:AQParentDirectories(member.path)];
    }
    NSMutableSet<NSString *> *seenFiles = [NSMutableSet set];
    BOOL valid = [self verifyDirectoryFD:snapshotFD prefix:@"" expectedFiles:expectedFiles
                            expectedDirs:expectedDirs seenFiles:seenFiles
                         entryIdentities:entryIdentities error:error];
    close(snapshotFD);
    if (!valid) return NO;
    if (![seenFiles isEqualToSet:[NSSet setWithArray:expectedFiles.allKeys]]) {
        return AQStoreFail(error, AQStoreIntegrityFailure);
    }
    return YES;
}

- (NSDictionary *)stageRequest:(NSDictionary *)request
                     sourceFDs:(NSDictionary<NSString *, NSNumber *> *)sourceFDs
                         error:(NSError **)error {
    if (error) *error = nil;
    if (![request isKindOfClass:[NSDictionary class]] ||
        ![request[@"session_id"] isKindOfClass:[NSString class]]) {
        AQStoreFail(error, AQStoreInvalidInput);
        return nil;
    }
    AQStoreSession *session = nil;
    NSArray<AQStoreMember *> *members = nil;
    @synchronized(_storeLock) {
        session = _sessions[(NSString *)request[@"session_id"]];
        members = session.members;
    }
    if (session == nil) {
        AQStoreFail(error, AQStoreInvalidState);
        return nil;
    }
    NSDictionary<NSString *, NSNumber *> *duplicates = [self duplicateSourceDescriptors:sourceFDs
                                                                                 members:members error:error];
    if (duplicates == nil) return nil;
    uint64_t total = 0;
    for (AQStoreMember *member in members) {
        if (!AQStoreAddBytes(total, member.size, &total)) {
            AQCloseDescriptors(duplicates);
            AQStoreFail(error, AQStoreCapacityDenied);
            return nil;
        }
    }
    if (![self acceptRequest:request session:&session operation:@"stage" preflight:nil error:error]) {
        AQCloseDescriptors(duplicates);
        return nil;
    }
    if (![self deadlineAllowsForSession:session error:error] ||
        ![self capacityAllows:total session:session error:error]) {
        AQCloseDescriptors(duplicates);
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    NSString *pendingName = AQRandomName(@"pending-");
    NSString *snapshotName = AQRandomName(@"snapshot-");
    BOOL intentRecorded = NO;
    @synchronized(_storeLock) {
        session.pendingName = pendingName;
        session.snapshotName = snapshotName;
        intentRecorded = [self appendEvent:@"stage_intent" session:session error:error];
    }
    if (!intentRecorded) {
        AQCloseDescriptors(duplicates);
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    if (![self boundaryAllows:@"before_payload_mkdir"]) {
        AQCloseDescriptors(duplicates);
        [self finishOperationForSession:session.sessionID];
        AQStoreFail(error, AQStoreIOFailure);
        return nil;
    }
    int pendingFD = -1;
    if (mkdirat(_rootFD, pendingName.fileSystemRepresentation, 0700) != 0 ||
        !AQDirectorySync(_rootFD)) {
        AQCloseDescriptors(duplicates);
        [self finishOperationForSession:session.sessionID];
        AQStoreFail(error, AQStoreIOFailure);
        return nil;
    }
    pendingFD = openat(_rootFD, pendingName.fileSystemRepresentation,
                       O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (pendingFD < 0 || ![self boundaryAllows:@"after_payload_mkdir"]) {
        if (pendingFD >= 0) close(pendingFD);
        AQCloseDescriptors(duplicates);
        [self finishOperationForSession:session.sessionID];
        AQStoreFail(error, AQStoreIOFailure);
        return nil;
    }
    BOOL copied = YES;
    uint64_t remaining = total;
    for (AQStoreMember *member in members) {
        int sourceFD = duplicates[member.path].intValue;
        if (![self copyMember:member sourceFD:sourceFD stageFD:pendingFD remaining:&remaining
                      session:session error:error]) {
            copied = NO;
            break;
        }
    }
    if (copied && !AQDirectorySync(pendingFD)) {
        AQStoreFail(error, AQStoreIOFailure);
        copied = NO;
    }
    if (copied && ![self verifySnapshotNamed:pendingName members:members error:error]) copied = NO;
    if (copied && (![self boundaryAllows:@"before_publish"] ||
                   ![self sessionIsLive:session error:error])) copied = NO;
    if (copied) {
        if (renameatx_np(_rootFD, pendingName.fileSystemRepresentation, _rootFD,
                         snapshotName.fileSystemRepresentation, RENAME_EXCL) != 0 ||
            !AQDirectorySync(_rootFD)) {
            AQStoreFail(error, AQStoreIOFailure);
            copied = NO;
        } else if (![self verifySnapshotNamed:snapshotName members:members error:error] ||
                   ![self sessionIsLive:session error:error]) {
            copied = NO;
        }
    }
    if (pendingFD >= 0) close(pendingFD);
        AQCloseDescriptors(duplicates);
    if (!copied) {
        NSString *lastError = [NSString stringWithFormat:@"%ld", (long)(error && *error ? (*error).code : AQStoreIOFailure)];
        @synchronized(_storeLock) {
            if (!session.revoked && [self currentTicks] < session.deadlineTicks) {
                [self markSession:session state:@"blocked_retained" effectState:@"retained"
                        lastError:lastError event:@"stage_blocked" error:NULL];
            } else if (!session.revoked) {
                session.state = @"blocked_retained";
                session.effectState = @"retained";
                session.lastError = lastError;
            }
        }
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    BOOL eligibleRecorded = NO;
    @synchronized(_storeLock) {
        if ([self sessionIsLive:session error:error]) {
            session.pendingName = @"";
            session.generation += 1;
            eligibleRecorded = [self markSession:session state:@"eligible" effectState:@"none" lastError:@""
                                            event:@"stage_eligible" error:error];
        }
    }
    if (!eligibleRecorded) {
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    [self finishOperationForSession:session.sessionID];
    return @{@"session_id": session.sessionID, @"state": @"eligible", @"generation": @(session.generation),
             @"snapshot_id": snapshotName, @"members": @(members.count)};
}

- (NSDictionary *)eligibilityForRequest:(NSDictionary *)request error:(NSError **)error {
    if (error) *error = nil;
    AQStoreSession *session = nil;
    if (![self acceptRequest:request session:&session operation:@"eligibility" preflight:nil error:error]) return nil;
    BOOL valid = [self sessionIsLive:session error:error];
    if (valid) valid = [self verifySnapshotNamed:session.snapshotName members:session.members error:error];
    if (!valid) {
        @synchronized(_storeLock) {
            if (!session.revoked && [self currentTicks] < session.deadlineTicks) {
                [self markSession:session state:@"blocked_retained" effectState:@"retained" lastError:@"eligibility"
                            event:@"eligibility_failed" error:NULL];
            } else if (!session.revoked) {
                session.state = @"blocked_retained";
                session.effectState = @"retained";
                session.lastError = @"eligibility";
            }
        }
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    BOOL eventRecorded = NO;
    @synchronized(_storeLock) {
        if ([self sessionIsLive:session error:error]) {
            eventRecorded = [self markSession:session state:@"eligible" effectState:@"none" lastError:@""
                                        event:@"eligibility_verified" error:error];
        }
    }
    if (!eventRecorded) {
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    [self finishOperationForSession:session.sessionID];
    return @{@"session_id": session.sessionID, @"state": @"eligible", @"generation": @(session.generation),
             @"manifest_sha256": session.manifestSHA256, @"members": @(session.members.count)};
}

- (int)exportPipeForRequest:(NSDictionary *)request error:(NSError **)error {
    if (error) *error = nil;
    AQStoreSession *session = nil;
    __block NSData *headerData = nil;
    if (![self acceptRequest:request session:&session operation:@"export"
        preflight:^BOOL(AQStoreSession *candidate, NSError **preflightError) {
            NSMutableArray<NSDictionary *> *headerMembers =
                [NSMutableArray arrayWithCapacity:candidate.members.count];
            for (AQStoreMember *member in candidate.members) {
                [headerMembers addObject:@{@"path": member.path, @"size": @(member.size),
                                           @"sha256": member.sha256}];
            }
            headerData = AQStoreCanonicalExportHeader(candidate.sessionID,
                candidate.manifestSHA256, candidate.generation, headerMembers, preflightError);
            return headerData != nil;
        } error:error]) return -1;
    if (![self sessionIsLive:session error:error] ||
        ![self verifySnapshotNamed:session.snapshotName members:session.members error:error]) {
        @synchronized(_storeLock) {
            if ([self failureMayBeRetainedForSession:session]) {
                [self markSession:session state:@"blocked_retained" effectState:@"retained" lastError:@"export"
                            event:@"export_failed" error:NULL];
            }
        }
        [self finishOperationForSession:session.sessionID];
        return -1;
    }
    if (headerData == nil) {
        [self finishOperationForSession:session.sessionID];
        return -1;
    }
    int descriptors[2] = {-1, -1};
    if (pipe(descriptors) != 0) {
        [self finishOperationForSession:session.sessionID];
        AQStoreFail(error, AQStoreIOFailure);
        return -1;
    }
    int readFD = descriptors[0];
    int writeFD = descriptors[1];
    int readFlags = fcntl(readFD, F_GETFL);
    int writeFlags = fcntl(writeFD, F_GETFL);
    if (readFlags < 0 || writeFlags < 0 || fcntl(readFD, F_SETFL, readFlags | O_NONBLOCK) != 0 ||
        fcntl(writeFD, F_SETFL, writeFlags | O_NONBLOCK) != 0 ||
        fcntl(readFD, F_SETFD, FD_CLOEXEC) != 0 || fcntl(writeFD, F_SETFD, FD_CLOEXEC) != 0 ||
        fcntl(writeFD, F_SETNOSIGPIPE, 1) != 0) {
        close(readFD);
        close(writeFD);
        [self finishOperationForSession:session.sessionID];
        AQStoreFail(error, AQStoreIOFailure);
        return -1;
    }
    NSData *prefixData = [AQFramePrefix dataUsingEncoding:NSASCIIStringEncoding];
    NSData *suffixData = [AQFrameSuffix dataUsingEncoding:NSASCIIStringEncoding];
    uint64_t headerSize = (uint64_t)headerData.length;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CC_SHA256_CTX context;
        BOOL okay = CC_SHA256_Init(&context) == 1;
        BOOL (^stillLive)(void) = ^BOOL { return [self sessionIsLive:session error:NULL]; };
        uint8_t headerLength[8];
        AQBigEndian64(headerSize, headerLength);
        if (okay) {
            CC_SHA256_Update(&context, prefixData.bytes, (CC_LONG)prefixData.length);
            CC_SHA256_Update(&context, headerLength, sizeof(headerLength));
            CC_SHA256_Update(&context, headerData.bytes, (CC_LONG)headerData.length);
            okay = AQWritePipeBytes(writeFD, prefixData.bytes, prefixData.length, stillLive) &&
                AQWritePipeBytes(writeFD, headerLength, sizeof(headerLength), stillLive) &&
                AQWritePipeBytes(writeFD, headerData.bytes, headerData.length, stillLive);
        }
        int snapshotFD = -1;
        if (okay) {
            snapshotFD = openat(_rootFD, session.snapshotName.fileSystemRepresentation,
                                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (snapshotFD < 0) okay = NO;
        }
        NSMutableData *buffer = [NSMutableData dataWithLength:AQStoreIOChunkSize];
        for (AQStoreMember *member in session.members) {
            if (!okay) break;
            if (![self boundaryAllows:@"before_export_member"]) {
                okay = NO;
                break;
            }
            NSArray<NSString *> *components = [member.path componentsSeparatedByString:@"/"];
            int parentFD = AQOpenSubdirectory(snapshotFD, components, components.count - 1);
            int fileFD = parentFD < 0 ? -1 : openat(parentFD, components.lastObject.fileSystemRepresentation,
                                                   O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
            if (parentFD >= 0) close(parentFD);
            struct stat status;
            if (fileFD < 0 || fstat(fileFD, &status) != 0 || !S_ISREG(status.st_mode) || status.st_nlink != 1 ||
                status.st_size < 0 || (uint64_t)status.st_size != member.size) {
                if (fileFD >= 0) close(fileFD);
                okay = NO;
                break;
            }
            CC_SHA256_CTX memberContext;
            BOOL memberOkay = CC_SHA256_Init(&memberContext) == 1;
            uint64_t offset = 0;
            while (memberOkay && offset < member.size) {
                if (!stillLive()) {
                    memberOkay = NO;
                    break;
                }
                uint64_t left = member.size - offset;
                size_t requested = left > AQStoreIOChunkSize ? AQStoreIOChunkSize : (size_t)left;
                ssize_t count = pread(fileFD, buffer.mutableBytes, requested, (off_t)offset);
                if (count < 0 && errno == EINTR) continue;
                if (count <= 0) {
                    memberOkay = NO;
                    break;
                }
                CC_SHA256_Update(&memberContext, buffer.bytes, (CC_LONG)count);
                CC_SHA256_Update(&context, buffer.bytes, (CC_LONG)count);
                if (!AQWritePipeBytes(writeFD, buffer.bytes, (size_t)count, stillLive)) {
                    memberOkay = NO;
                    break;
                }
                offset += (uint64_t)count;
            }
            uint8_t extra = 0;
            struct stat finalStatus;
            if (memberOkay && (pread(fileFD, &extra, 1, (off_t)offset) != 0 || fstat(fileFD, &finalStatus) != 0 ||
                               finalStatus.st_size != status.st_size || finalStatus.st_nlink != 1)) {
                memberOkay = NO;
            }
            unsigned char memberDigest[CC_SHA256_DIGEST_LENGTH];
            if (memberOkay) {
                CC_SHA256_Final(memberDigest, &memberContext);
                NSMutableString *digestText = [NSMutableString stringWithCapacity:64];
                for (NSUInteger index = 0; index < sizeof(memberDigest); ++index) {
                    [digestText appendFormat:@"%02x", memberDigest[index]];
                }
                memberOkay = [digestText isEqual:member.sha256];
            }
            close(fileFD);
            if (!memberOkay) okay = NO;
        }
        if (snapshotFD >= 0) close(snapshotFD);
        unsigned char streamDigest[CC_SHA256_DIGEST_LENGTH];
        if (okay) CC_SHA256_Final(streamDigest, &context);
        if (okay) okay = AQWritePipeBytes(writeFD, suffixData.bytes, suffixData.length, stillLive);
        if (okay) okay = AQWritePipeBytes(writeFD, streamDigest, sizeof(streamDigest), stillLive);
        if (okay) {
            [self markSession:session state:@"eligible" effectState:@"none" lastError:@""
                        event:@"export_completed" error:NULL];
        } else if ([self failureMayBeRetainedForSession:session]) {
            [self markSession:session state:@"blocked_retained" effectState:@"retained" lastError:@"export"
                        event:@"export_failed" error:NULL];
        }
        [self finishOperationForSession:session.sessionID];
        close(writeFD);
    });
    return readFD;
}

- (void)revokeSession:(NSString *)sessionID reason:(NSString *)reason {
    if (![sessionID isKindOfClass:[NSString class]]) return;
    AQStoreSession *session = nil;
    @synchronized(_storeLock) {
        session = _sessions[sessionID];
        if (session == nil || session.revoked) return;
        session.revoked = YES;
        session.state = @"revoked";
        session.effectState = @"retained";
        session.lastError = ([reason isKindOfClass:[NSString class]] && reason.length <= 128) ? reason : @"revoked";
        [self appendEvent:@"revoked" session:session error:NULL];
    }
}

- (BOOL)recordCleanupAttempt:(NSString *)entry session:(AQStoreSession *)session error:(NSError **)error {
    @synchronized(_storeLock) {
        if (session.revoked) return AQStoreFail(error, AQStoreRevoked);
        if ([session.attemptedEntries containsObject:entry]) return AQStoreFail(error, AQStoreInvalidState);
        NSMutableArray<NSString *> *attempted = [session.attemptedEntries mutableCopy];
        [attempted addObject:entry];
        session.attemptedEntries = [[attempted sortedArrayUsingSelector:@selector(compare:)] copy];
        session.effectState = @"pending";
        return [self appendEvent:@"cleanup_attempt" session:session error:error];
    }
}

- (NSDictionary *)cleanupRequest:(NSDictionary *)request error:(NSError **)error {
    if (error) *error = nil;
    AQStoreSession *session = nil;
    if (![self acceptRequest:request session:&session operation:@"cleanup" preflight:nil error:error]) return nil;
    if (![self sessionIsLive:session error:error]) {
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    NSMutableDictionary<NSString *, NSDictionary *> *entryIdentities = [NSMutableDictionary dictionary];
    if (session.attemptedEntries.count != 0 ||
        ![self verifySnapshotNamed:session.snapshotName members:session.members
                    entryIdentities:entryIdentities error:error]) {
        @synchronized(_storeLock) {
            if (!session.revoked && [self currentTicks] < session.deadlineTicks) {
                [self markSession:session state:@"eligible" effectState:@"retained" lastError:@"cleanup_preflight"
                            event:@"cleanup_failed" error:NULL];
            }
        }
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    NSMutableSet<NSString *> *directories = [NSMutableSet set];
    for (AQStoreMember *member in session.members) {
        [directories addObjectsFromArray:AQParentDirectories(member.path)];
    }
    NSArray<NSString *> *sortedDirectories = [directories.allObjects sortedArrayUsingComparator:^
        NSComparisonResult(NSString *left, NSString *right) {
            NSUInteger leftDepth = [left componentsSeparatedByString:@"/"].count;
            NSUInteger rightDepth = [right componentsSeparatedByString:@"/"].count;
            if (leftDepth != rightDepth) return leftDepth > rightDepth ? NSOrderedAscending : NSOrderedDescending;
            return [left compare:right];
        }];
    BOOL okay = YES;
    BOOL replacementRetained = NO;
    BOOL (^beforeUnlink)(NSString *) = ^BOOL(NSString *entry) {
        return [self boundaryAllows:[@"before_cleanup_unlink:" stringByAppendingString:entry]];
    };
    for (AQStoreMember *member in session.members) {
        if (![self sessionIsLive:session error:error]) {
            okay = NO;
            break;
        }
        NSString *attempt = [@"file:" stringByAppendingString:member.path];
        if (![self recordCleanupAttempt:attempt session:session error:error]) {
            okay = NO;
            break;
        }
        if (!AQRemoveSnapshotEntry(_rootFD, session.snapshotName, member.path, NO,
                                   entryIdentities[member.path], member, beforeUnlink, error)) {
            replacementRetained = error != NULL && *error != nil && (*error).code == AQStoreIntegrityFailure;
            okay = NO;
            break;
        }
        if (![self boundaryAllows:@"after_unlink"]) {
            @synchronized(_storeLock) {
                session.state = @"blocked_retained";
                session.effectState = @"uncertain";
                session.lastError = @"cleanup_unlink";
            }
            AQStoreFail(error, AQStoreIOFailure);
            okay = NO;
            break;
        }
        if (![self markSession:session state:@"eligible" effectState:@"cleanup_progress" lastError:@""
                         event:@"cleanup_member_done" error:error]) {
            okay = NO;
            break;
        }
    }
    for (NSString *directory in sortedDirectories) {
        if (!okay || ![self sessionIsLive:session error:error]) {
            okay = NO;
            break;
        }
        NSString *attempt = [@"directory:" stringByAppendingString:directory];
        if (![self recordCleanupAttempt:attempt session:session error:error]) {
            okay = NO;
            break;
        }
        if (!AQRemoveSnapshotEntry(_rootFD, session.snapshotName, directory, YES,
                                   entryIdentities[directory], nil, beforeUnlink, error)) {
            replacementRetained = error != NULL && *error != nil && (*error).code == AQStoreIntegrityFailure;
            okay = NO;
            break;
        }
        if (![self markSession:session state:@"eligible" effectState:@"cleanup_progress" lastError:@""
                         event:@"cleanup_member_done" error:error]) {
            okay = NO;
            break;
        }
    }
    if (okay) {
        NSString *attempt = [@"root:" stringByAppendingString:session.snapshotName];
        if (![self recordCleanupAttempt:attempt session:session error:error]) {
            okay = NO;
        } else if (!AQRemoveSnapshotEntry(_rootFD, session.snapshotName, @"", YES,
                                          entryIdentities[@""], nil, beforeUnlink, error)) {
            replacementRetained = error != NULL && *error != nil && (*error).code == AQStoreIntegrityFailure;
            okay = NO;
        }
    }
    if (!okay) {
        @synchronized(_storeLock) {
            if (replacementRetained && !session.revoked) {
                [self markSession:session state:@"blocked_retained" effectState:@"retained"
                        lastError:@"cleanup_replacement" event:@"cleanup_failed" error:NULL];
            } else if (!session.revoked && [session.effectState isEqual:@"pending"]) {
                session.state = @"blocked_retained";
                session.effectState = @"uncertain";
                session.lastError = @"cleanup_effect";
            }
        }
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    if (![self markSession:session state:@"cleaned" effectState:@"none" lastError:@""
                     event:@"cleanup_complete" error:error]) {
        [self finishOperationForSession:session.sessionID];
        return nil;
    }
    [self finishOperationForSession:session.sessionID];
    return @{@"session_id": session.sessionID, @"state": @"cleaned", @"generation": @(session.generation),
             @"cleanup_complete": @YES, @"attempted_members": @(session.attemptedEntries.count)};
}

@end
