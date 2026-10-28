#import "AQServiceProtocol.h"

#import "AQContract.h"
#import "AQJSON.h"
#import "AQSecurity.h"
#import "AQStore.h"
#import "AQTiming.h"

#include <fcntl.h>
#include <mach/mach_time.h>
#include <sys/stat.h>
#include <unistd.h>
#import <CommonCrypto/CommonDigest.h>

NSString *const AQServiceErrorDomain = @"com.argusromtoolkit.fixture-staging.service";

#ifdef AQ_SERVICE_TESTING
static BOOL AQServiceSyntheticMutationsAllowedForTesting = YES;

void AQServiceSetSyntheticMutationsAllowedForTesting(BOOL allowed) {
    @synchronized([AQServiceSessionCore class]) {
        AQServiceSyntheticMutationsAllowedForTesting = allowed;
    }
}

static BOOL AQServiceSyntheticMutationsEnabled(void) {
    @synchronized([AQServiceSessionCore class]) {
        return AQServiceSyntheticMutationsAllowedForTesting;
    }
}
#endif

/* This build has no approved isolation evidence, so production mutations stay
 * blocked before payload loading or operation dispatch. Only synthetic test
 * builds may explicitly enable the protocol path. */
static const BOOL AQServiceProductionMutationsBlocked = YES;

static BOOL AQServiceOperationRequiresProductionIsolation(NSString *operation) {
    return [operation isEqual:@"admit"] || [operation isEqual:@"stage"] ||
           [operation isEqual:@"revoke"] || [operation isEqual:@"cleanup"] ||
           [operation isEqual:@"export"];
}

static BOOL AQServiceProductionMutationAllowed(NSString *operation) {
    if (!AQServiceOperationRequiresProductionIsolation(operation) ||
        !AQServiceProductionMutationsBlocked) return YES;
#ifdef AQ_SERVICE_TESTING
    return AQServiceSyntheticMutationsEnabled();
#else
    return NO;
#endif
}

static BOOL AQServiceRecoveryIsRestartBlocked(NSDictionary *classification) {
    if (![classification isKindOfClass:NSDictionary.class] ||
        ![classification[@"state"] isEqual:@"blocked_retained"] ||
        ![classification[@"reason"] isEqual:@"restart_requires_fresh_authority"]) return NO;
    NSNumber *sessions = classification[@"sessions"];
    NSNumber *freshAdmissionAvailable = classification[@"fresh_admission_available"];
    return [sessions isKindOfClass:NSNumber.class] && sessions.unsignedLongLongValue > 0 &&
           [freshAdmissionAvailable isKindOfClass:NSNumber.class];
}

static BOOL AQServiceRecoveryAllowsFreshAdmission(NSDictionary *classification) {
    if (![classification isKindOfClass:NSDictionary.class]) return NO;
    if ([classification[@"state"] isEqual:@"clean"]) return YES;
    return AQServiceRecoveryIsRestartBlocked(classification) &&
           [classification[@"fresh_admission_available"] boolValue];
}

static BOOL AQServiceRecoveryFreshAdmissionConsumed(NSDictionary *classification) {
    return AQServiceRecoveryIsRestartBlocked(classification) &&
           ![classification[@"fresh_admission_available"] boolValue];
}

static NSDictionary *AQServiceAdmitWithReceiptReservation(
    id<AQServiceStore> store, NSString *sessionID, NSArray<NSString *> *operations,
    NSDictionary *manifest, NSDictionary *authority, BOOL *capacityDenied, NSError **error) {
    if (capacityDenied != NULL) *capacityDenied = NO;
    BOOL reservationCreated = NO;
    if ([operations containsObject:@"export"] &&
        ![store reserveReceiptCapacityForSessionID:sessionID created:&reservationCreated
                                             error:error]) {
        if (capacityDenied != NULL) *capacityDenied = YES;
        return nil;
    }
    NSDictionary *admitted = [store admitManifest:manifest authority:authority error:error];
    if (admitted == nil && reservationCreated) {
    NSError *releaseError = nil;
    if (![store releaseReceiptCapacityForSessionID:sessionID error:&releaseError]) {
        // The durable reservation is unresolved. Do not report this as an
        // ordinary admission failure that callers may safely retry.
        if (error != NULL) *error = AQServiceError(AQServiceUnsupportedExclusivity);
    }
    }
    return admitted;
}

#ifdef AQ_SERVICE_TESTING
BOOL AQServiceRecoveryAllowsFreshAdmissionForTesting(NSDictionary *classification) {
    return AQServiceRecoveryAllowsFreshAdmission(classification);
}
NSDictionary *AQServiceAdmitWithReceiptReservationForTesting(
    id<AQServiceStore> store, NSString *sessionID, NSArray<NSString *> *operations,
    NSDictionary *manifest, NSDictionary *authority, BOOL *capacityDenied, NSError **error) {
    return AQServiceAdmitWithReceiptReservation(store, sessionID, operations, manifest,
        authority, capacityDenied, error);
}
#endif
const NSUInteger AQServiceMaximumRequestBytes = 64 * 1024;
const NSUInteger AQServiceMaximumReceiptBytes = 256 * 1024;
const NSUInteger AQServiceMaximumDocumentBytes = 64 * 1024;
const NSUInteger AQServiceMaximumDocuments = 128;
const NSUInteger AQServiceMaximumSourceDescriptors = 1024;
const uint64_t AQServiceMaximumOperationNanoseconds = 3600ULL * NSEC_PER_SEC;

dispatch_queue_t AQServiceSerialPeerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create(
            "com.argusromtoolkit.fixture-staging.service.peers", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static const NSUInteger AQServiceMaximumConnections = 32;
static const NSUInteger AQServiceMaximumSignatureBytes = 256;
static const NSUInteger AQServiceMaximumTotalDocumentBytes = 8 * 1024 * 1024;

static NSString *const AQServiceRequestDigestDomain = @"argus.fixture-staging.request.v1";
static NSString *const AQServiceRequestIDDomain = @"argus.fixture-staging.request-id.v1";
static NSString *const AQServiceStoreEpochDomain = @"argus.fixture-staging.store-epoch.v1";
static NSString *const AQServiceHelloNonceDomain = @"argus.fixture-staging.hello-nonce.v1";

static BOOL AQServiceFail(NSError **error, AQServiceErrorCode code) {
    if (error != NULL) *error = AQServiceError(code);
    return NO;
}

/** AQStore still requires its numeric, non-secret session epoch. The service's
 * authoritative epoch is the opaque boot identity; this conversion supplies a
 * stable numeric projection without changing AQStore's field or clock rules. */
static uint64_t AQServiceStoreEpochForBootIdentity(NSString *bootIdentity) {
    NSString *digest = AQDigest(AQServiceStoreEpochDomain, bootIdentity, NULL);
    if (digest.length < 16) return 1;
    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[digest substringToIndex:16]];
    if (![scanner scanHexLongLong:&value]) return 1;
    value &= INT64_MAX;
    return value == 0 ? 1 : (uint64_t)value;
}

NSError *AQServiceError(AQServiceErrorCode code) {
    NSString *description = nil;
    switch (code) {
        case AQServiceInvalidRequest: description = @"INVALID_REQUEST"; break;
        case AQServiceLimitExceeded: description = @"LIMIT_EXCEEDED"; break;
        case AQServiceUnsupportedVersion: description = @"UNSUPPORTED_VERSION"; break;
        case AQServiceUnsupportedExclusivity:
            description = @"BLOCKED_UNSUPPORTED_EXCLUSIVITY"; break;
        case AQServiceUnauthenticatedConnection: description = @"UNAUTHENTICATED_CONNECTION"; break;
        case AQServiceConsentRequired: description = @"OWNER_CONSENT_REQUIRED"; break;
        case AQServiceConsentDenied: description = @"OWNER_CONSENT_DENIED"; break;
        case AQServiceConsentExpired: description = @"OWNER_CONSENT_EXPIRED"; break;
        case AQServiceBindingMismatch: description = @"SESSION_BINDING_MISMATCH"; break;
        case AQServiceReplayRejected: description = @"REPLAY_REJECTED"; break;
        case AQServiceOperationDenied: description = @"OPERATION_NOT_AUTHORIZED"; break;
        case AQServiceCoverageDenied: description = @"PLAN_COVERAGE_DENIED"; break;
        case AQServiceReferenceDenied: description = @"ORACLE_REFERENCE_UNVERIFIED"; break;
        case AQServiceStoreDenied: description = @"STORE_DENIED"; break;
        case AQServiceReceiptCapacityDenied: description = @"RECEIPT_CAPACITY_EXHAUSTED"; break;
        case AQServiceUnsupportedInstallation: description = @"UNSUPPORTED_INSTALLATION"; break;
        case AQServiceInternalFailure: description = @"INTERNAL_FAILURE"; break;
    }
    return [NSError errorWithDomain:AQServiceErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL AQServiceString(id value, NSUInteger minimum, NSUInteger maximum) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *string = value;
    if (string.length < minimum || string.length > maximum) return NO;
    return [string rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

static BOOL AQServiceToken(id value) {
    if (!AQServiceString(value, 1, 256)) return NO;
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"]; });
    return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static BOOL AQServiceDigestString(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 64) return NO;
    static NSCharacterSet *hex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ hex = [NSCharacterSet characterSetWithCharactersInString:
        @"0123456789abcdef"]; });
    return [value rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound;
}

static BOOL AQServiceUnsignedInteger(id value, uint64_t minimum, uint64_t maximum,
                                     uint64_t *result) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    long long integer = [value longLongValue];
    if (integer < 0 || (uint64_t)integer < minimum || (uint64_t)integer > maximum) return NO;
    if (result != NULL) *result = (uint64_t)integer;
    return YES;
}

static BOOL AQServiceBoolean(id value, BOOL *result) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) return NO;
    if (result != NULL) *result = [value boolValue];
    return YES;
}

static BOOL AQServiceExactKeys(NSDictionary *dictionary, NSArray<NSString *> *keys) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return NO;
    for (id key in dictionary.allKeys) {
        if (![key isKindOfClass:NSString.class]) return NO;
    }
    return [[NSSet setWithArray:dictionary.allKeys] isEqualToSet:[NSSet setWithArray:keys]];
}

/** SHA-256 of exact bytes, without JSON canonicalization. Owner authorization
 * uses the same canonical-JSON byte digest as the authorization record, so a
 * substituted attachment cannot remain valid by carrying the earlier digest. */
static NSString *AQServiceExactBytesSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (![data isKindOfClass:NSData.class] || data.length > UINT32_MAX) return nil;
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    char hex[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) {
        snprintf(hex + 2 * index, 3, "%02x", digest[index]);
    }
    return [NSString stringWithUTF8String:hex];
}

static NSString *AQServiceHelloNonce(NSString *installationIdentity,
                                     NSString *serviceBootIdentity,
                                     NSString *brokerRevision,
                                     NSString *ownerKeyIdentifier,
                                     uint64_t sequence,
                                     NSString *authorizationSHA256) {
    return AQDigest(AQServiceHelloNonceDomain, @{
        @"installation_id": installationIdentity,
        @"service_boot_id": serviceBootIdentity,
        @"broker_revision": brokerRevision,
        @"owner_key_id": ownerKeyIdentifier,
        @"sequence": @(sequence),
        @"authorization_sha256": authorizationSHA256,
    }, NULL);
}

static BOOL AQServiceStringArray(id value, BOOL allowEmpty,
                                 NSArray<NSString *> * _Nullable * _Nullable result) {
    if (![value isKindOfClass:NSArray.class] || (!allowEmpty && [value count] == 0) ||
        [value count] > AQServiceMaximumDocuments) return NO;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in value) {
        if (!AQServiceToken(entry) || [seen containsObject:entry]) return NO;
        [seen addObject:entry];
    }
    if (result != NULL) *result = [value copy];
    return YES;
}

static BOOL AQServiceSafeSourcePath(NSString *path);

static BOOL AQServicePathArray(id value, NSArray<NSString *> * _Nullable * _Nullable result) {
    if (![value isKindOfClass:NSArray.class] || [value count] == 0 ||
        [value count] > AQServiceMaximumSourceDescriptors) return NO;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in value) {
        if (![entry isKindOfClass:NSString.class] || !AQServiceSafeSourcePath(entry) ||
            [seen containsObject:entry]) return NO;
        [seen addObject:entry];
    }
    if (result != NULL) *result = [value copy];
    return YES;
}

static BOOL AQServiceData(id value, NSUInteger maximum, BOOL nonempty, NSData **result) {
    if (![value isKindOfClass:NSData.class] || [value length] > maximum ||
        (nonempty && [value length] == 0)) return NO;
    if (result != NULL) *result = value;
    return YES;
}

static BOOL AQServiceDataArray(id value, NSUInteger minimum, NSUInteger maximumCount,
                               NSUInteger *total, NSError **error) {
    if (![value isKindOfClass:NSArray.class] || [value count] < minimum ||
        [value count] > maximumCount) return AQServiceFail(error, AQServiceLimitExceeded);
    NSUInteger sum = 0;
    for (id entry in value) {
        if (![entry isKindOfClass:NSData.class] || [entry length] == 0 ||
            [entry length] > AQServiceMaximumDocumentBytes ||
            sum > AQServiceMaximumTotalDocumentBytes - [entry length]) {
            return AQServiceFail(error, AQServiceLimitExceeded);
        }
        sum += [entry length];
    }
    if (total != NULL) *total = sum;
    return YES;
}

static BOOL AQServiceSafeSourcePath(NSString *path) {
    if (![path isKindOfClass:NSString.class] || path.length == 0 || path.length > 4096 ||
        [path hasPrefix:@"/"] || [path hasSuffix:@"/"] || [path containsString:@"//"] ||
        [path containsString:@"\\"] || [path containsString:@":"] ||
        [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        return NO;
    }
    for (NSString *component in [path componentsSeparatedByString:@"/"]) {
        if (component.length == 0 || [component isEqual:@"."] || [component isEqual:@".."]) return NO;
    }
    return YES;
}

static BOOL AQServiceReviewAuthorizationMatches(id value, NSString *expectedSHA256,
                                                NSString *expectedManifestSHA256,
                                                NSString *expectedPlanSHA256,
                                                NSString *expectedRulesSHA256,
                                                NSError **error) {
    if (![value isKindOfClass:NSData.class] || [(NSData *)value length] == 0 ||
        [(NSData *)value length] > AQServiceMaximumDocumentBytes) {
        return AQServiceFail(error, AQServiceInvalidRequest);
    }
    NSData *reviewedBytes = value;
    NSString *actualSHA256 = AQServiceExactBytesSHA256(reviewedBytes);
    if (actualSHA256 == nil || expectedSHA256 == nil ||
        ![actualSHA256 isEqual:expectedSHA256]) {
        return AQServiceFail(error, AQServiceBindingMismatch);
    }
    NSError *parseError = nil;
    id authorization = AQParseJSON(reviewedBytes, &parseError);
    NSData *canonical = [authorization isKindOfClass:NSDictionary.class] ?
        AQCanonicalJSON(authorization, NULL) : nil;
    NSDictionary *plan = [authorization isKindOfClass:NSDictionary.class] ?
        authorization[@"plan"] : nil;
    if (![authorization isKindOfClass:NSDictionary.class] ||
        ![canonical isEqualToData:reviewedBytes]) {
        return AQServiceFail(error, AQServiceBindingMismatch);
    }
    if (![plan isKindOfClass:NSDictionary.class] ||
        !AQServiceDigestString(authorization[@"fixture_manifest_sha256"]) ||
        !AQServiceDigestString(plan[@"plan_sha256"]) ||
        !AQServiceDigestString(plan[@"rules_sha256"]) ||
        ![authorization[@"fixture_manifest_sha256"] isEqual:expectedManifestSHA256] ||
        ![plan[@"plan_sha256"] isEqual:expectedPlanSHA256] ||
        ![plan[@"rules_sha256"] isEqual:expectedRulesSHA256]) {
        return AQServiceFail(error, AQServiceBindingMismatch);
    }
    return YES;
}

static BOOL AQServiceSignedSourceIdentities(id value, NSArray<NSString *> *paths,
                                            NSArray<NSDictionary *> * _Nullable * _Nullable result) {
    if (![value isKindOfClass:NSArray.class] || [value count] != paths.count) return NO;
    NSMutableArray<NSDictionary *> *identities = [NSMutableArray arrayWithCapacity:paths.count];
    NSArray<NSString *> *keys = @[
        @"path", @"device", @"inode", @"mode", @"size", @"link_count"
    ];
    for (NSUInteger index = 0; index < paths.count; ++index) {
        NSDictionary *identity = value[index];
        uint64_t device = 0, inode = 0, mode = 0, size = 0, linkCount = 0;
        if (![identity isKindOfClass:NSDictionary.class] ||
            !AQServiceExactKeys(identity, keys) ||
            ![identity[@"path"] isEqual:paths[index]] ||
            !AQServiceUnsignedInteger(identity[@"device"], 0, INT64_MAX, &device) ||
            !AQServiceUnsignedInteger(identity[@"inode"], 1, INT64_MAX, &inode) ||
            !AQServiceUnsignedInteger(identity[@"mode"], 1, UINT32_MAX, &mode) ||
            !AQServiceUnsignedInteger(identity[@"size"], 0, INT64_MAX, &size) ||
            !AQServiceUnsignedInteger(identity[@"link_count"], 1, INT64_MAX, &linkCount) ||
            linkCount != 1) {
            return NO;
        }
        [identities addObject:[identity copy]];
    }
    if (result != NULL) *result = [identities copy];
    return YES;
}

static NSDictionary * _Nullable AQServiceActualSourceIdentity(NSString *path, int fd) {
    struct stat info = {0};
    if (!AQServiceSafeSourcePath(path) || fd < 0 || fcntl(fd, F_GETFL) < 0 ||
        (fcntl(fd, F_GETFL) & O_ACCMODE) != O_RDONLY || fstat(fd, &info) != 0 ||
        !S_ISREG(info.st_mode) || info.st_nlink != 1 || info.st_size < 0 ||
        (uint64_t)info.st_dev > INT64_MAX || (uint64_t)info.st_ino > INT64_MAX ||
        (uint64_t)info.st_size > INT64_MAX || (uint64_t)info.st_mode > UINT32_MAX) return nil;
    return @{
        @"path": path,
        @"device": @((uint64_t)info.st_dev),
        @"inode": @((uint64_t)info.st_ino),
        @"mode": @((uint32_t)info.st_mode),
        @"size": @((uint64_t)info.st_size),
        @"link_count": @((uint64_t)info.st_nlink),
    };
}

@interface AQServiceConnectionState : NSObject
@property(nonatomic, copy) NSString *connectionID;
@property(nonatomic, copy) NSString *phase;
@property(nonatomic, copy, nullable) NSString *sessionID;
@property(nonatomic, copy, nullable) NSString *grantID;
@property(nonatomic, copy, nullable) NSString *nonce;
@property(nonatomic, copy, nullable) NSString *challenge;
@property(nonatomic, copy, nullable) NSString *manifestSHA256;
@property(nonatomic, copy, nullable) NSString *planSHA256;
@property(nonatomic, copy, nullable) NSString *rulesSHA256;
@property(nonatomic, copy, nullable) NSString *authorizationSHA256;
@property(nonatomic, copy, nullable) NSString *consentSHA256;
@property(nonatomic, copy, nullable) NSArray<NSString *> *operations;
@property(nonatomic, strong, nullable) NSData *consentEnvelope;
@property(nonatomic, copy, nullable) NSString *serviceBootID;
@property(nonatomic) uint64_t storeEpoch;
@property(nonatomic) uint64_t deadlineNanoseconds;
@property(nonatomic) uint64_t storeDeadlineTicks;
@property(nonatomic) uint64_t hostReserveBytes;
@property(nonatomic) uint64_t destinationReserveBytes;
@property(nonatomic) BOOL cleanupAuthorized;
@property(nonatomic) BOOL admittedDuringFreshRecovery;
@property(nonatomic) uint64_t lastRequestSequence;
@end

@implementation AQServiceConnectionState
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _phase = @"registered";
    return self;
}
@end

/** Immutable result of authenticating one request before protected payload
 * checkout. Dispatch consumes this value instead of verifying the owner
 * signature or advancing replay state a second time. */
@interface AQServiceVerifiedFreshness : NSObject
@property(nonatomic, copy, readonly) NSDictionary *requestBody;
@property(nonatomic, readonly) uint64_t sequence;
@property(nonatomic, readonly) uint64_t deadlineNanoseconds;
@property(nonatomic, readonly) BOOL requiresFreshness;
- (instancetype)initWithRequestBody:(NSDictionary *)requestBody
                           sequence:(uint64_t)sequence
                 deadlineNanoseconds:(uint64_t)deadlineNanoseconds
                  requiresFreshness:(BOOL)requiresFreshness;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation AQServiceVerifiedFreshness
- (instancetype)initWithRequestBody:(NSDictionary *)requestBody
                           sequence:(uint64_t)sequence
                 deadlineNanoseconds:(uint64_t)deadlineNanoseconds
                  requiresFreshness:(BOOL)requiresFreshness {
    if (!(self = [super init])) return nil;
    _requestBody = [requestBody copy];
    _sequence = sequence;
    _deadlineNanoseconds = deadlineNanoseconds;
    _requiresFreshness = requiresFreshness;
    return self;
}
@end

@interface AQServiceSessionCore ()
@property(nonatomic, strong) id<AQServiceStore> store;
@property(nonatomic, copy) NSString *installationIdentity;
@property(nonatomic, copy) NSString *serviceBootIdentity;
@property(nonatomic, copy) NSString *brokerRevision;
@property(nonatomic, copy) NSString *ownerKeyIdentifier;
@property(nonatomic, strong) id<AQServiceClock> clock;
@property(nonatomic, copy) AQServiceOwnerVerifier ownerVerifier;
@property(nonatomic, copy) AQServiceIdentifierGenerator identifierGenerator;
/** Protects every read, insertion, and removal in the connection registry. */
@property(nonatomic, strong) NSLock *connectionsLock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, AQServiceConnectionState *> *connections;
/** Process-lifetime hello high-water marks keyed by installed owner. The core's
 * immutable service boot identity scopes the dictionary to one service epoch. */
@property(nonatomic, strong) NSLock *ownerHelloSequencesLock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *ownerHelloSequences;
- (nullable AQServiceConnectionState *)connectionStateForID:(NSString *)connectionID;
- (nullable NSString *)requestDigestForBody:(NSDictionary *)requestBody;
- (nullable NSString *)requestIDForSession:(NSString *)sessionID
                                  sequence:(uint64_t)sequence
                                 operation:(NSString *)operation
                             requestDigest:(NSString *)requestDigest;
- (BOOL)recordRequestSequence:(uint64_t)sequence
                        state:(AQServiceConnectionState *)state
                        error:(NSError **)error;
- (BOOL)recordHelloSequence:(uint64_t)sequence error:(NSError **)error;
/** Verifies an owner-signed freshness envelope before any operation-specific
 * request field, protected document, source descriptor, callback, or store
 * mutation is examined. Returns the canonical request body without the two
 * transport credentials. The envelope binds the installed identities and
 * service boot, connection, session, authorization epoch, request identity,
 * one-based sequence, operation, exact request digest, authorization and
 * owner-consent digests,
 * and immutable deadline. This verification does not change replay state. */
- (nullable NSDictionary *)verifyFreshnessForRequest:(NSDictionary *)request
                                               state:(AQServiceConnectionState *)state
                                              error:(NSError **)error;
/** Authenticates a request and advances replay state exactly once without
 * examining protected executable payloads. */
- (nullable AQServiceVerifiedFreshness *)preflightRequest:(NSDictionary *)request
                                             connectionID:(NSString *)connectionID
                                                  error:(NSError **)error;
- (nullable NSDictionary *)dispatchRequest:(NSDictionary *)request
                                 documents:(NSDictionary * _Nullable)documents
                                 sourceFDs:(NSDictionary<NSString *, NSNumber *> * _Nullable)sourceFDs
                         verifiedFreshness:(AQServiceVerifiedFreshness *)verifiedFreshness
                              connectionID:(NSString *)connectionID
                      exportFileDescriptor:(int *)exportFileDescriptor
                                     error:(NSError **)error;
- (nullable NSDictionary *)handleHello:(NSDictionary *)request
                                state:(AQServiceConnectionState *)state
                                error:(NSError **)error;
- (nullable NSDictionary *)handleAdmit:(NSDictionary *)request
                               documents:(NSDictionary *)documents
                                   state:(AQServiceConnectionState *)state
                                   error:(NSError **)error;
- (nullable NSDictionary *)handleStoreOperation:(NSDictionary *)request
                                        sourceFDs:(NSDictionary<NSString *, NSNumber *> *)sourceFDs
                                            state:(AQServiceConnectionState *)state
                             exportFileDescriptor:(int *)exportFileDescriptor
                                            error:(NSError **)error;
- (AQServiceErrorCode)codeForStoreError:(NSError *)error;
@end

@implementation AQServiceSessionCore

- (instancetype)initWithStore:(id<AQServiceStore>)store
          installationIdentity:(NSString *)installationIdentity
             serviceBootIdentity:(NSString *)serviceBootIdentity
                 brokerRevision:(NSString *)brokerRevision
               ownerKeyIdentifier:(NSString *)ownerKeyIdentifier
                           clock:(id<AQServiceClock>)clock
                           ownerVerifier:(AQServiceOwnerVerifier)ownerVerifier
              identifierGenerator:(AQServiceIdentifierGenerator)identifierGenerator
                            error:(NSError **)error {
    if (error != NULL) *error = nil;
    if (!(self = [super init])) {
        AQServiceFail(error, AQServiceInternalFailure);
        return nil;
    }
    if (store == nil || !AQServiceToken(installationIdentity) ||
        !AQServiceToken(serviceBootIdentity) || !AQServiceToken(brokerRevision) ||
        !AQServiceToken(ownerKeyIdentifier) || clock == nil || ownerVerifier == nil ||
        identifierGenerator == nil) {
        AQServiceFail(error, AQServiceUnsupportedInstallation);
        return nil;
    }
    _store = store;
    _installationIdentity = [installationIdentity copy];
    _serviceBootIdentity = [serviceBootIdentity copy];
    _brokerRevision = [brokerRevision copy];
    _ownerKeyIdentifier = [ownerKeyIdentifier copy];
    _clock = clock;
    _ownerVerifier = [ownerVerifier copy];
    _identifierGenerator = [identifierGenerator copy];
    _connectionsLock = [[NSLock alloc] init];
    _connections = [NSMutableDictionary dictionary];
    _ownerHelloSequencesLock = [[NSLock alloc] init];
    _ownerHelloSequences = [NSMutableDictionary dictionary];
    return self;
}

- (nullable NSString *)generatedToken:(NSError **)error {
    @try {
        NSString *token = self.identifierGenerator();
        if (!AQServiceToken(token)) {
            AQServiceFail(error, AQServiceInternalFailure);
            return nil;
        }
        return token;
    } @catch (__unused NSException *exception) {
        AQServiceFail(error, AQServiceInternalFailure);
        return nil;
    }
}

- (nullable NSString *)requestDigestForBody:(NSDictionary *)requestBody {
    NSMutableDictionary *content = [requestBody mutableCopy];
    [content removeObjectForKey:@"request_id"];
    [content removeObjectForKey:@"freshness_envelope"];
    [content removeObjectForKey:@"freshness_signature"];
    return AQDigest(AQServiceRequestDigestDomain, content, NULL);
}

- (nullable NSString *)requestIDForSession:(NSString *)sessionID
                                  sequence:(uint64_t)sequence
                                 operation:(NSString *)operation
                             requestDigest:(NSString *)requestDigest {
    return AQDigest(AQServiceRequestIDDomain, @{
        @"session_id": sessionID,
        @"sequence": @(sequence),
        @"operation": operation,
        @"request_sha256": requestDigest
    }, NULL);
}

- (BOOL)recordRequestSequence:(uint64_t)__unused sequence
                        state:(AQServiceConnectionState *)__unused state
                        error:(NSError **)__unused error {
    return YES;
}

- (BOOL)recordHelloSequence:(uint64_t)sequence error:(NSError **)error {
    [self.ownerHelloSequencesLock lock];
    NSNumber *highWaterValue = self.ownerHelloSequences[self.ownerKeyIdentifier];
    uint64_t highWater = highWaterValue == nil ? 0 : highWaterValue.unsignedLongLongValue;
    BOOL accepted = highWater == 0 ? sequence > 0 : sequence == highWater + 1;
    if (accepted) self.ownerHelloSequences[self.ownerKeyIdentifier] = @(sequence);
    [self.ownerHelloSequencesLock unlock];
    return accepted ? YES : AQServiceFail(error, AQServiceReplayRejected);
}

- (nullable NSString *)openConnection:(NSError **)error {
    if (error != NULL) *error = nil;
    [self.connectionsLock lock];
    BOOL atCapacity = self.connections.count >= AQServiceMaximumConnections;
    [self.connectionsLock unlock];
    if (atCapacity) {
        AQServiceFail(error, AQServiceLimitExceeded);
        return nil;
    }
    NSString *connectionID = [self generatedToken:error];
    if (connectionID == nil) return nil;
    AQServiceConnectionState *state = [[AQServiceConnectionState alloc] init];
    state.connectionID = connectionID;

    [self.connectionsLock lock];
    BOOL reachedCapacity = self.connections.count >= AQServiceMaximumConnections;
    BOOL identifierAlreadyRegistered = NO;
    if (!reachedCapacity) {
        identifierAlreadyRegistered = self.connections[connectionID] != nil;
        if (!identifierAlreadyRegistered) self.connections[connectionID] = state;
    }
    [self.connectionsLock unlock];

    if (reachedCapacity) {
        AQServiceFail(error, AQServiceLimitExceeded);
        return nil;
    }
    if (identifierAlreadyRegistered) {
        AQServiceFail(error, AQServiceInternalFailure);
        return nil;
    }
    return connectionID;
}

- (nullable AQServiceConnectionState *)connectionStateForID:(NSString *)connectionID {
    [self.connectionsLock lock];
    AQServiceConnectionState *state = self.connections[connectionID];
    [self.connectionsLock unlock];
    return state;
}

- (nullable NSDictionary *)verifyFreshnessForRequest:(NSDictionary *)request
                                               state:(AQServiceConnectionState *)state
                                              error:(NSError **)error {
    NSString *encodedEnvelope = request[@"freshness_envelope"];
    NSString *encodedSignature = request[@"freshness_signature"];
    if (!AQServiceString(encodedEnvelope, 1, AQServiceMaximumRequestBytes * 2) ||
        !AQServiceString(encodedSignature, 1, AQServiceMaximumSignatureBytes * 2)) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }
    NSData *canonicalFreshness = [[NSData alloc]
        initWithBase64EncodedString:encodedEnvelope options:0];
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:encodedSignature options:0];
    if (canonicalFreshness.length == 0 ||
        canonicalFreshness.length > AQServiceMaximumRequestBytes ||
        ![encodedEnvelope isEqual:[canonicalFreshness base64EncodedStringWithOptions:0]] ||
        signature.length == 0 || signature.length > AQServiceMaximumSignatureBytes ||
        ![encodedSignature isEqual:[signature base64EncodedStringWithOptions:0]]) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }

    NSError *verifyError = nil;
    BOOL verified = NO;
    @try {
        verified = self.ownerVerifier(canonicalFreshness, signature, &verifyError);
    } @catch (__unused NSException *exception) {
        verified = NO;
    }
    if (!verified) {
        AQServiceFail(error, AQServiceConsentDenied);
        return nil;
    }

    NSError *parseError = nil;
    id freshnessObject = AQParseJSON(canonicalFreshness, &parseError);
    NSData *canonicalAgain = [freshnessObject isKindOfClass:NSDictionary.class] ?
        AQCanonicalJSON(freshnessObject, NULL) : nil;
    if (![freshnessObject isKindOfClass:NSDictionary.class] ||
        ![canonicalAgain isEqualToData:canonicalFreshness]) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }
    NSDictionary *freshness = freshnessObject;
    NSArray<NSString *> *keys = @[
        @"schema_version", @"installation_id", @"service_boot_id", @"broker_revision",
        @"owner_key_id", @"connection_id", @"session_id", @"request_id",
        @"sequence", @"operation", @"request_sha256", @"authorization_sha256",
        @"consent_sha256", @"deadline_ns"
    ];
    if (!AQServiceExactKeys(freshness, keys) ||
        !AQServiceToken(freshness[@"installation_id"]) ||
        !AQServiceToken(freshness[@"service_boot_id"]) ||
        !AQServiceToken(freshness[@"broker_revision"]) ||
        !AQServiceToken(freshness[@"owner_key_id"]) ||
        !AQServiceToken(freshness[@"connection_id"]) ||
        !AQServiceToken(freshness[@"session_id"]) ||
        !AQServiceDigestString(freshness[@"request_id"]) ||
        !AQServiceToken(freshness[@"operation"]) ||
        !AQServiceDigestString(freshness[@"request_sha256"]) ||
        !AQServiceDigestString(freshness[@"authorization_sha256"]) ||
        !AQServiceDigestString(freshness[@"consent_sha256"])) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }
    uint64_t sequence = 0, deadline = 0;
    if (!AQServiceUnsignedInteger(freshness[@"schema_version"], 1, 1, NULL) ||
        !AQServiceUnsignedInteger(freshness[@"sequence"], 1, INT64_MAX, &sequence) ||
        !AQServiceUnsignedInteger(freshness[@"deadline_ns"], 1, INT64_MAX, &deadline)) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }

    NSMutableDictionary *requestBody = [request mutableCopy];
    [requestBody removeObjectForKey:@"freshness_envelope"];
    [requestBody removeObjectForKey:@"freshness_signature"];
    NSString *requestDigest = [self requestDigestForBody:requestBody];
    NSString *expectedRequestID = [self requestIDForSession:(NSString *)state.sessionID
        sequence:sequence operation:(NSString *)freshness[@"operation"]
        requestDigest:requestDigest];
    if (requestDigest == nil || expectedRequestID == nil) {
        AQServiceFail(error, AQServiceInternalFailure);
        return nil;
    }
    if (![freshness[@"installation_id"] isEqual:self.installationIdentity] ||
        ![freshness[@"service_boot_id"] isEqual:self.serviceBootIdentity] ||
        ![freshness[@"broker_revision"] isEqual:self.brokerRevision] ||
        ![freshness[@"owner_key_id"] isEqual:self.ownerKeyIdentifier] ||
        ![freshness[@"connection_id"] isEqual:state.connectionID] ||
        ![freshness[@"session_id"] isEqual:state.sessionID] ||
        ![freshness[@"operation"] isEqual:request[@"operation"]] ||
        state.authorizationSHA256 == nil ||
        ![freshness[@"authorization_sha256"] isEqual:state.authorizationSHA256] ||
        state.consentSHA256 == nil ||
        ![freshness[@"consent_sha256"] isEqual:state.consentSHA256]) {
        AQServiceFail(error, AQServiceBindingMismatch);
        return nil;
    }
    if (![freshness[@"request_id"] isEqual:request[@"request_id"]] ||
        ![freshness[@"request_id"] isEqual:expectedRequestID] ||
        ![freshness[@"request_sha256"] isEqual:requestDigest]) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }
    if (sequence <= state.lastRequestSequence) {
        AQServiceFail(error, AQServiceReplayRejected);
        return nil;
    }
    if (sequence != state.lastRequestSequence + 1) {
        AQServiceFail(error, AQServiceReplayRejected);
        return nil;
    }
    if (deadline != state.deadlineNanoseconds) {
        AQServiceFail(error, AQServiceBindingMismatch);
        return nil;
    }
    if (deadline <= self.clock.monotonicNanoseconds) {
        AQServiceFail(error, AQServiceConsentExpired);
        return nil;
    }
    return requestBody;
}

/* Performs authentication and advances replay state before protected
   executable payload loaders are checked out. The returned value is the only
   freshness result consumed by dispatch. */
- (nullable AQServiceVerifiedFreshness *)preflightRequest:(NSDictionary *)request
                                             connectionID:(NSString *)connectionID
                                                  error:(NSError **)error {
    if (error != NULL) *error = nil;
    if (![request isKindOfClass:NSDictionary.class] || !AQServiceToken(connectionID)) {
        return nil;
    }
    AQServiceConnectionState *state = [self connectionStateForID:connectionID];
    if (state == nil || [state.phase isEqual:@"invalidated"]) {
        AQServiceFail(error, AQServiceUnauthenticatedConnection);
        return nil;
    }
    uint64_t version = 0;
    if (!AQServiceUnsignedInteger(request[@"schema_version"], 1, INT64_MAX, &version)) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }
    if (version != 1) {
        AQServiceFail(error, AQServiceUnsupportedVersion);
        return nil;
    }
    NSString *operation = request[@"operation"];
    if (!AQServiceToken(operation) || !AQServiceToken(request[@"request_id"])) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }
    if (request[@"authorization"] != nil && ![operation isEqual:@"hello"]) {
        AQServiceFail(error, AQServiceInvalidRequest);
        return nil;
    }
    if ([operation isEqual:@"readiness"] || [operation isEqual:@"hello"]) {
        return [[AQServiceVerifiedFreshness alloc]
            initWithRequestBody:request sequence:0 deadlineNanoseconds:0 requiresFreshness:NO];
    }
    if (![request[@"connection_id"] isEqual:connectionID]) {
        AQServiceFail(error, AQServiceBindingMismatch);
        return nil;
    }
    NSDictionary *requestBody = [self verifyFreshnessForRequest:request state:state error:error];
    if (requestBody == nil) return nil;

    id encodedFreshnessValue = request[@"freshness_envelope"];
    if (!AQServiceString(encodedFreshnessValue, 1, AQServiceMaximumRequestBytes * 2)) {
        AQServiceFail(error, AQServiceInternalFailure);
        return nil;
    }
    NSData *canonicalFreshness = [[NSData alloc]
        initWithBase64EncodedString:encodedFreshnessValue options:0];
    NSDictionary *freshness = AQParseJSON(canonicalFreshness, NULL);
    uint64_t sequence = 0;
    uint64_t deadline = 0;
    if (![freshness isKindOfClass:NSDictionary.class] ||
        !AQServiceUnsignedInteger(freshness[@"sequence"], 1, INT64_MAX, &sequence) ||
        !AQServiceUnsignedInteger(freshness[@"deadline_ns"], 1, INT64_MAX, &deadline)) {
        AQServiceFail(error, AQServiceInternalFailure);
        return nil;
    }
    if (![self recordRequestSequence:sequence state:state error:error]) return nil;
    state.lastRequestSequence = sequence;
    return [[AQServiceVerifiedFreshness alloc]
        initWithRequestBody:requestBody sequence:sequence deadlineNanoseconds:deadline
        requiresFreshness:YES];
}

- (nullable NSDictionary *)handleHello:(NSDictionary *)request
                                state:(AQServiceConnectionState *)state
                                error:(NSError **)error {
    NSArray<NSString *> *keys = @[
        @"schema_version", @"operation", @"request_id", @"nonce", @"grant_id", @"sequence",
        @"authorization", @"service_boot_id",
        @"installation_id", @"broker_revision", @"owner_key_id",
        @"authorization_sha256", @"approval_sha256",
        @"manifest_sha256", @"plan_sha256", @"rules_sha256", @"operations",
        @"deadline_ns", @"store_deadline_ticks", @"host_reserve_bytes",
        @"destination_reserve_bytes",
        @"cleanup_authorized"
    ];
    if (!AQServiceExactKeys(request, keys)) return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    if (![request[@"operation"] isEqual:@"hello"] || !AQServiceToken(request[@"request_id"]) ||
        !AQServiceToken(request[@"nonce"]) || !AQServiceToken(request[@"grant_id"]) ||
        !AQServiceToken(request[@"service_boot_id"]) ||
        !AQServiceToken(request[@"installation_id"]) || !AQServiceToken(request[@"broker_revision"]) ||
        !AQServiceToken(request[@"owner_key_id"]) ||
        ![request[@"installation_id"] isEqual:self.installationIdentity] ||
        ![request[@"broker_revision"] isEqual:self.brokerRevision] ||
        ![request[@"owner_key_id"] isEqual:self.ownerKeyIdentifier] ||
        !AQServiceDigestString(request[@"authorization_sha256"]) ||
        !AQServiceDigestString(request[@"approval_sha256"]) ||
        !AQServiceDigestString(request[@"manifest_sha256"]) ||
        !AQServiceDigestString(request[@"plan_sha256"]) ||
        !AQServiceDigestString(request[@"rules_sha256"])) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    if (![request[@"service_boot_id"] isEqual:self.serviceBootIdentity]) {
        return AQServiceFail(error, AQServiceBindingMismatch) ? nil : nil;
    }
    if (!AQServiceReviewAuthorizationMatches(request[@"authorization"],
            request[@"authorization_sha256"], request[@"manifest_sha256"],
            request[@"plan_sha256"], request[@"rules_sha256"], error)) return nil;
    if (![state.phase isEqual:@"registered"]) {
        return AQServiceFail(error, AQServiceBindingMismatch) ? nil : nil;
    }
    NSArray<NSString *> *operations = nil;
    if (!AQServiceStringArray(request[@"operations"], NO, &operations)) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    NSSet *allowed = [NSSet setWithArray:@[@"stage", @"eligibility", @"export", @"cleanup"]];
    for (NSString *operation in operations) {
        if (![allowed containsObject:operation]) {
            return AQServiceFail(error, AQServiceOperationDenied) ? nil : nil;
        }
    }
    BOOL cleanupAuthorized = NO;
    uint64_t sequence = 0, deadline = 0, storeDeadline = 0;
    uint64_t hostReserve = 0, destinationReserve = 0;
    if (!AQServiceUnsignedInteger(request[@"sequence"], 1, INT64_MAX, &sequence) ||
        !AQServiceUnsignedInteger(request[@"deadline_ns"], 1, INT64_MAX, &deadline) ||
        !AQServiceUnsignedInteger(request[@"store_deadline_ticks"], 1, INT64_MAX,
                                  &storeDeadline) ||
        !AQServiceUnsignedInteger(request[@"host_reserve_bytes"], 0, INT64_MAX, &hostReserve) ||
        !AQServiceUnsignedInteger(request[@"destination_reserve_bytes"], 0, INT64_MAX,
                                  &destinationReserve) ||
        !AQServiceBoolean(request[@"cleanup_authorized"], &cleanupAuthorized)) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    if (cleanupAuthorized != [operations containsObject:@"cleanup"]) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    uint64_t storeNow = self.clock.continuousTicks;
    uint64_t now = self.clock.monotonicNanoseconds;
    if (storeNow == UINT64_MAX || now == UINT64_MAX) {
        return AQServiceFail(error, AQServiceInternalFailure) ? nil : nil;
    }
    if (deadline <= now) {
        return AQServiceFail(error, AQServiceConsentExpired) ? nil : nil;
    }
    if (deadline - now > AQServiceMaximumOperationNanoseconds) {
        return AQServiceFail(error, AQServiceLimitExceeded) ? nil : nil;
    }
    mach_timebase_info_data_t timebase = {0, 0};
    uint64_t latestStoreDeadline = 0;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS ||
        !AQStoreDeadlineTicksForMonotonicDeadline(deadline, now, storeNow,
            timebase.numer, timebase.denom, &latestStoreDeadline)) {
        return AQServiceFail(error, AQServiceInternalFailure) ? nil : nil;
    }
    if (storeDeadline <= storeNow || storeDeadline > latestStoreDeadline) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    NSString *expectedNonce = AQServiceHelloNonce(self.installationIdentity,
        self.serviceBootIdentity, self.brokerRevision, self.ownerKeyIdentifier, sequence,
        request[@"authorization_sha256"]);
    if (expectedNonce == nil || ![request[@"nonce"] isEqual:expectedNonce]) {
        return AQServiceFail(error, AQServiceReplayRejected) ? nil : nil;
    }
    if (![self recordHelloSequence:sequence error:error]) return nil;
    NSString *sessionID = [self generatedToken:error];
    NSString *challenge = [self generatedToken:error];
    if (sessionID == nil || challenge == nil) return nil;

    NSDictionary *consent = @{
        @"schema_version": @1,
        @"owner_key_id": self.ownerKeyIdentifier,
        @"broker_revision": self.brokerRevision,
        @"installation_id": self.installationIdentity,
        @"service_boot_id": self.serviceBootIdentity,
        @"session_id": sessionID,
        @"connection_id": state.connectionID,
        @"challenge": challenge,
        @"nonce": (NSString *)request[@"nonce"],
        @"grant_id": (NSString *)request[@"grant_id"],
        @"authorization_sha256": (NSString *)request[@"authorization_sha256"],
        @"approval_sha256": (NSString *)request[@"approval_sha256"],
        @"manifest_sha256": (NSString *)request[@"manifest_sha256"],
        @"plan_sha256": (NSString *)request[@"plan_sha256"],
        @"rules_sha256": (NSString *)request[@"rules_sha256"],
        @"operations": operations,
        @"deadline_ns": @(deadline),
        @"store_deadline_ticks": @(storeDeadline),
        @"host_reserve_bytes": @(hostReserve),
        @"destination_reserve_bytes": @(destinationReserve),
        @"cleanup_authorized": @(cleanupAuthorized)
    };
    NSError *encodeError = nil;
    NSData *envelope = AQCanonicalJSON(consent, &encodeError);
    if (envelope == nil || envelope.length > AQServiceMaximumRequestBytes) {
        return AQServiceFail(error, AQServiceInternalFailure) ? nil : nil;
    }

    state.phase = @"owner_consent_pending";
    state.sessionID = sessionID;
    state.grantID = request[@"grant_id"];
    state.nonce = request[@"nonce"];
    state.challenge = challenge;
    state.manifestSHA256 = request[@"manifest_sha256"];
    state.planSHA256 = request[@"plan_sha256"];
    state.rulesSHA256 = request[@"rules_sha256"];
    state.authorizationSHA256 = request[@"authorization_sha256"];
    state.consentSHA256 = request[@"approval_sha256"];
    state.operations = operations;
    state.consentEnvelope = envelope;
    state.serviceBootID = self.serviceBootIdentity;
    state.storeEpoch = AQServiceStoreEpochForBootIdentity(self.serviceBootIdentity);
    state.deadlineNanoseconds = deadline;
    state.storeDeadlineTicks = storeDeadline;
    state.hostReserveBytes = hostReserve;
    state.destinationReserveBytes = destinationReserve;
    state.cleanupAuthorized = cleanupAuthorized;
    NSString *consentDigest = AQDigest(@"", consent, &encodeError);
    if (consentDigest == nil) return AQServiceFail(error, AQServiceInternalFailure) ? nil : nil;
    return @{
        @"connection_id": state.connectionID,
        @"session_id": sessionID,
        @"challenge": challenge,
        @"consent_envelope": [envelope base64EncodedStringWithOptions:0],
        @"consent_sha256": consentDigest,
        @"service_boot_id": self.serviceBootIdentity,
        @"deadline_ns": @(deadline)
    };
}

- (nullable NSDictionary *)handleRequest:(NSDictionary *)request
                             documents:(NSDictionary * _Nullable)documents
                             sourceFDs:(NSDictionary<NSString *, NSNumber *> * _Nullable)sourceFDs
                            connectionID:(NSString *)connectionID
                  exportFileDescriptor:(int *)exportFileDescriptor
                                   error:(NSError **)error {
    if (error != NULL) *error = nil;
    if (exportFileDescriptor != NULL) *exportFileDescriptor = -1;
    AQServiceVerifiedFreshness *verified = [self preflightRequest:request
        connectionID:connectionID error:error];
    if (verified == nil) return nil;
    NSString *operation = verified.requestBody[@"operation"];
    if (!AQServiceProductionMutationAllowed(operation)) {
        return AQServiceFail(error, AQServiceUnsupportedExclusivity) ? nil : nil;
    }
    if ((documents != nil && ![operation isEqual:@"admit"]) ||
        (sourceFDs != nil && ![operation isEqual:@"stage"])) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    return [self dispatchRequest:request documents:documents sourceFDs:sourceFDs
        verifiedFreshness:verified connectionID:connectionID
        exportFileDescriptor:exportFileDescriptor error:error];
}

- (nullable NSDictionary *)dispatchRequest:(NSDictionary *)request
                                 documents:(NSDictionary * _Nullable)documents
                                 sourceFDs:(NSDictionary<NSString *, NSNumber *> * _Nullable)sourceFDs
                         verifiedFreshness:(AQServiceVerifiedFreshness *)verifiedFreshness
                              connectionID:(NSString *)connectionID
                      exportFileDescriptor:(int *)exportFileDescriptor
                                     error:(NSError **)error {
    if (error != NULL) *error = nil;
    if (![verifiedFreshness isKindOfClass:AQServiceVerifiedFreshness.class]) {
        return AQServiceFail(error, AQServiceInternalFailure) ? nil : nil;
    }
    request = verifiedFreshness.requestBody;
    if (![request isKindOfClass:NSDictionary.class] || !AQServiceToken(connectionID)) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    AQServiceConnectionState *state = [self connectionStateForID:connectionID];
    if (state == nil || [state.phase isEqual:@"invalidated"]) {
        return AQServiceFail(error, AQServiceUnauthenticatedConnection) ? nil : nil;
    }
    if (verifiedFreshness.requiresFreshness &&
        verifiedFreshness.deadlineNanoseconds <= self.clock.monotonicNanoseconds) {
        return AQServiceFail(error, AQServiceConsentExpired) ? nil : nil;
    }
    NSString *operation = request[@"operation"];
    if (!AQServiceToken(operation) || !AQServiceToken(request[@"request_id"])) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }

    if ([operation isEqual:@"readiness"]) {
        if (documents != nil || sourceFDs != nil || request[@"authorization"] != nil) {
            return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
        }
        return [self readinessFacts];
    }
    if ([operation isEqual:@"hello"]) {
        if (documents != nil || sourceFDs != nil) {
            return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
        }
        return [self handleHello:request state:state error:error];
    }
    if ([operation isEqual:@"admit"]) {
        if (documents == nil || sourceFDs != nil) {
            return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
        }
        return [self handleAdmit:request documents:documents state:state error:error];
    }
    if (documents != nil) return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;

    if ([operation isEqual:@"inspect"]) {
        NSArray<NSString *> *keys = @[
            @"schema_version", @"operation", @"request_id", @"connection_id", @"session_id"
        ];
        if (!AQServiceExactKeys(request, keys) || !AQServiceToken(request[@"session_id"])) {
            return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
        }
    NSDictionary *result = [self.store inspectSession:(NSString *)request[@"session_id"]];
        if (result == nil) return AQServiceFail(error, AQServiceStoreDenied) ? nil : nil;
        return @{@"session": result, @"read_only": @YES};
    }
    if ([operation isEqual:@"recovery"]) {
        NSArray<NSString *> *keys = @[
            @"schema_version", @"operation", @"request_id", @"connection_id"
        ];
        if (!AQServiceExactKeys(request, keys) || sourceFDs != nil) {
            return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
        }
        return @{@"recovery": [self.store classifyRecovery], @"read_only": @YES};
    }
    if ([operation isEqual:@"revoke"]) {
        NSArray<NSString *> *keys = @[
            @"schema_version", @"operation", @"request_id", @"connection_id", @"session_id",
            @"grant_id", @"epoch"
        ];
        uint64_t epoch = 0;
        if (!AQServiceExactKeys(request, keys) || sourceFDs != nil ||
            ![request[@"session_id"] isEqual:state.sessionID] ||
            ![request[@"grant_id"] isEqual:state.grantID] ||
            !AQServiceUnsignedInteger(request[@"epoch"], 0, INT64_MAX, &epoch) ||
            epoch != state.storeEpoch) {
            return AQServiceFail(error, AQServiceBindingMismatch) ? nil : nil;
        }
    NSString *sessionID = state.sessionID;
    if (sessionID == nil) return AQServiceFail(error, AQServiceBindingMismatch) ? nil : nil;
    [self.store revokeSession:sessionID reason:@"owner_or_broker_revocation"];
    NSDictionary *result = @{@"revoked": @YES, @"session_id": sessionID};
        state.phase = @"invalidated";
        return result;
    }
    if (sourceFDs != nil && ![operation isEqual:@"stage"]) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    return [self handleStoreOperation:request sourceFDs:sourceFDs state:state
                 exportFileDescriptor:exportFileDescriptor error:error];
}

- (nullable NSDictionary *)handleRequest:(NSDictionary *)request
                         documentsLoader:(AQServiceDocumentsLoader)documentsLoader
                         sourceFDsLoader:(AQServiceSourceFDsLoader)sourceFDsLoader
                            connectionID:(NSString *)connectionID
                  exportFileDescriptor:(int *)exportFileDescriptor
                                   error:(NSError **)error {
    if (error != NULL) *error = nil;
    if (exportFileDescriptor != NULL) *exportFileDescriptor = -1;
    AQServiceVerifiedFreshness *verified = [self preflightRequest:request
        connectionID:connectionID error:error];
    if (verified == nil) return nil;
    NSString *operation = verified.requestBody[@"operation"];
    if (!AQServiceProductionMutationAllowed(operation)) {
        return AQServiceFail(error, AQServiceUnsupportedExclusivity) ? nil : nil;
    }
    if ((documentsLoader != nil && ![operation isEqual:@"admit"]) ||
        (sourceFDsLoader != nil && ![operation isEqual:@"stage"])) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    NSDictionary *documents = documentsLoader != nil ? documentsLoader() : nil;
    NSDictionary *sourceFDs = sourceFDsLoader != nil ? sourceFDsLoader() : nil;
    return [self dispatchRequest:verified.requestBody documents:documents sourceFDs:sourceFDs
        verifiedFreshness:verified connectionID:connectionID
        exportFileDescriptor:exportFileDescriptor error:error];
}

- (void)invalidateConnection:(NSString *)connectionID reason:(NSString *)reason {
    if (!AQServiceToken(connectionID)) return;
    AQServiceConnectionState *state = [self connectionStateForID:connectionID];
    if (state == nil) return;
    NSString *sessionID = state.sessionID;
    if (sessionID.length != 0) {
        [self.store revokeSession:sessionID reason:@"broker_connection_lost"];
    }
    state.phase = @"invalidated";
    state.consentEnvelope = nil;
    [self.connectionsLock lock];
    [self.connections removeObjectForKey:connectionID];
    [self.connectionsLock unlock];
}

- (NSDictionary *)readinessFacts {
    NSDictionary *recovery = [self.store classifyRecovery];
    NSString *recoveryState = [recovery[@"state"] isKindOfClass:NSString.class]
        ? recovery[@"state"] : @"unknown";
    return @{
        @"ready": @([recoveryState isEqual:@"clean"]),
        @"store_recovery_state": recoveryState,
        @"protocol_version": @1,
        @"installation_id": self.installationIdentity,
        @"service_boot_id": self.serviceBootIdentity,
        @"broker_revision": self.brokerRevision,
        @"owner_key_id": self.ownerKeyIdentifier,
        @"staging_root": AQProductionStagingRoot,
        @"namespace_authority": @"protected_service_identity",
        @"python_destination": @"BLOCKED_UNSUPPORTED_EXCLUSIVITY",
        @"exclusive_cleanup_authority": @"requires_kernel_isolation_proof"
    };
}

- (AQServiceErrorCode)codeForStoreError:(NSError *)error {
    if (![error.domain isEqual:AQStoreErrorDomain]) return AQServiceStoreDenied;
    switch ((AQStoreErrorCode)error.code) {
        case AQStoreDeadlineExpired: return AQServiceConsentExpired;
        case AQStoreRevoked: return AQServiceUnauthenticatedConnection;
        case AQStoreInvalidInput:
        case AQStoreInvalidState: return AQServiceBindingMismatch;
        case AQStoreMetadataHeaderTooLarge: return AQServiceLimitExceeded;
        case AQStoreUnauthorizedRoot:
        case AQStoreSourceDenied:
        case AQStoreCapacityDenied:
        case AQStoreIntegrityFailure:
        case AQStoreJournalCorrupt:
        case AQStoreBusy:
        case AQStoreIOFailure: return AQServiceStoreDenied;
    }
}

- (nullable NSDictionary *)handleStoreOperation:(NSDictionary *)request
                                        sourceFDs:(NSDictionary<NSString *, NSNumber *> *)sourceFDs
                                            state:(AQServiceConnectionState *)state
                             exportFileDescriptor:(int *)exportFileDescriptor
                                            error:(NSError **)error {
    NSString *operation = request[@"operation"];
    BOOL isStage = [operation isEqual:@"stage"];
    NSMutableArray<NSString *> *keys = [@[
        @"schema_version", @"operation", @"request_id", @"connection_id", @"session_id",
        @"grant_id", @"epoch", @"sequence", @"expected_generation"
    ] mutableCopy];
    if (isStage) [keys addObjectsFromArray:@[ @"source_paths", @"source_identities" ]];
    if (!AQServiceExactKeys(request, keys) ||
        ![state.phase isEqual:@"admitted"] ||
        ![request[@"connection_id"] isEqual:state.connectionID] ||
        ![request[@"session_id"] isEqual:state.sessionID] ||
        ![request[@"grant_id"] isEqual:state.grantID] ||
        ![state.operations containsObject:operation]) {
        return AQServiceFail(error, AQServiceOperationDenied) ? nil : nil;
    }
    uint64_t epoch = 0, sequence = 0, generation = 0;
    if (!AQServiceUnsignedInteger(request[@"epoch"], 0, INT64_MAX, &epoch) ||
        !AQServiceUnsignedInteger(request[@"sequence"], 1, INT64_MAX, &sequence) ||
        !AQServiceUnsignedInteger(request[@"expected_generation"], 0, INT64_MAX, &generation) ||
        epoch != state.storeEpoch) {
        return AQServiceFail(error, AQServiceBindingMismatch) ? nil : nil;
    }
    if (state.deadlineNanoseconds <= self.clock.monotonicNanoseconds) {
        return AQServiceFail(error, AQServiceConsentExpired) ? nil : nil;
    }
    NSDictionary *recovery = [self.store classifyRecovery];
    BOOL currentFreshSessionMayOperateDuringRecovery = state.admittedDuringFreshRecovery &&
        ([operation isEqual:@"stage"] || [operation isEqual:@"export"]) &&
        [state.phase isEqual:@"admitted"] && AQServiceRecoveryFreshAdmissionConsumed(recovery);
    if (![operation isEqual:@"eligibility"] &&
        ![recovery[@"state"] isEqual:@"clean"] && !currentFreshSessionMayOperateDuringRecovery) {
        return AQServiceFail(error, AQServiceStoreDenied) ? nil : nil;
    }
    if ([operation isEqual:@"cleanup"] && !state.cleanupAuthorized) {
        return AQServiceFail(error, AQServiceOperationDenied) ? nil : nil;
    }
    NSDictionary<NSString *, NSNumber *> *validatedFDs = nil;
    NSMutableArray<NSDictionary *> *sources = [NSMutableArray array];
    if (isStage) {
        NSArray<NSString *> *paths = nil;
        NSArray<NSDictionary *> *signedIdentities = nil;
        if (!AQServicePathArray(request[@"source_paths"], &paths) ||
            !AQServiceSignedSourceIdentities(request[@"source_identities"], paths,
                                             &signedIdentities) ||
            ![sourceFDs isKindOfClass:NSDictionary.class] || sourceFDs.count != paths.count) {
            return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
        }
        NSMutableDictionary<NSString *, NSNumber *> *bounded = [NSMutableDictionary dictionary];
        for (NSUInteger index = 0; index < paths.count; ++index) {
            NSString *path = paths[index];
            NSNumber *fdNumber = sourceFDs[path];
            if (![fdNumber isKindOfClass:NSNumber.class]) {
                return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
            }
            int fd = [fdNumber intValue];
            NSDictionary *actualIdentity = AQServiceActualSourceIdentity(path, fd);
            if (actualIdentity == nil || ![actualIdentity isEqual:signedIdentities[index]]) {
                return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
            }
            bounded[path] = @(fd);
            [sources addObject:actualIdentity];
        }
        [sources sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [(NSString *)left[@"path"] compare:(NSString *)right[@"path"]];
        }];
        validatedFDs = bounded;
    } else if (sourceFDs != nil && sourceFDs.count != 0) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }

    NSString *sessionID = state.sessionID;
    NSString *grantID = state.grantID;
    if (sessionID == nil || grantID == nil) {
        return AQServiceFail(error, AQServiceBindingMismatch) ? nil : nil;
    }
    NSDictionary *storeRequest = @{
        @"session_id": sessionID,
        @"grant_id": grantID,
        @"connection_id": state.connectionID,
        @"epoch": @(epoch),
        @"operation": operation,
        @"sequence": @(sequence),
        @"request_sha256": @"",
        @"expected_generation": @(generation)
    };
    NSMutableDictionary *digestInput = [storeRequest mutableCopy];
    [digestInput removeObjectForKey:@"request_sha256"];
    digestInput[@"request_id"] = request[@"request_id"];
    digestInput[@"sources"] = sources;
    NSError *digestError = nil;
    NSString *requestDigest = AQDigest(AQServiceRequestDigestDomain, digestInput, &digestError);
    if (requestDigest == nil) return AQServiceFail(error, AQServiceInternalFailure) ? nil : nil;
    NSMutableDictionary *boundRequest = [storeRequest mutableCopy];
    boundRequest[@"request_sha256"] = requestDigest;

    NSError *storeError = nil;
    NSDictionary *result = nil;
    if ([operation isEqual:@"stage"]) {
        if (validatedFDs == nil) {
            return AQServiceFail(error, AQServiceInternalFailure) ? nil : nil;
        }
        result = [self.store stageRequest:boundRequest sourceFDs:validatedFDs error:&storeError];
    } else if ([operation isEqual:@"eligibility"]) {
        result = [self.store eligibilityForRequest:boundRequest error:&storeError];
    } else if ([operation isEqual:@"cleanup"]) {
        result = [self.store cleanupRequest:boundRequest error:&storeError];
    } else if ([operation isEqual:@"export"]) {
        if (![self.store reserveReceiptCapacityForSessionID:sessionID error:&storeError]) {
            return AQServiceFail(error, AQServiceReceiptCapacityDenied) ? nil : nil;
        }
        int fd = [self.store exportPipeForRequest:boundRequest error:&storeError];
        if (fd >= 0) {
            result = @{
                @"export_transport": @"anonymous_pipe_read_only",
                @"receiver_verification": @"required",
                @"delivery": @"not_yet_confirmed"
            };
            if (exportFileDescriptor != NULL) *exportFileDescriptor = fd;
        }
    }
    if (result == nil) {
        AQServiceFail(error, [self codeForStoreError:storeError]);
        return nil;
    }
    return @{
        @"store": result,
        @"operation": operation,
        @"owner_approval": @"not_checked",
        @"byte_integrity": [operation isEqual:@"stage"] ? @"store_verified_pending" : @"not_checked"
    };
}


static BOOL AQServiceValidatePlan(NSData *planData,
                                  NSDictionary *manifest,
                                  NSDictionary *contract,
                                  AQServiceConnectionState *state,
                                  NSDictionary * _Nullable * _Nullable coverage,
                                  NSError **error) {
    NSError *parseError = nil;
    id parsed = AQParseJSON(planData, &parseError);
    if (![parsed isKindOfClass:NSDictionary.class]) {
        return AQServiceFail(error, AQServiceInvalidRequest);
    }
    NSDictionary *plan = parsed;
    uint64_t schemaVersion = 0;
    if (!AQServiceUnsignedInteger(plan[@"schema_version"], 1, 1, &schemaVersion) ||
        !AQServiceUnsignedInteger(plan[@"host_reserve_bytes"], 0, INT64_MAX, NULL) ||
        [plan[@"host_reserve_bytes"] unsignedLongLongValue] != state.hostReserveBytes) {
        return AQServiceFail(error, AQServiceInvalidRequest);
    }
    NSDictionary *ruleObject = plan[@"rules"];
    if (![ruleObject isKindOfClass:NSDictionary.class]) {
        return AQServiceFail(error, AQServiceInvalidRequest);
    }
    NSString *ruleDigest = AQDigest(@"", ruleObject, NULL);
    if (![ruleDigest isEqual:state.rulesSHA256]) {
        return AQServiceFail(error, AQServiceCoverageDenied);
    }
    NSDictionary *planCoverage = plan[@"fixture_coverage"];
    NSArray<NSString *> *coverageKeys = @[
        @"mode", @"required_fixture_ids", @"selected_fixture_ids", @"mandatory_fixture_ids"
    ];
    if (!AQServiceExactKeys(planCoverage, coverageKeys) ||
        ![planCoverage[@"mode"] isKindOfClass:NSString.class]) {
        return AQServiceFail(error, AQServiceInvalidRequest);
    }
    NSString *mode = planCoverage[@"mode"];
    NSArray<NSString *> *required = nil, *selected = nil, *mandatory = nil;
    if (!AQServiceStringArray(planCoverage[@"required_fixture_ids"], NO, &required) ||
        !AQServiceStringArray(planCoverage[@"selected_fixture_ids"], NO, &selected) ||
        !AQServiceStringArray(planCoverage[@"mandatory_fixture_ids"], YES, &mandatory)) {
        return AQServiceFail(error, AQServiceInvalidRequest);
    }
    if (![mode isEqual:manifest[@"coverage_mode"]] ||
        ![selected isEqualToArray:(NSArray<NSString *> *)manifest[@"selected_fixture_ids"]]) {
        return AQServiceFail(error, AQServiceCoverageDenied);
    }
    NSMutableArray<NSString *> *contractIDs = [NSMutableArray array];
    for (id fixture in contract[@"fixtures"]) {
        if (![fixture isKindOfClass:NSDictionary.class]) {
            return AQServiceFail(error, AQServiceInternalFailure);
        }
        NSString *fixtureID = fixture[@"fixture_id"];
        if (!AQServiceToken(fixtureID)) {
            return AQServiceFail(error, AQServiceInternalFailure);
        }
        [contractIDs addObject:fixtureID];
    }
    if (![selected isEqualToArray:contractIDs]) {
        return AQServiceFail(error, AQServiceCoverageDenied);
    }
    NSSet *requiredSet = [NSSet setWithArray:required];
    NSSet *selectedSet = [NSSet setWithArray:selected];
    NSSet *mandatorySet = [NSSet setWithArray:mandatory];
    for (NSString *fixtureID in selectedSet) {
        if (![requiredSet containsObject:fixtureID]) {
            return AQServiceFail(error, AQServiceCoverageDenied);
        }
    }
    if (![selectedSet isSubsetOfSet:requiredSet] ||
        ![mandatorySet isSubsetOfSet:selectedSet]) {
        return AQServiceFail(error, AQServiceCoverageDenied);
    }
    if ([mode isEqual:@"mandatory_full_plan"]) {
        if (![selectedSet isEqualToSet:requiredSet] || ![mandatorySet isEqualToSet:requiredSet]) {
            return AQServiceFail(error, AQServiceCoverageDenied);
        }
    } else if ([mode isEqual:@"authorized_partial_plan"]) {
        if (selectedSet.count >= requiredSet.count) {
            return AQServiceFail(error, AQServiceCoverageDenied);
        }
    } else {
        return AQServiceFail(error, AQServiceCoverageDenied);
    }
    if (coverage != NULL) {
        *coverage = @{
            @"mode": mode,
            @"required_fixture_ids": required,
            @"selected_fixture_ids": selected,
            @"mandatory_fixture_ids": mandatory
        };
    }
    return YES;
}

- (nullable NSDictionary *)handleAdmit:(NSDictionary *)request
                               documents:(NSDictionary *)documents
                                   state:(AQServiceConnectionState *)state
                                   error:(NSError **)error {
    NSArray<NSString *> *requestKeys = @[
        @"schema_version", @"operation", @"request_id", @"connection_id", @"session_id",
        @"consent_sha256"
    ];
    NSArray<NSString *> *documentKeys = @[
        @"consent", @"signature", @"manifest", @"plan", @"oracles", @"evidence"
    ];
    if (!AQServiceExactKeys(request, requestKeys) || !AQServiceExactKeys(documents, documentKeys)) {
        return AQServiceFail(error, AQServiceInvalidRequest) ? nil : nil;
    }
    if (![state.phase isEqual:@"owner_consent_pending"] ||
        !AQServiceToken(request[@"request_id"]) ||
        ![request[@"connection_id"] isEqual:state.connectionID] ||
        ![request[@"session_id"] isEqual:state.sessionID] ||
        !AQServiceDigestString(request[@"consent_sha256"])) {
        return AQServiceFail(error, AQServiceBindingMismatch) ? nil : nil;
    }
    if (state.deadlineNanoseconds <= self.clock.monotonicNanoseconds) {
        return AQServiceFail(error, AQServiceConsentExpired) ? nil : nil;
    }
    NSData *consent = nil, *signature = nil;
    if (!AQServiceData(documents[@"consent"], AQServiceMaximumRequestBytes, YES, &consent) ||
        !AQServiceData(documents[@"signature"], AQServiceMaximumSignatureBytes, YES, &signature)) {
        AQServiceFail(error, AQServiceInvalidRequest);
        state.phase = @"invalidated";
        return nil;
    }
    NSData *storedConsent = state.consentEnvelope;
    if (storedConsent == nil || ![storedConsent isEqualToData:consent]) {
        AQServiceFail(error, AQServiceBindingMismatch);
        state.phase = @"invalidated";
        return nil;
    }
    NSError *parseError = nil;
    id consentObject = AQParseJSON(consent, &parseError);
    if (![consentObject isKindOfClass:NSDictionary.class] ||
        ![request[@"consent_sha256"] isEqual:AQDigest(@"", consentObject, NULL)]) {
        AQServiceFail(error, AQServiceBindingMismatch);
        state.phase = @"invalidated";
        return nil;
    }

    __block BOOL signatureAccepted = NO;
    @try {
        NSError *verificationError = nil;
        signatureAccepted = self.ownerVerifier(consent, signature, &verificationError);
    } @catch (__unused NSException *exception) {
        signatureAccepted = NO;
    }
    if (!signatureAccepted) {
        AQServiceFail(error, AQServiceConsentDenied);
        state.phase = @"invalidated";
        return nil;
    }

    // Payload access begins only after the stored consent and owner signature
    // bind this request to the hello challenge.
    NSData *manifestData = nil, *planData = nil;
    if (!AQServiceData(documents[@"manifest"], AQServiceMaximumDocumentBytes, YES, &manifestData) ||
        !AQServiceData(documents[@"plan"], AQServiceMaximumDocumentBytes, YES, &planData) ||
        ![documents[@"oracles"] isKindOfClass:NSArray.class] ||
        ![documents[@"evidence"] isKindOfClass:NSArray.class]) {
        AQServiceFail(error, AQServiceInvalidRequest);
        state.phase = @"invalidated";
        return nil;
    }
    NSUInteger documentBytes = manifestData.length + planData.length;
    NSUInteger oracleBytes = 0, evidenceBytes = 0;
    if (!AQServiceDataArray(documents[@"oracles"], 0, AQServiceMaximumDocuments,
                            &oracleBytes, error) ||
        !AQServiceDataArray(documents[@"evidence"], 0, AQServiceMaximumDocuments,
                            &evidenceBytes, error) ||
        documentBytes > AQServiceMaximumTotalDocumentBytes - oracleBytes ||
        documentBytes + oracleBytes > AQServiceMaximumTotalDocumentBytes - evidenceBytes) {
        state.phase = @"invalidated";
        return nil;
    }

    id manifestObject = AQParseJSON(manifestData, &parseError);
    if (![manifestObject isKindOfClass:NSDictionary.class]) {
        AQServiceFail(error, AQServiceInvalidRequest);
        state.phase = @"invalidated";
        return nil;
    }
    NSError *contractError = nil;
    NSString *manifestSHA256 = state.manifestSHA256;
    NSString *planSHA256 = state.planSHA256;
    NSString *rulesSHA256 = state.rulesSHA256;
    if (manifestSHA256 == nil || planSHA256 == nil || rulesSHA256 == nil) {
        AQServiceFail(error, AQServiceBindingMismatch);
        state.phase = @"invalidated";
        return nil;
    }
    NSDictionary *contract = AQValidateSnapshotContract(
        manifestData, (NSArray<NSData *> *)documents[@"oracles"],
        (NSArray<NSData *> *)documents[@"evidence"], manifestSHA256,
        planSHA256, rulesSHA256, &contractError);
    if (contract == nil) {
        AQServiceErrorCode failure = AQServiceCoverageDenied;
        if ([contractError.domain isEqual:AQContractErrorDomain] &&
            (contractError.code == AQInputInvalid || contractError.code == AQLimitExceeded ||
             contractError.code == AQPinMismatch)) failure = AQServiceInvalidRequest;
        AQServiceFail(error, failure);
        state.phase = @"invalidated";
        return nil;
    }
    for (NSDictionary *assessment in contract[@"fixtures"]) {
        NSString *origin = assessment[@"corpus_origin"];
        NSString *support = assessment[@"independent_support"];
        if (![assessment[@"byte_integrity"] isEqual:@"not_checked"] ||
            ![assessment[@"owner_approval"] isEqual:@"not_checked"]) {
            AQServiceFail(error, AQServiceInternalFailure);
            state.phase = @"invalidated";
            return nil;
        }
        if ([origin isEqual:@"owner_private_genuine"] &&
            ![support isEqual:@"verified_independent_reference"]) {
            AQServiceFail(error, AQServiceReferenceDenied);
            state.phase = @"invalidated";
            return nil;
        }
    }

    NSDictionary *coverage = nil;
    if (!AQServiceValidatePlan(planData, manifestObject, contract, state, &coverage, error)) {
        state.phase = @"invalidated";
        return nil;
    }
    id planObject = AQParseJSON(planData, &parseError);
    if (![planObject isKindOfClass:NSDictionary.class]) {
        AQServiceFail(error, AQServiceInvalidRequest);
        state.phase = @"invalidated";
        return nil;
    }
    NSString *planDigest = AQDigest(@"", planObject, NULL);
    if (![planDigest isEqual:planSHA256]) {
        AQServiceFail(error, AQServiceCoverageDenied);
        state.phase = @"invalidated";
        return nil;
    }

    NSString *sessionID = state.sessionID;
    NSString *grantID = state.grantID;
    NSArray<NSString *> *operations = state.operations;
    if (sessionID == nil || grantID == nil || operations == nil) {
        AQServiceFail(error, AQServiceBindingMismatch);
        state.phase = @"invalidated";
        return nil;
    }
    NSDictionary *authority = @{
        @"session_id": sessionID,
        @"grant_id": grantID,
        @"connection_id": state.connectionID,
        @"epoch": @(state.storeEpoch),
        @"manifest_sha256": manifestSHA256,
        @"plan_sha256": planSHA256,
        @"rules_sha256": rulesSHA256,
        @"deadline_ticks": @(state.storeDeadlineTicks),
        @"host_reserve_bytes": @(state.hostReserveBytes),
        @"destination_reserve_bytes": @(state.destinationReserveBytes),
        @"operations": operations
    };
    NSDictionary *recoveryBeforeAdmission = [self.store classifyRecovery];
    BOOL admittedDuringFreshRecovery =
        AQServiceRecoveryIsRestartBlocked(recoveryBeforeAdmission) &&
        [recoveryBeforeAdmission[@"fresh_admission_available"] boolValue];
    if (!AQServiceRecoveryAllowsFreshAdmission(recoveryBeforeAdmission)) {
        AQServiceFail(error, AQServiceStoreDenied);
        state.phase = @"invalidated";
        return nil;
    }
    NSError *storeError = nil;
    BOOL receiptCapacityDenied = NO;
    NSDictionary *admitted = AQServiceAdmitWithReceiptReservation(
        self.store, sessionID, operations, manifestObject, authority,
        &receiptCapacityDenied, &storeError);
    if (receiptCapacityDenied) {
        AQServiceFail(error, AQServiceReceiptCapacityDenied);
        state.phase = @"invalidated";
        return nil;
    }
    if (admitted == nil) {
        AQServiceFail(error, [self codeForStoreError:storeError]);
        state.phase = @"invalidated";
        return nil;
    }

    state.admittedDuringFreshRecovery = admittedDuringFreshRecovery;
    state.phase = @"admitted";
    NSMutableArray<NSString *> *fixtureIDs = [NSMutableArray array];
    NSMutableArray<NSString *> *support = [NSMutableArray array];
    for (NSDictionary *assessment in contract[@"fixtures"]) {
        NSString *fixtureID = assessment[@"fixture_id"];
        NSString *supportTier = assessment[@"independent_support"];
        if (fixtureID == nil || supportTier == nil) {
            AQServiceFail(error, AQServiceInternalFailure);
            state.phase = @"invalidated";
            return nil;
        }
        [fixtureIDs addObject:fixtureID];
        [support addObject:supportTier];
    }
    NSString *contractManifestSHA256 = contract[@"manifest_sha256"];
    NSString *sourceAuthority = contract[@"source_authority"];
    if (contractManifestSHA256 == nil || sourceAuthority == nil) {
        AQServiceFail(error, AQServiceInternalFailure);
        state.phase = @"invalidated";
        return nil;
    }
    return @{
        @"store": admitted,
        @"manifest_sha256": contractManifestSHA256,
        @"source_authority": sourceAuthority,
        @"selected_fixture_ids": fixtureIDs,
        @"oracle_support": support,
        @"coverage": coverage,
        @"owner_consent": @"verified_by_installed_owner_key",
        @"owner_approval": @"not_checked",
        @"byte_integrity": @"not_checked"
    };
}

@end
