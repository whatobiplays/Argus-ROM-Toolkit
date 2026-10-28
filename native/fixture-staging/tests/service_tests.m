#import "AQJSON.h"
#import "AQServiceProtocol.h"
#import "AQServiceReceiptJournal.h"
#import "AQTiming.h"

#import <xpc/xpc.h>
#include <mach/mach_time.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef AQ_SERVICE_TESTING
@interface AQServiceReceiptJournal (ReservationReleaseTesting)
- (BOOL)syncDirectoryForReservationRelease;
@end

@interface AQFailingReleaseSyncReceiptJournal : AQServiceReceiptJournal
@property(nonatomic) BOOL failNextReservationReleaseSync;
@end

@implementation AQFailingReleaseSyncReceiptJournal
- (BOOL)syncDirectoryForReservationRelease {
    if (self.failNextReservationReleaseSync) {
        self.failNextReservationReleaseSync = NO;
        return NO;
    }
    return [super syncDirectoryForReservationRelease];
}
@end

void AQServiceResetWireAccessCountersForTesting(void);
NSUInteger AQServiceDocumentAccessCountForTesting(void);
NSUInteger AQServiceDescriptorDecodeCountForTesting(void);
NSUInteger AQServiceDescriptorDuplicateCountForTesting(void);
NSUInteger AQServiceDispatchCountForTesting(void);
BOOL AQServiceHandleWireMessageForTesting(AQServiceSessionCore *core, NSString *connectionID,
                                          xpc_object_t event, NSDictionary **responseOut,
                                          NSString **invalidationReasonOut);
BOOL AQServiceRecoveryAllowsFreshAdmissionForTesting(NSDictionary *classification);
NSDictionary *AQServiceAdmitWithReceiptReservationForTesting(
    id<AQServiceStore> store, NSString *sessionID, NSArray<NSString *> *operations,
    NSDictionary *manifest, NSDictionary *authority, BOOL *capacityDenied, NSError **error);
void AQServiceSetReceiptJournalForTesting(AQServiceReceiptJournal *journal);
int AQServiceWriteSelfCheckOutputForTesting(NSData *encoded, FILE *stream);
#endif

static int serviceFailures;

#define SERVICE_CHECK(value) do { \
    if (!(value)) { fprintf(stderr, "service FAIL %s:%d: %s\n", __func__, __LINE__, #value); \
        serviceFailures++; } \
} while (0)

@interface AQServiceTestStore : NSObject <AQServiceStore>
@property(nonatomic) NSUInteger revokedCount;
@property(nonatomic) NSUInteger recoveryCount;
@property(nonatomic) NSUInteger callbackCount;
@property(nonatomic, copy, nullable) NSDictionary *lastStageRequest;
@property(nonatomic, copy, nullable) NSDictionary<NSString *, NSNumber *> *lastStageSourceFDs;
@property(nonatomic, copy, nullable) NSDictionary *recoveryClassification;
@property(nonatomic, strong, nullable) NSNumber *exportPipeDescriptorForTesting;
@property(nonatomic) BOOL rejectReceiptCapacity;
@property(nonatomic) BOOL rejectAdmission;
@property(nonatomic) BOOL hasExistingReceiptReservation;
@property(nonatomic) BOOL rejectReceiptReservationRelease;
@property(nonatomic) BOOL receiptReservationRetained;
@property(nonatomic) NSUInteger receiptReservationCount;
@property(nonatomic) NSUInteger receiptReservationReleaseCount;
@property(nonatomic, strong, nullable) AQServiceReceiptJournal *receiptJournalForTesting;
@end

@implementation AQServiceTestStore
- (BOOL)reserveReceiptCapacityForSessionID:(NSString *)sessionID error:(NSError **)error {
    self.receiptReservationCount++;
    if (self.receiptJournalForTesting != nil) {
        return [self.receiptJournalForTesting reserveCapacityForSessionID:sessionID error:error];
    }
    BOOL reserved = !self.rejectReceiptCapacity;
    if (reserved) self.receiptReservationRetained = YES;
    return reserved;
}
- (BOOL)reserveReceiptCapacityForSessionID:(NSString *)sessionID
                                    created:(BOOL *)created
                                      error:(NSError **)error {
    if (self.receiptJournalForTesting != nil) {
        self.receiptReservationCount++;
        return [self.receiptJournalForTesting reserveCapacityForSessionID:sessionID
            created:created error:error];
    }
    BOOL reserved = [self reserveReceiptCapacityForSessionID:sessionID error:error];
    if (created != NULL) *created = reserved && !self.hasExistingReceiptReservation;
    return reserved;
}
- (BOOL)releaseReceiptCapacityForSessionID:(NSString *)sessionID
                                      error:(NSError **)error {
    self.receiptReservationReleaseCount++;
    if (self.receiptJournalForTesting != nil) {
        return [self.receiptJournalForTesting releaseCapacityForSessionID:sessionID error:error];
    }
    if (self.rejectReceiptReservationRelease) {
        if (error != NULL) *error = AQServiceError(AQServiceStoreDenied);
        return NO;
    }
    self.receiptReservationRetained = NO;
    return YES;
}
- (NSDictionary *)admitManifest:(__unused NSDictionary *)manifest
                      authority:(NSDictionary *)authority error:(__unused NSError **)error {
    self.callbackCount++;
    if (self.rejectAdmission) return nil;
    return @{@"state": @"admitted", @"session_id": (id)authority[@"session_id"]};
}
- (NSDictionary *)stageRequest:(__unused NSDictionary *)request
                     sourceFDs:(NSDictionary<NSString *,NSNumber *> *)sourceFDs
                         error:(__unused NSError **)error {
    self.callbackCount++;
    self.lastStageRequest = request;
    self.lastStageSourceFDs = sourceFDs;
    return @{@"state": @"published"};
}
- (NSDictionary *)inspectSession:(NSString *)sessionID {
    self.callbackCount++;
    return @{@"session_id": sessionID, @"state": @"owner_consent_pending"};
}
- (NSDictionary *)eligibilityForRequest:(__unused NSDictionary *)request
                                  error:(__unused NSError **)error {
    self.callbackCount++;
    return @{@"eligible": @YES};
}
- (int)exportPipeForRequest:(__unused NSDictionary *)request error:(__unused NSError **)error {
    self.callbackCount++;
    return self.exportPipeDescriptorForTesting == nil ? -1 : self.exportPipeDescriptorForTesting.intValue;
}
- (NSDictionary *)cleanupRequest:(__unused NSDictionary *)request
                           error:(__unused NSError **)error {
    self.callbackCount++;
    return @{@"state": @"cleaned"};
}
- (NSDictionary *)classifyRecovery {
    self.recoveryCount++;
    return self.recoveryClassification ?: @{@"state": @"clean", @"sessions": @0};
}
- (void)revokeSession:(__unused NSString *)sessionID reason:(__unused NSString *)reason {
    self.callbackCount++;
    _revokedCount++;
}
@end

@interface AQServiceTestClock : NSObject <AQServiceClock>
@property(nonatomic) uint64_t nanoseconds;
@property(nonatomic) uint64_t storeTicks;
@end
@implementation AQServiceTestClock
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _nanoseconds = 1;
    _storeTicks = 1;
    return self;
}
- (uint64_t)monotonicNanoseconds { return self.nanoseconds; }
- (uint64_t)continuousTicks { return self.storeTicks; }
@end

@interface AQServiceSessionCore (TestMutationObservation)
- (BOOL)recordRequestSequence:(uint64_t)sequence state:(id)state error:(NSError **)error;
@end

@interface AQServiceObservingCore : AQServiceSessionCore
@property(nonatomic) NSUInteger recordMutationCount;
@end

@implementation AQServiceObservingCore
- (BOOL)recordRequestSequence:(uint64_t)sequence state:(id)state error:(NSError **)error {
    self.recordMutationCount++;
    return [super recordRequestSequence:sequence state:state error:error];
}
@end

static NSDictionary *TestReviewAuthorizationObject(void) {
    return @{
        @"authorization_id": @"synthetic-review-v1",
        @"fixture_manifest_sha256": [@"c" stringByPaddingToLength:64
            withString:@"c" startingAtIndex:0],
        @"plan": @{
            @"plan_sha256": [@"d" stringByPaddingToLength:64
                withString:@"d" startingAtIndex:0],
            @"rules_sha256": [@"e" stringByPaddingToLength:64
                withString:@"e" startingAtIndex:0],
        },
    };
}

static NSData *TestReviewAuthorization(void) {
    return AQCanonicalJSON(TestReviewAuthorizationObject(), NULL);
}

static NSString *TestReviewAuthorizationSHA256(void) {
    return AQDigest(@"", TestReviewAuthorizationObject(), NULL) ?: @"";
}

static NSString *TestHelloNonceForBoot(uint64_t sequence, NSString *serviceBootID,
                                      NSString *authorizationSHA256) {
    return AQDigest(@"argus.fixture-staging.hello-nonce.v1", @{
        @"installation_id": @"installation-1",
        @"service_boot_id": serviceBootID,
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"sequence": @(sequence),
        @"authorization_sha256": authorizationSHA256,
    }, NULL);
}

static NSString *TestHelloNonce(uint64_t sequence) {
    return TestHelloNonceForBoot(sequence, @"boot-1", TestReviewAuthorizationSHA256());
}

static NSDictionary *TestHello(void) {
    NSString *authorizationSHA256 = TestReviewAuthorizationSHA256();
    NSString *nonce = TestHelloNonce(1);
    return @{
        @"schema_version": @1, @"operation": @"hello", @"request_id": @"request-1",
        @"nonce": nonce, @"grant_id": @"grant-1", @"sequence": @1,
        @"service_boot_id": @"boot-1",
        @"installation_id": @"installation-1", @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"authorization": TestReviewAuthorization(),
        @"authorization_sha256": authorizationSHA256,
        @"approval_sha256": [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0],
        @"manifest_sha256": [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0],
        @"plan_sha256": [@"d" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0],
        @"rules_sha256": [@"e" stringByPaddingToLength:64 withString:@"e" startingAtIndex:0],
        @"operations": @[@"stage", @"eligibility", @"export", @"cleanup"],
        @"deadline_ns": @(1 + 3600ULL * NSEC_PER_SEC),
        @"store_deadline_ticks": @1000, @"host_reserve_bytes": @100,
        @"destination_reserve_bytes": @200, @"cleanup_authorized": @YES
    };
}

static NSMutableDictionary *TestSignedRequest(NSDictionary *body,
                                              NSString *connectionID,
                                              NSString *sessionID,
                                              uint64_t __unused epoch,
                                              uint64_t sequence,
                                              NSNumber *deadline,
                                              NSString *authorizationSHA256,
                                              NSDictionary *overrides) {
    NSMutableDictionary *content = [body mutableCopy];
    [content removeObjectForKey:@"request_id"];
    NSString *requestDigest = AQDigest(@"argus.fixture-staging.request.v1", content, NULL);
    if (requestDigest == nil) return nil;
    NSString *requestID = AQDigest(@"argus.fixture-staging.request-id.v1", @{
        @"session_id": sessionID,
        @"sequence": @(sequence),
        @"operation": (NSString *)body[@"operation"],
        @"request_sha256": requestDigest
    }, NULL);
    if (requestID == nil) return nil;
    NSMutableDictionary *identifiedBody = [body mutableCopy];
    identifiedBody[@"request_id"] = requestID;
    NSMutableDictionary *freshness = [@{
        @"schema_version": @1,
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"connection_id": connectionID,
        @"session_id": sessionID,
        @"request_id": requestID,
        @"sequence": @(sequence),
        @"operation": (NSString *)body[@"operation"],
        @"request_sha256": requestDigest,
        @"authorization_sha256": authorizationSHA256,
        @"consent_sha256": [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0],
        @"deadline_ns": deadline
    } mutableCopy];
    [freshness addEntriesFromDictionary:overrides];
    NSData *freshnessData = AQCanonicalJSON(freshness, NULL);
    if (freshnessData == nil) return nil;
    identifiedBody[@"freshness_envelope"] = [freshnessData base64EncodedStringWithOptions:0];
    identifiedBody[@"freshness_signature"] = [[@"owner-signature" dataUsingEncoding:NSUTF8StringEncoding]
        base64EncodedStringWithOptions:0];
    return identifiedBody;
}

static const uint64_t TestMaximumOperationNanoseconds = 3600ULL * NSEC_PER_SEC;

static NSMutableDictionary *TestHelloV2(uint64_t sequence, NSString * _Nullable nonce) {
    NSMutableDictionary *hello = [TestHello() mutableCopy];
    hello[@"sequence"] = @(sequence);
    hello[@"nonce"] = nonce ?: TestHelloNonce(sequence);
    return hello;
}

static NSString *TestRequestDigest(NSDictionary *body) {
    NSMutableDictionary *content = [body mutableCopy];
    [content removeObjectForKey:@"request_id"];
    [content removeObjectForKey:@"freshness_envelope"];
    [content removeObjectForKey:@"freshness_signature"];
    return AQDigest(@"argus.fixture-staging.request.v1", content, NULL);
}

static NSString *TestRequestID(NSDictionary *body, NSString *sessionID, uint64_t sequence) {
    NSString *digest = TestRequestDigest(body);
    if (digest == nil) return nil;
    return AQDigest(@"argus.fixture-staging.request-id.v1", @{
        @"session_id": sessionID,
        @"sequence": @(sequence),
        @"operation": (NSString *)body[@"operation"],
        @"request_sha256": digest
    }, NULL);
}

static NSMutableDictionary *TestSignedRequestV2(NSDictionary *body,
                                                NSString *connectionID,
                                                NSString *sessionID,
                                                uint64_t sequence,
                                                NSNumber *deadline,
                                                NSString *authorizationSHA256,
                                                NSDictionary *overrides) {
    NSString *requestDigest = TestRequestDigest(body);
    NSString *requestID = TestRequestID(body, sessionID, sequence);
    if (requestDigest == nil || requestID == nil) return nil;
    NSMutableDictionary *identifiedBody = [body mutableCopy];
    identifiedBody[@"request_id"] = requestID;
    NSMutableDictionary *freshness = [@{
        @"schema_version": @1,
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"connection_id": connectionID,
        @"session_id": sessionID,
        @"request_id": requestID,
        @"sequence": @(sequence),
        @"operation": (NSString *)body[@"operation"],
        @"request_sha256": requestDigest,
        @"authorization_sha256": authorizationSHA256,
        @"consent_sha256": [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0],
        @"deadline_ns": deadline
    } mutableCopy];
    [freshness addEntriesFromDictionary:overrides];
    NSData *freshnessData = AQCanonicalJSON(freshness, NULL);
    if (freshnessData == nil) return nil;
    identifiedBody[@"freshness_envelope"] = [freshnessData base64EncodedStringWithOptions:0];
    identifiedBody[@"freshness_signature"] = [[@"owner-signature" dataUsingEncoding:NSUTF8StringEncoding]
        base64EncodedStringWithOptions:0];
    return identifiedBody;
}

static NSDictionary *TestRecoveryBody(NSString *requestID, NSString *connectionID) {
    return @{
        @"schema_version": @1, @"operation": @"recovery",
        @"request_id": requestID, @"connection_id": connectionID
    };
}

@interface AQProtectedReadCounter : NSObject
@property(nonatomic) NSUInteger accessCount;
@end

@implementation AQProtectedReadCounter
- (void)recordAccess { self.accessCount++; }
@end

@interface AQProtectedPayloadProbe : NSProxy
@property(nonatomic, strong) id storage;
@property(nonatomic, strong) AQProtectedReadCounter *counter;
@end

@implementation AQProtectedPayloadProbe
- (instancetype)initWithStorage:(id)storage counter:(AQProtectedReadCounter *)counter {
    _storage = storage;
    _counter = counter;
    return self;
}
- (BOOL)isKindOfClass:(Class)aClass {
    return [self.storage isKindOfClass:aClass];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [self.storage methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    [self.counter recordAccess];
    [invocation invokeWithTarget:self.storage];
}
@end

static NSData *AQTestData(NSString *value) {
    return (NSData *)[value dataUsingEncoding:NSUTF8StringEncoding];
}

static void RunAdmitRejectsBeforeProtectedPayloadAccess(BOOL rejectSignature) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    __block NSUInteger verifierCalls = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
 serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
   ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
       ownerVerifier:^BOOL(NSData *consent, __unused NSData *signature,
                           __unused NSError **verifyError) {
           verifierCalls++;
           NSDictionary *envelope = AQParseJSON(consent, NULL);
           SERVICE_CHECK([envelope[@"owner_key_id"] isEqual:@"owner-key-1"]);
           SERVICE_CHECK([envelope[@"authorization_sha256"]
               isEqual:TestReviewAuthorizationSHA256()]);
           return !rejectSignature;
       }
  identifierGenerator:^NSString *{ token++; return [NSString stringWithFormat:@"token-%lu",
                                                        (unsigned long)token]; }
                error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error];
    int exportFD = -1;
    NSDictionary *hello = [core handleRequest:TestHello() documents:nil sourceFDs:nil
                                 connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(hello != nil);
    if (hello == nil) return;

    NSData *boundConsent = [[NSData alloc]
        initWithBase64EncodedString:(NSString *)hello[@"consent_envelope"] options:0];
    NSData *submittedConsent = rejectSignature ? boundConsent :
        [@"unbound-consent" dataUsingEncoding:NSUTF8StringEncoding];
    AQProtectedReadCounter *protectedReads = [[AQProtectedReadCounter alloc] init];
    AQProtectedPayloadProbe *manifest = [[AQProtectedPayloadProbe alloc]
        initWithStorage:AQTestData(@"manifest") counter:protectedReads];
    AQProtectedPayloadProbe *plan = [[AQProtectedPayloadProbe alloc]
        initWithStorage:AQTestData(@"plan") counter:protectedReads];
    AQProtectedPayloadProbe *oracles = [[AQProtectedPayloadProbe alloc]
        initWithStorage:@[AQTestData(@"oracle")] counter:protectedReads];
    AQProtectedPayloadProbe *evidence = [[AQProtectedPayloadProbe alloc]
        initWithStorage:@[AQTestData(@"evidence")] counter:protectedReads];
    NSData *signature = AQTestData(@"signature");
    SERVICE_CHECK(submittedConsent != nil);
    SERVICE_CHECK(signature != nil);
    SERVICE_CHECK(manifest != nil);
    SERVICE_CHECK(plan != nil);
    SERVICE_CHECK(oracles != nil);
    SERVICE_CHECK(evidence != nil);
    if (submittedConsent == nil || signature == nil || manifest == nil || plan == nil ||
        oracles == nil || evidence == nil) return;
    NSDictionary *documents = @{
        @"consent": submittedConsent,
        @"signature": signature,
        @"manifest": manifest, @"plan": plan, @"oracles": oracles, @"evidence": evidence
    };
    NSString *sessionID = (NSString *)hello[@"session_id"];
    NSString *consentSHA256 = rejectSignature ? (NSString *)hello[@"consent_sha256"] :
        [@"f" stringByPaddingToLength:64 withString:@"f" startingAtIndex:0];
    SERVICE_CHECK(sessionID != nil);
    SERVICE_CHECK(consentSHA256 != nil);
    if (sessionID == nil || consentSHA256 == nil) return;
    NSDictionary *admitBody = @{
        @"schema_version": @1, @"operation": @"admit", @"request_id": @"request-admit",
        @"connection_id": connection, @"session_id": sessionID,
        @"consent_sha256": consentSHA256
    };
    NSMutableDictionary *admitRequest = TestSignedRequest(admitBody, connection, sessionID, 1, 1,
        (NSNumber *)hello[@"deadline_ns"], (NSString *)TestHello()[@"authorization_sha256"], @{});
    SERVICE_CHECK(admitRequest != nil);
    if (admitRequest == nil) return;

    error = nil;
    NSDictionary *result = [core handleRequest:admitRequest documents:documents sourceFDs:nil
                                 connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:(rejectSignature ?
        @"OWNER_CONSENT_DENIED" : @"SESSION_BINDING_MISMATCH")]);
    SERVICE_CHECK(protectedReads.accessCount == 0);
    SERVICE_CHECK(verifierCalls == 1);
}

static void TestAdmitRejectsBeforeProtectedPayloadAccess(void) {
    RunAdmitRejectsBeforeProtectedPayloadAccess(NO);
    RunAdmitRejectsBeforeProtectedPayloadAccess(YES);
}

static void TestServiceSessionBinding(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
 serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
   ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
       ownerVerifier:^BOOL(__unused NSData *consent, __unused NSData *signature,
                           __unused NSError **verifyError) { return YES; }
  identifierGenerator:^NSString *{ token++; return [NSString stringWithFormat:@"token-%lu",
                                                        (unsigned long)token]; }
                error:&error];
    SERVICE_CHECK(core != nil);

    dispatch_queue_t firstPeerQueue = AQServiceSerialPeerQueue();
    dispatch_queue_t secondPeerQueue = AQServiceSerialPeerQueue();
    SERVICE_CHECK(firstPeerQueue != NULL && firstPeerQueue == secondPeerQueue);
    if (firstPeerQueue != NULL) {
        dispatch_semaphore_t firstEntered = dispatch_semaphore_create(0);
        dispatch_semaphore_t releaseFirst = dispatch_semaphore_create(0);
        dispatch_semaphore_t secondEntered = dispatch_semaphore_create(0);
        dispatch_semaphore_t releaseSecond = dispatch_semaphore_create(0);
        dispatch_async(firstPeerQueue, ^{
            dispatch_semaphore_signal(firstEntered);
            dispatch_semaphore_wait(releaseFirst, DISPATCH_TIME_FOREVER);
        });
        dispatch_async(secondPeerQueue, ^{
            dispatch_semaphore_signal(secondEntered);
            dispatch_semaphore_wait(releaseSecond, DISPATCH_TIME_FOREVER);
        });
        SERVICE_CHECK(dispatch_semaphore_wait(firstEntered,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        BOOL secondEnteredBeforeRelease =
            dispatch_semaphore_wait(secondEntered, DISPATCH_TIME_NOW) == 0;
        SERVICE_CHECK(!secondEnteredBeforeRelease);
        dispatch_semaphore_signal(releaseFirst);
        SERVICE_CHECK(dispatch_semaphore_wait(secondEntered,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        dispatch_semaphore_signal(releaseSecond);
        dispatch_sync(firstPeerQueue, ^{});
    }

    for (NSDictionary *request in @[
        @{@"schema_version": @1, @"operation": @"readiness", @"request_id": @"direct-readiness"},
        @{@"schema_version": @1, @"operation": @"inspect", @"request_id": @"direct-inspect",
          @"connection_id": @"direct-launch", @"session_id": @"session"},
        @{@"schema_version": @1, @"operation": @"recovery", @"request_id": @"direct-recovery",
          @"connection_id": @"direct-launch"}
    ]) {
        error = nil;
        int ignoredExportFD = -1;
        NSDictionary *result = [core handleRequest:request documents:nil sourceFDs:nil
            connectionID:@"direct-launch" exportFileDescriptor:&ignoredExportFD error:&error];
        SERVICE_CHECK(result == nil);
        SERVICE_CHECK([error.localizedDescription isEqual:@"UNAUTHENTICATED_CONNECTION"]);
    }

    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection.length != 0);
    int exportFD = -1;
    NSDictionary *readinessRequest = @{
        @"schema_version": @1, @"operation": @"readiness",
        @"request_id": @"request-readiness"
    };
    NSDictionary *readiness = [core handleRequest:readinessRequest documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK([readiness isEqualToDictionary:[core readinessFacts]]);
    SERVICE_CHECK([readiness[@"broker_revision"] isEqual:@"broker-1"]);
    SERVICE_CHECK([readiness[@"owner_key_id"] isEqual:@"owner-key-1"]);
    SERVICE_CHECK([core handleRequest:readinessRequest documents:@{} sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);

    NSMutableDictionary *missingOwnerKey = [TestHello() mutableCopy];
    [missingOwnerKey removeObjectForKey:@"owner_key_id"];
    error = nil;
    SERVICE_CHECK([core handleRequest:missingOwnerKey documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);

    NSMutableDictionary *wrongOwnerKey = [TestHello() mutableCopy];
    wrongOwnerKey[@"owner_key_id"] = @"owner-key-2";
    error = nil;
    SERVICE_CHECK([core handleRequest:wrongOwnerKey documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);

    NSDictionary *hello = [core handleRequest:TestHello() documents:nil sourceFDs:nil
                                 connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(hello != nil);
    if (hello == nil) return;
    SERVICE_CHECK([hello[@"session_id"] length] != 0);
    NSData *consent = [[NSData alloc] initWithBase64EncodedString:(NSString *)hello[@"consent_envelope"]
                                                           options:0];
    NSDictionary *envelope = consent == nil ? nil : AQParseJSON(consent, NULL);
    SERVICE_CHECK([envelope[@"owner_key_id"] isEqual:@"owner-key-1"]);
    SERVICE_CHECK([envelope[@"session_id"] isEqual:hello[@"session_id"]]);
    SERVICE_CHECK([envelope[@"connection_id"] isEqual:connection]);
    SERVICE_CHECK([envelope[@"operations"] count] == 4);

    NSDictionary *recoveryBody = @{
        @"schema_version": @1, @"operation": @"recovery", @"request_id": @"request-2",
        @"connection_id": connection
    };
    NSDictionary *recoveryRequest = TestSignedRequest(recoveryBody, connection,
        (NSString *)hello[@"session_id"], 1, 1, (NSNumber *)hello[@"deadline_ns"],
        (NSString *)TestHello()[@"authorization_sha256"], @{});
    SERVICE_CHECK(recoveryRequest != nil);
    if (recoveryRequest == nil) return;
    NSDictionary *recovery = [core handleRequest:recoveryRequest documents:nil sourceFDs:nil
                                    connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK([recovery[@"recovery"][@"state"] isEqual:@"clean"]);
    NSDictionary *facts = [core readinessFacts];
    SERVICE_CHECK([facts[@"python_destination"] isEqual:@"BLOCKED_UNSUPPORTED_EXCLUSIVITY"]);

    store.recoveryClassification = @{
        @"state": @"blocked_retained", @"reason": @"journal_corrupt", @"sessions": @0
    };
    NSDictionary *blockedFacts = [core readinessFacts];
    SERVICE_CHECK([blockedFacts[@"ready"] isEqual:@NO]);

    [core invalidateConnection:connection reason:@"test"];
    SERVICE_CHECK(store.revokedCount == 1);
    error = nil;
    SERVICE_CHECK([core handleRequest:recoveryRequest documents:nil sourceFDs:nil
                        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"UNAUTHENTICATED_CONNECTION"]);
}

static void TestServiceRejectsStaleSignedFreshnessBeforeDispatch(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    __block NSUInteger verifierCalls = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(NSData *__unused canonicalFreshness,
                            NSData *__unused signature,
                            __unused NSError **verifyError) {
            verifierCalls++;
            return YES;
        }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)token];
        }
        error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection.length != 0);
    NSMutableDictionary *hello = [TestHello() mutableCopy];
    hello[@"sequence"] = @2;
    hello[@"nonce"] = TestHelloNonce(2);
    int exportFD = -1;
    NSDictionary *helloResponse = [core handleRequest:hello documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(helloResponse != nil);
    if (helloResponse == nil) return;
    NSMutableDictionary *primer = TestSignedRequest(
        TestRecoveryBody(@"stale-sequence-primer", connection), connection,
        helloResponse[@"session_id"], 1, 1, hello[@"deadline_ns"],
        hello[@"authorization_sha256"], @{});
    SERVICE_CHECK(primer != nil);
    SERVICE_CHECK([core handleRequest:primer documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] != nil);
    NSMutableDictionary *request = TestSignedRequest(
        TestRecoveryBody(@"stale-sequence-request", connection), connection,
        helloResponse[@"session_id"], 1, 1, hello[@"deadline_ns"],
        hello[@"authorization_sha256"], @{});
    SERVICE_CHECK(request != nil);

    error = nil;
    SERVICE_CHECK([core handleRequest:request documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"REPLAY_REJECTED"]);
    SERVICE_CHECK(verifierCalls == 2);
    SERVICE_CHECK(store.recoveryCount == 1);
}

#if defined(AQ_SERVICE_TESTING) && !defined(AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN)
static xpc_object_t TestWireMessageWithProtectedPayload(NSDictionary *request, int *sourceFDOut) {
    NSError *error = nil;
    NSData *requestData = AQCanonicalJSON(request, &error);
    SERVICE_CHECK(requestData != nil);
    if (requestData == nil) return NULL;

    char temporaryPath[] = "/tmp/argus-service-wire-fd.XXXXXX";
    int sourceFD = mkstemp(temporaryPath);
    SERVICE_CHECK(sourceFD >= 0);
    if (sourceFD < 0) return NULL;
    unlink(temporaryPath);

    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(message, "version", 1);
    xpc_dictionary_set_data(message, "request", requestData.bytes, requestData.length);
    xpc_object_t documents = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(documents, "protected_read", "sentinel");
    xpc_dictionary_set_value(message, "documents", documents);
    xpc_object_t descriptors = xpc_array_create(NULL, 0);
    xpc_array_set_fd(descriptors, XPC_ARRAY_APPEND, sourceFD);
    xpc_dictionary_set_value(message, "source_fds", descriptors);
    *sourceFDOut = sourceFD;
    return message;
}

static xpc_object_t TestWireHelloMessage(NSDictionary *hello, NSData * _Nullable authorization) {
    NSMutableDictionary *wireRequest = [hello mutableCopy];
    [wireRequest removeObjectForKey:@"authorization"];
    NSData *requestData = AQCanonicalJSON(wireRequest, NULL);
    if (requestData == nil) return NULL;
    const void * _Nullable authorizationBytes = NULL;
    if (authorization != nil) {
        if (authorization.length == 0) return NULL;
        authorizationBytes = authorization.bytes;
        if (authorizationBytes == NULL) return NULL;
    }
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(message, "version", 1);
    xpc_dictionary_set_data(message, "request", requestData.bytes, requestData.length);
    if (authorization != nil) {
        const void * _Nonnull validatedAuthorizationBytes =
            (const void * _Nonnull)authorizationBytes;
        xpc_dictionary_set_data(message, "authorization", validatedAuthorizationBytes,
                                authorization.length);
    }
    return message;
}

static void TestWireHelloAuthorizationBinding(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"wire-hello-token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *firstConnection = [core openConnection:&error];
    NSDictionary *firstHello = TestHello();
    xpc_object_t firstMessage = TestWireHelloMessage(firstHello, TestReviewAuthorization());
    NSDictionary *response = nil;
    NSString *invalidation = nil;
    SERVICE_CHECK(AQServiceHandleWireMessageForTesting(core, firstConnection, firstMessage,
                                                       &response, &invalidation));
    SERVICE_CHECK([response[@"status"] isEqual:@"OK"]);

    NSString *missingConnection = [core openConnection:&error];
    xpc_object_t missingMessage = TestWireHelloMessage(TestHelloV2(2, nil), nil);
    response = nil;
    invalidation = nil;
    SERVICE_CHECK(AQServiceHandleWireMessageForTesting(core, missingConnection, missingMessage,
                                                       &response, &invalidation));
    SERVICE_CHECK([response[@"code"] isEqual:@"INVALID_REQUEST"]);

    NSString *substituteConnection = [core openConnection:&error];
    xpc_object_t substituteMessage = TestWireHelloMessage(TestHelloV2(2, nil),
        [@"{\"authorization_id\":\"synthetic-review-v2\"}" dataUsingEncoding:NSUTF8StringEncoding]);
    response = nil;
    invalidation = nil;
    SERVICE_CHECK(AQServiceHandleWireMessageForTesting(core, substituteConnection,
                                                       substituteMessage, &response, &invalidation));
    SERVICE_CHECK([response[@"code"] isEqual:@"SESSION_BINDING_MISMATCH"]);

    NSString *validConnection = [core openConnection:&error];
    xpc_object_t validMessage = TestWireHelloMessage(TestHelloV2(2, nil),
                                                     TestReviewAuthorization());
    response = nil;
    invalidation = nil;
    SERVICE_CHECK(AQServiceHandleWireMessageForTesting(core, validConnection, validMessage,
                                                       &response, &invalidation));
    SERVICE_CHECK([response[@"status"] isEqual:@"OK"]);
}

static void TestHelloRejectsAuthorizationPinMismatches(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"claim-check-token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil && error == nil);
    if (core == nil) return;

    for (NSString *claim in @[@"fixture_manifest_sha256", @"plan_sha256", @"rules_sha256"]) {
        NSMutableDictionary *authorization = [TestReviewAuthorizationObject() mutableCopy];
        if ([claim isEqual:@"fixture_manifest_sha256"]) {
            authorization[claim] = [@"f" stringByPaddingToLength:64
                withString:@"f" startingAtIndex:0];
        } else {
            NSMutableDictionary *plan = [authorization[@"plan"] mutableCopy];
            plan[claim] = [@"f" stringByPaddingToLength:64
                withString:@"f" startingAtIndex:0];
            authorization[@"plan"] = plan;
        }
        NSData *authorizationBytes = AQCanonicalJSON(authorization, NULL);
        NSString *authorizationSHA256 = AQDigest(@"", authorization, NULL);
        NSMutableDictionary *hello = [TestHello() mutableCopy];
        hello[@"authorization"] = authorizationBytes;
        hello[@"authorization_sha256"] = authorizationSHA256;
        hello[@"nonce"] = TestHelloNonceForBoot(
            1, @"boot-1", authorizationSHA256);

        NSString *connection = [core openConnection:&error];
        xpc_object_t message = TestWireHelloMessage(hello, authorizationBytes);
        NSDictionary *response = nil;
        NSString *invalidation = nil;
        SERVICE_CHECK(AQServiceHandleWireMessageForTesting(
            core, connection, message, &response, &invalidation));
        SERVICE_CHECK([response[@"status"] isEqual:@"BLOCKED"]);
        SERVICE_CHECK(store.callbackCount == 0);
    }
}

static void RunWireFreshnessRejection(BOOL wrongOwnerSignature, NSString *expectedCode) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    __block NSUInteger verifierCalls = 0;
    NSError *error = nil;
    AQServiceObservingCore *core = [[AQServiceObservingCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(NSData *__unused freshness, NSData *signature,
                            __unused NSError **verifyError) {
            verifierCalls++;
            return [signature isEqualToData:AQTestData(@"owner-signature")];
        } identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection.length != 0);
    NSMutableDictionary *hello = [TestHello() mutableCopy];
    hello[@"sequence"] = @2;
    hello[@"nonce"] = TestHelloNonce(2);
    int exportFD = -1;
    NSDictionary *helloResponse = [core handleRequest:hello documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(helloResponse != nil);
    if (helloResponse == nil) return;
    if (!wrongOwnerSignature) {
        NSMutableDictionary *primer = TestSignedRequest(
            TestRecoveryBody(@"wire-primer", connection), connection,
            helloResponse[@"session_id"], 1, 1, hello[@"deadline_ns"],
            hello[@"authorization_sha256"], @{});
        SERVICE_CHECK(primer != nil);
        SERVICE_CHECK([core handleRequest:primer documents:nil sourceFDs:nil
            connectionID:connection exportFileDescriptor:&exportFD error:&error] != nil);
    }
    NSUInteger recordMutationsAfterHello = core.recordMutationCount;
    NSUInteger callbacksBeforeStaleRequest = store.callbackCount;
    verifierCalls = 0;

    NSString *requestID = wrongOwnerSignature ? @"wire-wrong-owner-signature" : @"wire-stale-freshness";
    NSDictionary *body = TestRecoveryBody(requestID, connection);
    NSMutableDictionary *request = [TestSignedRequest(
        body, connection, helloResponse[@"session_id"], 1, 1,
        hello[@"deadline_ns"], hello[@"authorization_sha256"], @{}) mutableCopy];
    SERVICE_CHECK(request != nil);
    if (request == nil) return;
    if (wrongOwnerSignature) {
        request[@"freshness_signature"] = [AQTestData(@"wrong-owner-signature")
            base64EncodedStringWithOptions:0];
    }

    AQServiceResetWireAccessCountersForTesting();
    int sourceFD = -1;
    xpc_object_t message = TestWireMessageWithProtectedPayload(request, &sourceFD);
    SERVICE_CHECK(message != NULL);
    if (message == NULL) return;
    NSDictionary *response = nil;
    NSString *invalidationReason = nil;
    BOOL handled = AQServiceHandleWireMessageForTesting(
        core, connection, message, &response, &invalidationReason);

    SERVICE_CHECK(handled);
    SERVICE_CHECK([response[@"code"] isEqual:expectedCode]);
    SERVICE_CHECK([invalidationReason isEqual:@"protocol_rejection"]);
    SERVICE_CHECK(AQServiceDocumentAccessCountForTesting() == 0);
    SERVICE_CHECK(AQServiceDescriptorDecodeCountForTesting() == 0);
    SERVICE_CHECK(AQServiceDescriptorDuplicateCountForTesting() == 0);
    SERVICE_CHECK(AQServiceDispatchCountForTesting() == 0);
    SERVICE_CHECK(verifierCalls == 1);
    SERVICE_CHECK(store.callbackCount == callbacksBeforeStaleRequest);
    SERVICE_CHECK(core.recordMutationCount == recordMutationsAfterHello);
    close(sourceFD);
}

static void TestWireFreshnessRejectsBeforeProtectedPayloadAccess(void) {
    RunWireFreshnessRejection(NO, @"REPLAY_REJECTED");
    RunWireFreshnessRejection(YES, @"OWNER_CONSENT_DENIED");
}

static NSString *TestBrokerReceiptDigest(NSDictionary *completion) {
    NSMutableDictionary *digestPayload = [completion mutableCopy];
    [digestPayload removeObjectForKey:@"service_boot_id"];
    [digestPayload removeObjectForKey:@"sequence"];
    [digestPayload removeObjectForKey:@"receipt_sha256"];
    [digestPayload removeObjectForKey:@"receipt_path"];
    return AQDigest(@"", digestPayload, NULL) ?: @"";
}

static void TestAuthenticatedReceiptRecordAndQueryBoundary(void) {
    char directory[] = "/tmp/argus-service-receipt.XXXXXX";
    char *created = mkdtemp(directory);
    SERVICE_CHECK(created != NULL);
    if (created == NULL) return;
    SERVICE_CHECK(chmod(directory, 0700) == 0);
    NSString *directoryPath = [NSString stringWithUTF8String:directory] ?: @"";
    NSError *error = nil;
    AQServiceReceiptJournal *journal = [[AQServiceReceiptJournal alloc]
        initWithDirectory:directoryPath error:&error];
    SERVICE_CHECK(journal != nil && error == nil);
    if (journal == nil) { rmdir(directory); return; }
    AQServiceSetReceiptJournalForTesting(journal);

    NSArray *members = @[@{@"path": @"fixture/game.rom", @"size": @4,
                            @"sha256": [@"d" stringByPaddingToLength:64
                                withString:@"d" startingAtIndex:0]}];
    NSDictionary *binding = @{
        @"request_id": @"request-1", @"session_id": @"session-1",
        @"service_boot_id": @"boot-1", @"sequence": @1, @"deadline_ns": @500,
        @"manifest_sha256": [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0],
        @"generation": @7, @"members": members
    };
    NSString *membersSHA256 = AQDigest(@"", members, NULL) ?: @"";
    SERVICE_CHECK(membersSHA256.length == 64);
    NSMutableDictionary *completion = [@{
        @"schema_version": @1,
        @"status": @"VERIFIED_RECEIVER_COMPLETION",
        @"code": @"BROKER_RECEIVER_RECEIPT_DURABLE",
        @"durable": @YES,
        @"request_id": @"request-1", @"session_id": @"session-1",
        @"service_boot_id": @"boot-1", @"sequence": @1, @"deadline_ns": @500,
        @"manifest_sha256": [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0],
        @"generation": @7,
        @"authorization_sha256": [@"e" stringByPaddingToLength:64 withString:@"e" startingAtIndex:0],
        @"members": members, @"members_sha256": membersSHA256,
        @"member_count": @1,
        @"frame_sha256": [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0],
        @"receipt_sha256": [@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0]
    } mutableCopy];
    completion[@"receipt_sha256"] = TestBrokerReceiptDigest(completion);
    NSDictionary *(^dispatch)(NSDictionary *) = ^NSDictionary *(NSDictionary *request) {
        NSData *encoded = AQCanonicalJSONWithMaximumBytes(request, 256 * 1024, NULL);
        xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_uint64(message, "version", 1);
        xpc_dictionary_set_data(message, "request", encoded.bytes, encoded.length);
        NSDictionary *response = nil;
        NSString *invalidation = nil;
        SERVICE_CHECK(AQServiceHandleWireMessageForTesting(nil, @"authenticated-broker",
            message, &response, &invalidation));
        SERVICE_CHECK(invalidation == nil);
        return response;
    };

    SERVICE_CHECK([journal reserveCapacityForSessionID:(NSString *)binding[@"session_id"]
                                                   error:&error]);
    NSMutableDictionary *incomplete = [completion mutableCopy];
    incomplete[@"durable"] = @NO;
    NSDictionary *incompleteResponse = dispatch(@{@"operation": @"receipt_record",
        @"request_id": @"request-1", @"binding": binding, @"completion": incomplete});
    SERVICE_CHECK([incompleteResponse[@"status"] isEqual:@"BLOCKED"]);

    NSArray *malformedDigests = @[@"", @"abc", [@"a" stringByPaddingToLength:63
        withString:@"a" startingAtIndex:0], [@"a" stringByPaddingToLength:65
        withString:@"a" startingAtIndex:0], [@"A" stringByPaddingToLength:64
        withString:@"A" startingAtIndex:0], [@"g" stringByPaddingToLength:64
        withString:@"g" startingAtIndex:0]];
    for (NSString *key in @[@"frame_sha256", @"receipt_sha256"]) {
        for (id malformedDigest in malformedDigests) {
            NSMutableDictionary *malformed = [completion mutableCopy];
            malformed[key] = malformedDigest;
            NSDictionary *malformedResponse = dispatch(@{ @"operation": @"receipt_record",
                @"request_id": @"request-1", @"binding": binding,
                @"completion": malformed });
            SERVICE_CHECK([malformedResponse[@"status"] isEqual:@"BLOCKED"]);
        }
    }

    NSMutableDictionary *missingField = [completion mutableCopy];
    [missingField removeObjectForKey:@"receipt_path"];
    NSDictionary *missingFieldResponse = dispatch(@{
        @"operation": @"receipt_record", @"request_id": @"request-1",
        @"binding": binding, @"completion": missingField,
    });
    SERVICE_CHECK([missingFieldResponse[@"status"] isEqual:@"BLOCKED"]);

    NSMutableDictionary *extraField = [completion mutableCopy];
    extraField[@"unbound_nonce"] = @"unexpected";
    NSDictionary *extraFieldResponse = dispatch(@{
        @"operation": @"receipt_record", @"request_id": @"request-1",
        @"binding": binding, @"completion": extraField,
    });
    SERVICE_CHECK([extraFieldResponse[@"status"] isEqual:@"BLOCKED"]);

    NSMutableDictionary *staleDigest = [completion mutableCopy];
    staleDigest[@"frame_sha256"] = [@"f" stringByPaddingToLength:64
        withString:@"f" startingAtIndex:0];
    NSDictionary *staleDigestResponse = dispatch(@{
        @"operation": @"receipt_record", @"request_id": @"request-1",
        @"binding": binding, @"completion": staleDigest,
    });
    SERVICE_CHECK([staleDigestResponse[@"status"] isEqual:@"BLOCKED"]);

    NSArray *beforeValidRecord = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:directoryPath error:NULL] ?: @[];
    NSMutableArray *receiptRecordsBeforeValidAppend = [NSMutableArray array];
    for (NSString *entry in beforeValidRecord) {
        if (![entry isEqual:@".capacity.lock"] && ![entry hasPrefix:@"reserve-"]) {
            [receiptRecordsBeforeValidAppend addObject:entry];
        }
    }
    SERVICE_CHECK(receiptRecordsBeforeValidAppend.count == 0);
    NSMutableDictionary *brokerCompletion = [completion mutableCopy];
    [brokerCompletion removeObjectForKey:@"service_boot_id"];
    [brokerCompletion removeObjectForKey:@"sequence"];
    brokerCompletion[@"receipt_path"] = @"/private/var/db/argus-qualification/receipts/export.receipt.json";
    NSDictionary *recordResponse = dispatch(@{@"operation": @"receipt_record",
        @"request_id": @"request-1", @"binding": binding, @"completion": brokerCompletion});
    SERVICE_CHECK([recordResponse[@"status"] isEqual:@"OK"]);
    NSDictionary *returnedCompletion = recordResponse[@"completion"];
    SERVICE_CHECK(returnedCompletion.count == 18);
    SERVICE_CHECK([returnedCompletion[@"service_boot_id"] isEqual:@"boot-1"]);
    SERVICE_CHECK([returnedCompletion[@"sequence"] isEqual:@1]);
    SERVICE_CHECK([returnedCompletion[@"receipt_path"] isEqual:brokerCompletion[@"receipt_path"]]);
    NSDictionary *queryResponse = dispatch(@{@"operation": @"receipt_query",
        @"request_id": @"request-1", @"binding": binding});
    SERVICE_CHECK([queryResponse[@"completion"] isEqual:returnedCompletion]);

    NSMutableArray *maximumMembers = [NSMutableArray arrayWithCapacity:200];
    NSString *memberDigest = [@"d" stringByPaddingToLength:64
        withString:@"d" startingAtIndex:0];
    for (NSUInteger index = 0; index < 200; ++index) {
        [maximumMembers addObject:@{
            @"path": [NSString stringWithFormat:@"fixture-%04lu.rom", (unsigned long)index],
            @"size": @4,
            @"sha256": memberDigest,
        }];
    }
    NSMutableDictionary *largeBinding = [binding mutableCopy];
    largeBinding[@"request_id"] = @"request-maximum-members";
    largeBinding[@"session_id"] = @"session-maximum-members";
    largeBinding[@"sequence"] = @2;
    largeBinding[@"members"] = maximumMembers;
    NSMutableDictionary *largeCompletion = [completion mutableCopy];
    largeCompletion[@"request_id"] = largeBinding[@"request_id"];
    largeCompletion[@"session_id"] = largeBinding[@"session_id"];
    largeCompletion[@"sequence"] = largeBinding[@"sequence"];
    largeCompletion[@"members"] = maximumMembers;
    largeCompletion[@"members_sha256"] = AQDigest(@"", maximumMembers, NULL) ?: @"";
    largeCompletion[@"member_count"] = @(maximumMembers.count);
    largeCompletion[@"receipt_path"] = @"/private/var/db/argus-qualification/receipts/maximum.receipt.json";
    [largeCompletion removeObjectForKey:@"service_boot_id"];
    [largeCompletion removeObjectForKey:@"sequence"];
    largeCompletion[@"receipt_sha256"] = TestBrokerReceiptDigest(largeCompletion);
    NSData *largeRecord = AQCanonicalJSON(@{
        @"binding": largeBinding,
        @"completion": largeCompletion,
    }, NULL);
    SERVICE_CHECK(largeRecord.length > 16 * 1024);
    SERVICE_CHECK(largeRecord.length < 256 * 1024);
    SERVICE_CHECK([journal reserveCapacityForSessionID:(NSString *)largeBinding[@"session_id"]
                                                   error:&error]);
    NSDictionary *largeRecordResponse = dispatch(@{
        @"operation": @"receipt_record",
        @"request_id": @"request-maximum-members",
        @"binding": largeBinding,
        @"completion": largeCompletion,
    });
    SERVICE_CHECK([largeRecordResponse[@"status"] isEqual:@"OK"]);
    NSDictionary *largeQueryResponse = dispatch(@{
        @"operation": @"receipt_query",
        @"request_id": @"request-maximum-members",
        @"binding": largeBinding,
    });
    SERVICE_CHECK([largeQueryResponse[@"completion"] isEqual:largeRecordResponse[@"completion"]]);

    NSMutableArray *maximumCountMembers = [NSMutableArray arrayWithCapacity:1024];
    for (NSUInteger index = 0; index < 1024; ++index) {
        [maximumCountMembers addObject:@{
            @"path": [NSString stringWithFormat:@"f/%04lu", (unsigned long)index],
            @"size": @1,
        }];
    }
    NSMutableDictionary *maximumCountBinding = [binding mutableCopy];
    maximumCountBinding[@"request_id"] = @"request-1024-members";
    maximumCountBinding[@"session_id"] = @"session-1024-members";
    maximumCountBinding[@"sequence"] = @3;
    maximumCountBinding[@"members"] = maximumCountMembers;
    NSMutableDictionary *maximumCountCompletion = [completion mutableCopy];
    maximumCountCompletion[@"request_id"] = @"request-1024-members";
    maximumCountCompletion[@"session_id"] = @"session-1024-members";
    maximumCountCompletion[@"sequence"] = @3;
    maximumCountCompletion[@"members"] = maximumCountMembers;
    maximumCountCompletion[@"members_sha256"] = AQDigest(@"", maximumCountMembers, NULL) ?: @"";
    maximumCountCompletion[@"member_count"] = @(maximumCountMembers.count);
    maximumCountCompletion[@"receipt_path"] = @"/private/var/db/argus-qualification/receipts/maximum-count.receipt.json";
    maximumCountCompletion[@"receipt_sha256"] = TestBrokerReceiptDigest(maximumCountCompletion);
    SERVICE_CHECK([journal reserveCapacityForSessionID:(NSString *)maximumCountBinding[@"session_id"]
                                                   error:&error]);
    SERVICE_CHECK([journal recordBrokerCompletion:maximumCountCompletion
        binding:maximumCountBinding error:&error]);
    NSDictionary *maximumCountReceipt = [journal receiptForBinding:maximumCountBinding error:&error];
    SERVICE_CHECK([maximumCountReceipt isEqual:maximumCountCompletion]);

    NSMutableArray *maximumHeaderMembers = [NSMutableArray arrayWithCapacity:400];
    for (NSUInteger index = 0; index < 400; ++index) {
        [maximumHeaderMembers addObject:@{
            @"path": [NSString stringWithFormat:@"fixture-%04lu.rom", (unsigned long)index],
            @"size": @1,
            @"sha256": memberDigest,
        }];
    }
    NSData *maximumHeader = AQCanonicalJSON(maximumHeaderMembers, &error);
    SERVICE_CHECK(maximumHeader.length < 64 * 1024);
    NSMutableDictionary *maximumHeaderBinding = [binding mutableCopy];
    maximumHeaderBinding[@"request_id"] = @"request-maximum-header";
    maximumHeaderBinding[@"session_id"] = @"session-maximum-header";
    maximumHeaderBinding[@"sequence"] = @4;
    maximumHeaderBinding[@"members"] = maximumHeaderMembers;
    NSMutableDictionary *maximumHeaderCompletion = [completion mutableCopy];
    maximumHeaderCompletion[@"request_id"] = @"request-maximum-header";
    maximumHeaderCompletion[@"session_id"] = @"session-maximum-header";
    maximumHeaderCompletion[@"sequence"] = @4;
    maximumHeaderCompletion[@"members"] = maximumHeaderMembers;
    maximumHeaderCompletion[@"members_sha256"] = AQDigest(@"", maximumHeaderMembers, NULL) ?: @"";
    maximumHeaderCompletion[@"member_count"] = @(maximumHeaderMembers.count);
    maximumHeaderCompletion[@"receipt_path"] = @"/private/var/db/argus-qualification/receipts/maximum-header.receipt.json";
    maximumHeaderCompletion[@"receipt_sha256"] = TestBrokerReceiptDigest(maximumHeaderCompletion);
    NSDictionary *maximumHeaderRecord = @{
        @"binding": maximumHeaderBinding,
        @"completion": maximumHeaderCompletion,
    };
    NSData *maximumReceipt = [NSJSONSerialization dataWithJSONObject:maximumHeaderRecord
        options:NSJSONWritingSortedKeys error:&error];
    SERVICE_CHECK(maximumReceipt.length > 64 * 1024);
    SERVICE_CHECK(maximumReceipt.length < 256 * 1024);
    SERVICE_CHECK([journal reserveCapacityForSessionID:(NSString *)maximumHeaderBinding[@"session_id"]
                                                   error:&error]);
    SERVICE_CHECK([journal recordBrokerCompletion:maximumHeaderCompletion
        binding:maximumHeaderBinding error:&error]);
    NSDictionary *maximumHeaderReceipt = [journal receiptForBinding:maximumHeaderBinding error:&error];
    SERVICE_CHECK([maximumHeaderReceipt isEqual:maximumHeaderCompletion]);
    NSDictionary *maximumWireRecordResponse = dispatch(@{
        @"operation": @"receipt_record",
        @"request_id": @"request-maximum-header",
        @"binding": maximumHeaderBinding,
        @"completion": maximumHeaderCompletion,
    });
    SERVICE_CHECK([maximumWireRecordResponse[@"status"] isEqual:@"OK"]);
    NSDictionary *maximumWireQueryResponse = dispatch(@{
        @"operation": @"receipt_query",
        @"request_id": @"request-maximum-header",
        @"binding": maximumHeaderBinding,
    });
    SERVICE_CHECK([maximumWireQueryResponse[@"completion"] isEqual:maximumHeaderCompletion]);

    NSUInteger reservedSessions = 0;
    BOOL capacityRejected = NO;
    for (NSUInteger index = 0; index < 256; ++index) {
        NSString *sessionID = [NSString stringWithFormat:@"capacity-session-%lu",
                               (unsigned long)index];
        if (![journal reserveCapacityForSessionID:sessionID error:&error]) {
            capacityRejected = YES;
            break;
        }
        reservedSessions++;
    }
    SERVICE_CHECK(reservedSessions > 0);
    SERVICE_CHECK(capacityRejected);
    NSDictionary *queryAtCapacity = dispatch(@{
        @"operation": @"receipt_query", @"request_id": @"request-1", @"binding": binding
    });
    SERVICE_CHECK([queryAtCapacity[@"completion"] isEqual:returnedCompletion]);

    NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:
        directoryPath error:NULL] ?: @[];
    NSString *receiptDigest = AQDigest(
        @"argus.fixture-staging.service-receipt.v1", binding, NULL);
    NSString *receiptPath = [directoryPath stringByAppendingPathComponent:
        [NSString stringWithFormat:@"receipt-%@.json", receiptDigest ?: @""]];
    SERVICE_CHECK([[NSFileManager defaultManager] fileExistsAtPath:receiptPath]);
    NSMutableData *corrupt = receiptPath == nil ? nil :
        [[NSData dataWithContentsOfFile:receiptPath] mutableCopy];
    if (corrupt.length != 0) {
        ((uint8_t *)corrupt.mutableBytes)[0] = '!';
        SERVICE_CHECK([corrupt writeToFile:receiptPath atomically:NO]);
        NSDictionary *corruptQuery = dispatch(@{@"operation": @"receipt_query",
            @"request_id": @"request-1", @"binding": binding});
        SERVICE_CHECK([corruptQuery[@"status"] isEqual:@"BLOCKED"]);
    }
    AQServiceSetReceiptJournalForTesting(nil);
    journal = nil;
    for (NSString *entry in entries) unlink([[NSString stringWithFormat:@"%s/%@", directory, entry]
        fileSystemRepresentation]);
    rmdir(directory);
}

static void TestReceiptJournalRecoversStaleTemporaryFiles(void) {
    char directory[] = "/tmp/argus-service-receipt-restart.XXXXXX";
    char *created = mkdtemp(directory);
    SERVICE_CHECK(created != NULL);
    if (created == NULL) return;
    SERVICE_CHECK(chmod(directory, 0700) == 0);
    NSString *directoryPath = [NSString stringWithUTF8String:directory] ?: @"";
    NSError *error = nil;
    AQServiceReceiptJournal *journal = [[AQServiceReceiptJournal alloc]
        initWithDirectory:directoryPath error:&error];
    SERVICE_CHECK(journal != nil && error == nil);
    if (journal == nil) { rmdir(directory); return; }

    SERVICE_CHECK([journal reserveCapacityForSessionID:@"uncertain-session" error:&error]);
    NSString *reservationDigest = AQDigest(
        @"argus.fixture-staging.service-receipt-reservation.v1", @"uncertain-session", NULL);
    NSString *reservationPath = [directoryPath stringByAppendingPathComponent:
        [NSString stringWithFormat:@"reserve-%@.json", reservationDigest ?: @""]];
    NSString *receiptDigest = [@"d" stringByPaddingToLength:64
        withString:@"d" startingAtIndex:0];
    NSString *receiptPath = [directoryPath stringByAppendingPathComponent:
        [NSString stringWithFormat:@"receipt-%@.json", receiptDigest]];
    int receiptFD = open(receiptPath.fileSystemRepresentation,
                         O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    SERVICE_CHECK(receiptFD >= 0);
    if (receiptFD >= 0) {
        const char durableReceipt[] = "durable-receipt";
        SERVICE_CHECK(write(receiptFD, durableReceipt, sizeof(durableReceipt) - 1) ==
                      (ssize_t)(sizeof(durableReceipt) - 1));
        SERVICE_CHECK(fsync(receiptFD) == 0);
        SERVICE_CHECK(close(receiptFD) == 0);
    }

    NSMutableArray<NSString *> *temporaryPaths = [NSMutableArray array];
    NSString *temporaryDigest = [@"a" stringByPaddingToLength:64
        withString:@"a" startingAtIndex:0];
    for (NSUInteger index = 1; index <= 257; ++index) {
        NSString *uuid = [NSString stringWithFormat:
            @"00000000-0000-4000-8000-%012lx", (unsigned long)index];
        NSString *name = [NSString stringWithFormat:
            @".receipt-%@.json-%@.tmp", temporaryDigest, uuid];
        NSString *path = [directoryPath stringByAppendingPathComponent:name];
        int descriptor = open(path.fileSystemRepresentation,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
        SERVICE_CHECK(descriptor >= 0);
        if (descriptor >= 0) {
            const char partial[] = "partial";
            SERVICE_CHECK(write(descriptor, partial, sizeof(partial) - 1) ==
                          (ssize_t)(sizeof(partial) - 1));
            SERVICE_CHECK(fsync(descriptor) == 0);
            SERVICE_CHECK(close(descriptor) == 0);
            [temporaryPaths addObject:path];
        }
    }

    journal = nil;
    error = nil;
    AQServiceReceiptJournal *restarted = [[AQServiceReceiptJournal alloc]
        initWithDirectory:directoryPath error:&error];
    SERVICE_CHECK(restarted != nil && error == nil);
    for (NSString *path in temporaryPaths) {
        SERVICE_CHECK(access(path.fileSystemRepresentation, F_OK) != 0 && errno == ENOENT);
    }
    SERVICE_CHECK(access(receiptPath.fileSystemRepresentation, F_OK) == 0);
    SERVICE_CHECK(access(reservationPath.fileSystemRepresentation, F_OK) == 0);
    SERVICE_CHECK([restarted reserveCapacityForSessionID:@"after-restart" error:&error]);

    restarted = nil;
    [[NSFileManager defaultManager] removeItemAtPath:directoryPath error:NULL];
}

static void TestReceiptJournalRejectsTemporarySymlinks(void) {
    char directory[] = "/tmp/argus-service-receipt-symlink.XXXXXX";
    char *created = mkdtemp(directory);
    SERVICE_CHECK(created != NULL);
    if (created == NULL) return;
    SERVICE_CHECK(chmod(directory, 0700) == 0);
    NSString *directoryPath = [NSString stringWithUTF8String:directory] ?: @"";
    NSString *targetPath = [directoryPath stringByAppendingPathComponent:@"target"];
    int targetFD = open(targetPath.fileSystemRepresentation,
                        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    SERVICE_CHECK(targetFD >= 0);
    if (targetFD >= 0) close(targetFD);
    NSString *digest = [@"a" stringByPaddingToLength:64
        withString:@"a" startingAtIndex:0];
    NSString *temporaryPath = [directoryPath stringByAppendingPathComponent:
        [NSString stringWithFormat:
            @".receipt-%@.json-00000000-0000-4000-8000-000000000001.tmp", digest]];
    SERVICE_CHECK(symlink(targetPath.fileSystemRepresentation,
                          temporaryPath.fileSystemRepresentation) == 0);

    NSError *error = nil;
    AQServiceReceiptJournal *journal = [[AQServiceReceiptJournal alloc]
        initWithDirectory:directoryPath error:&error];
    SERVICE_CHECK(journal == nil && error != nil);
    struct stat metadata = {0};
    SERVICE_CHECK(lstat(temporaryPath.fileSystemRepresentation, &metadata) == 0 &&
                  S_ISLNK(metadata.st_mode));
    SERVICE_CHECK(access(targetPath.fileSystemRepresentation, F_OK) == 0);
    [[NSFileManager defaultManager] removeItemAtPath:directoryPath error:NULL];
}

static void TestReceiptLookupRejectsFIFOWithoutBlocking(void) {
    char directory[] = "/tmp/argus-service-receipt-fifo.XXXXXX";
    char *created = mkdtemp(directory);
    SERVICE_CHECK(created != NULL);
    if (created == NULL) return;
    SERVICE_CHECK(chmod(directory, 0700) == 0);
    NSString *directoryPath = [NSString stringWithUTF8String:directory] ?: @"";
    NSError *error = nil;
    AQServiceReceiptJournal *journal = [[AQServiceReceiptJournal alloc]
        initWithDirectory:directoryPath error:&error];
    SERVICE_CHECK(journal != nil && error == nil);
    if (journal == nil) { rmdir(directory); return; }
    NSDictionary *binding = @{
        @"request_id": @"fifo-request", @"session_id": @"fifo-session",
        @"service_boot_id": @"fifo-boot", @"sequence": @1,
        @"deadline_ns": @500,
        @"manifest_sha256": [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0],
        @"generation": @1,
        @"members": @[@{@"path": @"f", @"size": @1,
                         @"sha256": [@"d" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0]}],
    };
    NSString *digest = AQDigest(@"argus.fixture-staging.service-receipt.v1", binding, NULL);
    NSString *fifoPath = [directoryPath stringByAppendingPathComponent:
        [NSString stringWithFormat:@"receipt-%@.json", digest ?: @""]];
    SERVICE_CHECK(mkfifo(fifoPath.fileSystemRepresentation, 0600) == 0);

    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block NSDictionary *receipt = nil;
    __block NSError *lookupError = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        receipt = [journal receiptForBinding:binding error:&lookupError];
        dispatch_semaphore_signal(finished);
    });
    BOOL completed = dispatch_semaphore_wait(finished,
        dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2)) == 0;
    SERVICE_CHECK(completed);
    if (!completed) {
        int unblock = open(fifoPath.fileSystemRepresentation, O_WRONLY | O_NONBLOCK);
        if (unblock >= 0) close(unblock);
        SERVICE_CHECK(dispatch_semaphore_wait(finished,
            dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
    }
    SERVICE_CHECK(receipt == nil);
    SERVICE_CHECK(lookupError != nil);
    unlink(fifoPath.fileSystemRepresentation);
    journal = nil;
    rmdir(directory);
}
#endif

static void TestServiceRejectsPriorSessionFreshness(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(NSData *__unused canonicalFreshness,
                            NSData *__unused signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)token];
        }
        error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;
    NSString *firstConnection = [core openConnection:&error];
    SERVICE_CHECK(firstConnection.length != 0);
    int exportFD = -1;
    NSDictionary *firstHello = [core handleRequest:TestHello() documents:nil sourceFDs:nil
        connectionID:firstConnection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(firstHello != nil);
    if (firstHello == nil) return;

    NSString *secondConnection = [core openConnection:&error];
    SERVICE_CHECK(secondConnection.length != 0);
    NSMutableDictionary *secondHello = [TestHello() mutableCopy];
    secondHello[@"request_id"] = @"request-2";
    secondHello[@"sequence"] = @2;
    secondHello[@"nonce"] = TestHelloNonce(2);
    NSDictionary *secondHelloResponse = [core handleRequest:secondHello documents:nil sourceFDs:nil
        connectionID:secondConnection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(secondHelloResponse != nil);
    if (secondHelloResponse == nil) return;

    NSDictionary *body = @{
        @"schema_version": @1, @"operation": @"recovery",
        @"request_id": @"old-session-replay", @"connection_id": secondConnection
    };
    NSDictionary *request = TestSignedRequest(body, secondConnection,
        (NSString *)firstHello[@"session_id"], 1, 1,
        (NSNumber *)secondHello[@"deadline_ns"],
        (NSString *)secondHello[@"authorization_sha256"], @{});
    SERVICE_CHECK(request != nil);
    if (request == nil) return;
    error = nil;
    SERVICE_CHECK([core handleRequest:request documents:nil sourceFDs:nil
        connectionID:secondConnection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"SESSION_BINDING_MISMATCH"]);
    SERVICE_CHECK(store.recoveryCount == 0);
}

static void TestServiceRejectsSignedRequestAfterRestart(void) {
    AQServiceTestStore *oldStore = [[AQServiceTestStore alloc] init];
    AQServiceTestStore *newStore = [[AQServiceTestStore alloc] init];
    __block NSUInteger oldToken = 0;
    __block NSUInteger newToken = 0;
    NSError *error = nil;
    AQServiceSessionCore *oldCore = [[AQServiceSessionCore alloc]
        initWithStore:oldStore installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(NSData *__unused data, NSData *__unused signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            oldToken++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)oldToken];
        }
        error:&error];
    AQServiceSessionCore *newCore = [[AQServiceSessionCore alloc]
        initWithStore:newStore installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-2" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(NSData *__unused data, NSData *__unused signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            newToken++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)newToken];
        }
        error:&error];
    SERVICE_CHECK(oldCore != nil && newCore != nil);
    if (oldCore == nil || newCore == nil) return;

    int exportFD = -1;
    NSString *oldConnection = [oldCore openConnection:&error];
    NSDictionary *oldHello = [oldCore handleRequest:TestHello() documents:nil sourceFDs:nil
        connectionID:oldConnection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(oldHello != nil);
    if (oldHello == nil) return;
    NSDictionary *oldBody = TestRecoveryBody(@"restart-request", oldConnection);
    NSDictionary *oldRequest = TestSignedRequest(oldBody, oldConnection,
        (NSString *)oldHello[@"session_id"], 1, 1,
        (NSNumber *)TestHello()[@"deadline_ns"],
        (NSString *)TestHello()[@"authorization_sha256"], @{});
    SERVICE_CHECK(oldRequest != nil);
    if (oldRequest == nil) return;

    NSString *newConnection = [newCore openConnection:&error];
    NSMutableDictionary *newHelloRequest = [TestHello() mutableCopy];
    newHelloRequest[@"service_boot_id"] = @"boot-2";
    newHelloRequest[@"nonce"] = TestHelloNonceForBoot(1, @"boot-2",
                                                       TestReviewAuthorizationSHA256());
    NSDictionary *newHello = [newCore handleRequest:newHelloRequest documents:nil sourceFDs:nil
        connectionID:newConnection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(newHello != nil);
    if (newHello == nil) return;
    SERVICE_CHECK([newConnection isEqual:oldConnection]);
    SERVICE_CHECK([newHello[@"session_id"] isEqual:oldHello[@"session_id"]]);

    error = nil;
    SERVICE_CHECK([newCore handleRequest:oldRequest documents:nil sourceFDs:nil
        connectionID:newConnection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"SESSION_BINDING_MISMATCH"]);
    SERVICE_CHECK(newStore.recoveryCount == 0);
}

static void TestPrepareAdmittedState(AQServiceSessionCore *core, NSString *connection) {
    NSDictionary *connections = [core valueForKey:@"connections"];
    id state = [connections objectForKey:connection];
    SERVICE_CHECK(state != nil);
    if (state == nil) return;
    [state setValue:@"admitted" forKey:@"phase"];
    [state setValue:@"stage-session" forKey:@"sessionID"];
    [state setValue:@"grant-1" forKey:@"grantID"];
    [state setValue:@[ @"stage" ] forKey:@"operations"];
    [state setValue:TestReviewAuthorizationSHA256() forKey:@"authorizationSHA256"];
    [state setValue:[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]
        forKey:@"consentSHA256"];
    [state setValue:@(1000) forKey:@"deadlineNanoseconds"];
    [state setValue:@(1) forKey:@"storeEpoch"];
}

#if defined(AQ_SERVICE_TESTING) && !defined(AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN)
static void TestFreshAdmissionRecoveryPolicy(void) {
    SERVICE_CHECK(AQServiceRecoveryAllowsFreshAdmissionForTesting(
        @{@"state": @"clean", @"sessions": @0}));
    SERVICE_CHECK(AQServiceRecoveryAllowsFreshAdmissionForTesting(
        @{@"state": @"blocked_retained", @"reason": @"restart_requires_fresh_authority",
          @"sessions": @1, @"fresh_admission_available": @YES}));
    SERVICE_CHECK(!AQServiceRecoveryAllowsFreshAdmissionForTesting(
        @{@"state": @"blocked_retained", @"reason": @"restart_requires_fresh_authority",
          @"sessions": @1, @"fresh_admission_available": @NO}));
    SERVICE_CHECK(!AQServiceRecoveryAllowsFreshAdmissionForTesting(
        @{@"state": @"blocked_retained", @"reason": @"journal_corrupt", @"sessions": @1}));
    SERVICE_CHECK(!AQServiceRecoveryAllowsFreshAdmissionForTesting(
        @{@"state": @"blocked_retained", @"reason": @"restart_requires_fresh_authority",
          @"sessions": @0}));
}

static void TestAdmissionFailureReleasesOnlyItsReceiptReservation(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    store.rejectAdmission = YES;
    BOOL capacityDenied = NO;
    NSError *error = nil;
    NSDictionary *authority = @{@"session_id": @"failed-admission"};
    NSDictionary *result = AQServiceAdmitWithReceiptReservationForTesting(
        store, @"failed-admission", @[@"export"], @{}, authority,
        &capacityDenied, &error);
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK(!capacityDenied);
    SERVICE_CHECK(store.receiptReservationReleaseCount == 1);

    store.hasExistingReceiptReservation = YES;
    result = AQServiceAdmitWithReceiptReservationForTesting(
        store, @"existing-reservation", @[@"export"], @{},
        @{@"session_id": @"existing-reservation"}, &capacityDenied, &error);
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK(store.receiptReservationReleaseCount == 1);
}

static void TestAdmissionFailureReleaseFailureIsBlocked(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    store.rejectAdmission = YES;
    store.rejectReceiptReservationRelease = YES;
    BOOL capacityDenied = NO;
    NSError *error = nil;

    NSDictionary *result = AQServiceAdmitWithReceiptReservationForTesting(
        store, @"release-failure", @[@"export"], @{},
        @{@"session_id": @"release-failure"}, &capacityDenied, &error);

    SERVICE_CHECK(result == nil);
    SERVICE_CHECK(!capacityDenied);
    SERVICE_CHECK(store.receiptReservationReleaseCount == 1);
    SERVICE_CHECK(store.receiptReservationRetained);
    SERVICE_CHECK([error.domain isEqual:AQServiceErrorDomain]);
    SERVICE_CHECK(error.code == AQServiceUnsupportedExclusivity);
}

static void TestReceiptJournalReservationRelease(void) {
    char templatePath[] = "/private/tmp/argus-receipt-release-XXXXXX";
    char *directory = mkdtemp(templatePath);
    SERVICE_CHECK(directory != NULL);
    if (directory == NULL) return;
    NSString *path = @(directory);
    NSError *error = nil;
    AQServiceReceiptJournal *journal = [[AQServiceReceiptJournal alloc]
        initWithDirectory:path error:&error];
    SERVICE_CHECK(journal != nil);
    if (journal == nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return;
    }
    BOOL created = NO;
    SERVICE_CHECK([journal reserveCapacityForSessionID:@"failed-admission"
        created:&created error:&error]);
    SERVICE_CHECK(created);
    SERVICE_CHECK([journal releaseCapacityForSessionID:@"failed-admission" error:&error]);
    created = NO;
    SERVICE_CHECK([journal reserveCapacityForSessionID:@"failed-admission"
        created:&created error:&error]);
    SERVICE_CHECK(created);
    created = YES;
    SERVICE_CHECK([journal reserveCapacityForSessionID:@"failed-admission"
        created:&created error:&error]);
    SERVICE_CHECK(!created);
    SERVICE_CHECK([journal releaseCapacityForSessionID:@"failed-admission" error:&error]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

static void TestReceiptJournalReleaseSyncFailureRetainsRecoveryObligation(void) {
    char templatePath[] = "/private/tmp/argus-receipt-release-sync-XXXXXX";
    char *directory = mkdtemp(templatePath);
    SERVICE_CHECK(directory != NULL);
    if (directory == NULL) return;
    NSString *path = @(directory);
    NSError *error = nil;
    AQFailingReleaseSyncReceiptJournal *journal = [[AQFailingReleaseSyncReceiptJournal alloc]
        initWithDirectory:path error:&error];
    SERVICE_CHECK(journal != nil);
    if (journal == nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return;
    }

    journal.failNextReservationReleaseSync = YES;

    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    store.rejectAdmission = YES;
    store.receiptJournalForTesting = journal;
    BOOL capacityDenied = NO;
    NSDictionary *result = AQServiceAdmitWithReceiptReservationForTesting(
        store, @"release-sync-failure", @[@"export"], @{},
        @{@"session_id": @"release-sync-failure"}, &capacityDenied, &error);
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK(!capacityDenied);
    SERVICE_CHECK(store.receiptReservationReleaseCount == 1);
    SERVICE_CHECK([error.domain isEqual:AQServiceErrorDomain]);
    SERVICE_CHECK(error.code == AQServiceUnsupportedExclusivity);

    store.receiptJournalForTesting = nil;
    journal = nil;
    AQServiceReceiptJournal *reopened = [[AQServiceReceiptJournal alloc]
        initWithDirectory:path error:&error];
    SERVICE_CHECK(reopened != nil);
    if (reopened != nil) {
        BOOL created = YES;
        SERVICE_CHECK([reopened reserveCapacityForSessionID:@"release-sync-failure"
            created:&created error:&error]);
        SERVICE_CHECK(!created);
        SERVICE_CHECK([reopened releaseCapacityForSessionID:@"release-sync-failure"
            error:&error]);
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}
#endif

static void TestExportAdmissionFailsClosedForRecoveryAndReceiptCapacity(void) {
    for (NSNumber *blockedValue in @[ @YES, @NO ]) {
        BOOL blockedRecovery = blockedValue.boolValue;
        AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
        store.rejectReceiptCapacity = !blockedRecovery;
        if (blockedRecovery) {
            store.recoveryClassification = @{
                @"state": @"blocked_retained", @"reason": @"journal_corrupt", @"sessions": @0
            };
        }
        __block NSUInteger token = 0;
        NSError *error = nil;
        AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
            initWithStore:store installationIdentity:@"installation-1"
            serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
            ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
            ownerVerifier:^BOOL(__unused NSData *consent, __unused NSData *signature,
                                __unused NSError **verifyError) { return YES; }
            identifierGenerator:^NSString *{
                token++;
                return [NSString stringWithFormat:@"capacity-token-%lu", (unsigned long)token];
            } error:&error];
        SERVICE_CHECK(core != nil);
        if (core == nil) continue;
        NSString *connection = [core openConnection:&error];
        TestPrepareAdmittedState(core, connection);
        NSDictionary *connections = [core valueForKey:@"connections"];
        id state = [connections objectForKey:connection];
        [state setValue:@[ @"export" ] forKey:@"operations"];
        NSDictionary *body = @{
            @"schema_version": @1, @"operation": @"export", @"request_id": @"ignored",
            @"connection_id": connection, @"session_id": @"stage-session",
            @"grant_id": @"grant-1", @"epoch": @1, @"sequence": @1,
            @"expected_generation": @0
        };
        NSDictionary *request = TestSignedRequest(body, connection, @"stage-session", 1, 1,
            @1000, TestReviewAuthorizationSHA256(), @{});
        int exportFD = -1;
        error = nil;
        NSDictionary *result = [core handleRequest:request documents:nil sourceFDs:nil
            connectionID:connection exportFileDescriptor:&exportFD error:&error];
        SERVICE_CHECK(result == nil);
        SERVICE_CHECK([error.localizedDescription isEqual:(blockedRecovery ?
            @"STORE_DENIED" : @"RECEIPT_CAPACITY_EXHAUSTED")]);
        SERVICE_CHECK(store.callbackCount == 0);
        SERVICE_CHECK(store.receiptReservationCount == (blockedRecovery ? 0 : 1));
        SERVICE_CHECK(exportFD == -1);
    }
}

static NSDictionary *TestSourceIdentity(NSString *path, int fd) {
    struct stat info = {0};
    if (fstat(fd, &info) != 0) return nil;
    return @{
        @"path": path,
        @"device": @((uint64_t)info.st_dev),
        @"inode": @((uint64_t)info.st_ino),
        @"mode": @((uint32_t)info.st_mode),
        @"size": @((uint64_t)info.st_size),
        @"link_count": @((uint64_t)info.st_nlink),
    };
}

static NSMutableDictionary *TestStageRequest(NSString *connection, NSString *path,
                                             NSDictionary *identity, uint64_t sequence) {
    NSDictionary *body = @{
        @"schema_version": @1,
        @"operation": @"stage",
        @"connection_id": connection,
        @"session_id": @"stage-session",
        @"grant_id": @"grant-1",
        @"epoch": @1,
        @"sequence": @(sequence),
        @"expected_generation": @0,
        @"source_paths": @[ path ],
        @"source_identities": @[ identity ],
    };
    return TestSignedRequest(body, connection, @"stage-session", 1, sequence,
                             @1000, TestReviewAuthorizationSHA256(), @{});
}

static void TestFreshRecoverySessionCanStageAndExportDuringRestartRecovery(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    store.recoveryClassification = @{
        @"state": @"blocked_retained",
        @"reason": @"restart_requires_fresh_authority",
        @"sessions": @1,
        @"fresh_admission_available": @NO,
    };
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"restart-stage-token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    char sourceTemplate[] = "/tmp/argus-service-restart-stage.XXXXXX";
    int writableFD = mkstemp(sourceTemplate);
    SERVICE_CHECK(writableFD >= 0);
    if (writableFD < 0) return;
    close(writableFD);
    int sourceFD = open(sourceTemplate, O_RDONLY);
    SERVICE_CHECK(sourceFD >= 0);
    if (sourceFD < 0) {
        unlink(sourceTemplate);
        return;
    }

    NSString *sourcePath = @"fresh-recovery/source.bin";
    NSDictionary *identity = TestSourceIdentity(sourcePath, sourceFD);
    SERVICE_CHECK(identity != nil);
    NSString *connection = [core openConnection:&error] ?: @"";
    SERVICE_CHECK(connection.length > 0);
    if (connection.length == 0) {
        close(sourceFD);
        unlink(sourceTemplate);
        return;
    }
    TestPrepareAdmittedState(core, connection);
    NSDictionary *connections = [core valueForKey:@"connections"];
    id connectionState = [connections objectForKey:connection];
    [connectionState setValue:@[@"stage", @"export"] forKey:@"operations"];
    [connectionState setValue:@YES forKey:@"admittedDuringFreshRecovery"];
    int exportFD = -1;
    NSMutableDictionary *request = TestStageRequest(connection, sourcePath, identity, 1);
    NSDictionary *result = [core handleRequest:request documents:nil
        sourceFDs:@{sourcePath: @(sourceFD)} connectionID:(connection ?: @"")
        exportFileDescriptor:&exportFD error:&error];

    SERVICE_CHECK(result != nil);
    SERVICE_CHECK(store.callbackCount == 1);
    SERVICE_CHECK(error == nil);
    int exportPipe[2] = {-1, -1};
    SERVICE_CHECK(pipe(exportPipe) == 0);
    if (exportPipe[0] < 0 || exportPipe[1] < 0) {
        close(sourceFD);
        unlink(sourceTemplate);
        return;
    }
    store.exportPipeDescriptorForTesting = @(exportPipe[0]);
    NSDictionary *exportBody = @{
        @"schema_version": @1,
        @"operation": @"export",
        @"connection_id": connection,
        @"session_id": @"stage-session",
        @"grant_id": @"grant-1",
        @"epoch": @1,
        @"sequence": @2,
        @"expected_generation": @1,
    };
    NSDictionary *exportRequest = TestSignedRequest(exportBody, connection, @"stage-session", 1, 2,
        @1000, TestReviewAuthorizationSHA256(), @{});
    error = nil;
    NSDictionary *exportResult = [core handleRequest:exportRequest documents:nil
        sourceFDs:nil connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(exportResult != nil);
    SERVICE_CHECK(store.callbackCount == 2);
    SERVICE_CHECK(exportFD == exportPipe[0]);
    SERVICE_CHECK(error == nil);
    if (exportFD >= 0) close(exportFD);
    close(exportPipe[1]);
    NSDictionary *recoveryAfterOperations = [store classifyRecovery];
    SERVICE_CHECK([recoveryAfterOperations[@"state"] isEqual:@"blocked_retained"]);
    SERVICE_CHECK([recoveryAfterOperations[@"sessions"] unsignedLongLongValue] == 1);
    SERVICE_CHECK(![recoveryAfterOperations[@"fresh_admission_available"] boolValue]);
    close(sourceFD);
    unlink(sourceTemplate);
}

static void TestUnmarkedConnectionCannotOperateDuringRestartRecovery(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    store.recoveryClassification = @{
        @"state": @"blocked_retained",
        @"reason": @"restart_requires_fresh_authority",
        @"sessions": @1,
        @"fresh_admission_available": @NO,
    };
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{ return @"unmarked-recovery-token"; } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error] ?: @"";
    SERVICE_CHECK(connection.length > 0);
    if (connection.length == 0) return;
    TestPrepareAdmittedState(core, connection);
    NSDictionary *connections = [core valueForKey:@"connections"];
    id connectionState = [connections objectForKey:connection];
    [connectionState setValue:@[@"export"] forKey:@"operations"];

    NSDictionary *body = @{
        @"schema_version": @1,
        @"operation": @"export",
        @"connection_id": connection,
        @"session_id": @"stage-session",
        @"grant_id": @"grant-1",
        @"epoch": @1,
        @"sequence": @1,
        @"expected_generation": @0,
    };
    NSDictionary *request = TestSignedRequest(body, connection, @"stage-session", 1, 1,
        @1000, TestReviewAuthorizationSHA256(), @{});
    int exportFD = -1;
    NSDictionary *result = [core handleRequest:request documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK(error.code == AQServiceStoreDenied);
    SERVICE_CHECK(store.callbackCount == 0);
    SERVICE_CHECK(exportFD == -1);
}

static void TestStageBindsSignedSourceDescriptorIdentity(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"stage-token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    char firstTemplate[] = "/tmp/argus-service-stage-a.XXXXXX";
    char secondTemplate[] = "/tmp/argus-service-stage-b.XXXXXX";
    int firstWritableFD = mkstemp(firstTemplate);
    int secondWritableFD = mkstemp(secondTemplate);
    int firstFD = firstWritableFD < 0 ? -1 : open(firstTemplate, O_RDONLY);
    int secondFD = secondWritableFD < 0 ? -1 : open(secondTemplate, O_RDONLY);
    if (firstWritableFD >= 0) close(firstWritableFD);
    if (secondWritableFD >= 0) close(secondWritableFD);
    SERVICE_CHECK(firstFD >= 0 && secondFD >= 0);
    if (firstFD < 0 || secondFD < 0) {
        if (firstFD >= 0) close(firstFD);
        if (secondFD >= 0) close(secondFD);
        return;
    }
    NSString *firstSource = @"source-a";
    NSString *secondSource = @"source-b";
    NSDictionary *firstIdentity = TestSourceIdentity(firstSource, firstFD);
    NSDictionary *secondIdentity = TestSourceIdentity(secondSource, secondFD);
    SERVICE_CHECK(firstIdentity != nil && secondIdentity != nil);

    NSString *firstConnection = [core openConnection:&error];
    TestPrepareAdmittedState(core, firstConnection);
    int exportFD = -1;
    NSMutableDictionary *signedForFirst = TestStageRequest(firstConnection, firstSource,
                                                           firstIdentity, 1);
    NSDictionary *result = [core handleRequest:signedForFirst
        documents:nil sourceFDs:@{firstSource: @(firstFD)} connectionID:firstConnection
        exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result != nil);
    SERVICE_CHECK(store.callbackCount == 1);
    SERVICE_CHECK([store.lastStageSourceFDs[firstSource] intValue] == firstFD);
    struct stat atCallback = {0};
    SERVICE_CHECK(fstat([store.lastStageSourceFDs[firstSource] intValue], &atCallback) == 0);
    SERVICE_CHECK((uint64_t)atCallback.st_dev == [firstIdentity[@"device"] unsignedLongLongValue]);
    SERVICE_CHECK((uint64_t)atCallback.st_ino == [firstIdentity[@"inode"] unsignedLongLongValue]);

    NSString *secondConnection = [core openConnection:&error];
    TestPrepareAdmittedState(core, secondConnection);
    NSMutableDictionary *signedForFirstButSubstituted = TestStageRequest(
        secondConnection, firstSource, firstIdentity, 1);
    error = nil;
    result = [core handleRequest:signedForFirstButSubstituted
        documents:nil sourceFDs:@{firstSource: @(secondFD)} connectionID:secondConnection
        exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);
    SERVICE_CHECK(store.callbackCount == 1);

    NSMutableDictionary *mutatedAfterSigning = TestStageRequest(
        secondConnection, firstSource, firstIdentity, 1);
    mutatedAfterSigning[@"source_identities"] = @[ secondIdentity ];
    error = nil;
    result = [core handleRequest:mutatedAfterSigning
        documents:nil sourceFDs:@{firstSource: @(secondFD)} connectionID:secondConnection
        exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);
    SERVICE_CHECK(store.callbackCount == 1);
    close(firstFD);
    close(secondFD);
    unlink(firstTemplate);
    unlink(secondTemplate);
}

static void TestServiceStrictFreshnessAndSequence(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    AQServiceTestClock *clock = [[AQServiceTestClock alloc] init];
    __block NSUInteger token = 0;
    __block NSUInteger verifierCalls = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:clock
        ownerVerifier:^BOOL(NSData *canonicalFreshness, NSData *signature,
                            __unused NSError **verifyError) {
            verifierCalls++;
            NSDictionary *freshness = AQParseJSON(canonicalFreshness, NULL);
            SERVICE_CHECK(freshness != nil);
            return ![signature isEqualToData:AQTestData(@"bad-freshness-signature")];
        }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)token];
        }
        error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;
    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection.length != 0);
    int exportFD = -1;
    NSDictionary *hello = [core handleRequest:TestHello() documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(hello != nil);
    if (hello == nil) return;
    NSString *sessionID = (NSString *)hello[@"session_id"];
    NSNumber *deadline = (NSNumber *)TestHello()[@"deadline_ns"];
    NSString *authorization = (NSString *)TestHello()[@"authorization_sha256"];

    NSMutableDictionary *(^signedRecovery)(NSString *, uint64_t, NSDictionary *) =
        ^NSMutableDictionary *(NSString *requestID, uint64_t sequence, NSDictionary *overrides) {
            NSDictionary *body = TestRecoveryBody(requestID, connection);
            return TestSignedRequest(body, connection, sessionID, 1, sequence, deadline,
                                     authorization, overrides);
        };
    BOOL (^rejects)(NSDictionary *, NSString *) = ^BOOL(NSDictionary *request,
                                                        NSString *expected) {
        NSError *callError = nil;
        int callExportFD = -1;
        NSDictionary *result = [core handleRequest:request documents:nil sourceFDs:nil
            connectionID:connection exportFileDescriptor:&callExportFD error:&callError];
        SERVICE_CHECK(result == nil);
        SERVICE_CHECK([callError.localizedDescription isEqual:expected]);
        return result == nil && [callError.localizedDescription isEqual:expected];
    };

    NSMutableDictionary *first = signedRecovery(@"fresh-valid-1", 1, @{});
    SERVICE_CHECK(first != nil);
    NSDictionary *firstResult = [core handleRequest:first documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(firstResult != nil);
    SERVICE_CHECK(store.recoveryCount == 1);

    rejects(signedRecovery(@"fresh-duplicate-sequence", 1, @{}), @"REPLAY_REJECTED");
    rejects(signedRecovery(@"fresh-skipped-sequence", 3, @{}), @"REPLAY_REJECTED");
    rejects(signedRecovery(@"fresh-duplicate-request-id", 2,
        @{@"request_id": (NSString *)first[@"request_id"]}), @"INVALID_REQUEST");
    SERVICE_CHECK(store.recoveryCount == 1);

    NSMutableDictionary *second = signedRecovery(@"fresh-valid-2", 2, @{});
    SERVICE_CHECK(second != nil);
    SERVICE_CHECK([core handleRequest:second documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] != nil);
    SERVICE_CHECK(store.recoveryCount == 2);
    rejects(signedRecovery(@"fresh-reversed-sequence", 1, @{}), @"REPLAY_REJECTED");
    rejects(signedRecovery(@"fresh-old-boot", 3,
        @{@"service_boot_id": @"boot-old"}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-peer-epoch", 3,
        @{@"epoch": @2}), @"INVALID_REQUEST");
    rejects(signedRecovery(@"fresh-wrong-owner", 3,
        @{@"owner_key_id": @"owner-key-2"}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-install", 3,
        @{@"installation_id": @"installation-2"}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-broker", 3,
        @{@"broker_revision": @"broker-2"}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-session", 3,
        @{@"session_id": @"session-old"}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-connection", 3,
        @{@"connection_id": @"connection-old"}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-authorization", 3,
        @{@"authorization_sha256": [@"f" stringByPaddingToLength:64
            withString:@"f" startingAtIndex:0]}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-consent", 3,
        @{@"consent_sha256": [@"9" stringByPaddingToLength:64
            withString:@"9" startingAtIndex:0]}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-request-digest", 3,
        @{@"request_sha256": [@"0" stringByPaddingToLength:64
            withString:@"0" startingAtIndex:0]}), @"INVALID_REQUEST");
    rejects(signedRecovery(@"fresh-wrong-operation", 3,
        @{@"operation": @"inspect"}), @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-wrong-request-id", 3,
        @{@"request_id": @"different-request"}), @"INVALID_REQUEST");
    rejects(signedRecovery(@"fresh-later-deadline", 3,
        @{@"deadline_ns": @(deadline.unsignedLongLongValue + 1)}),
        @"SESSION_BINDING_MISMATCH");
    rejects(signedRecovery(@"fresh-earlier-deadline", 3,
        @{@"deadline_ns": @(deadline.unsignedLongLongValue - 1)}),
        @"SESSION_BINDING_MISMATCH");

    NSMutableDictionary *badSignature = signedRecovery(@"fresh-bad-signature", 3, @{});
    badSignature[@"freshness_signature"] = [AQTestData(@"bad-freshness-signature")
        base64EncodedStringWithOptions:0];
    rejects(badSignature, @"OWNER_CONSENT_DENIED");
    SERVICE_CHECK(store.recoveryCount == 2);
    SERVICE_CHECK(verifierCalls > 0);

    clock.nanoseconds = deadline.unsignedLongLongValue;
    rejects(signedRecovery(@"fresh-expired", 3, @{}), @"OWNER_CONSENT_EXPIRED");
    SERVICE_CHECK(store.recoveryCount == 2);
}

static void TestTask2TimingEpochNonceAndRequestIdentity(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    AQServiceTestClock *clock = [[AQServiceTestClock alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:clock
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"task2-token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection.length != 0);
    int exportFD = -1;
    NSMutableDictionary *expired = TestHelloV2(1, nil);
    expired[@"deadline_ns"] = @(clock.nanoseconds);
    error = nil;
    SERVICE_CHECK([core handleRequest:expired documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"OWNER_CONSENT_EXPIRED"]);

    NSMutableDictionary *tooLong = TestHelloV2(1, nil);
    tooLong[@"deadline_ns"] = @(clock.nanoseconds + TestMaximumOperationNanoseconds + 1);
    error = nil;
    SERVICE_CHECK([core handleRequest:tooLong documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"LIMIT_EXCEEDED"]);

    NSMutableDictionary *wrongEpoch = TestHelloV2(1,
        TestHelloNonceForBoot(1, @"boot-2", TestReviewAuthorizationSHA256()));
    wrongEpoch[@"service_boot_id"] = @"boot-2";
    error = nil;
    SERVICE_CHECK([core handleRequest:wrongEpoch documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"SESSION_BINDING_MISMATCH"]);

    NSMutableDictionary *missingAuthorization = [TestHelloV2(1, nil) mutableCopy];
    [missingAuthorization removeObjectForKey:@"authorization"];
    error = nil;
    SERVICE_CHECK([core handleRequest:missingAuthorization documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);

    NSMutableDictionary *substitutedAuthorization = [TestHelloV2(1, nil) mutableCopy];
    substitutedAuthorization[@"authorization"] =
        [@"{\"authorization_id\":\"synthetic-review-v2\"}" dataUsingEncoding:NSUTF8StringEncoding];
    error = nil;
    SERVICE_CHECK([core handleRequest:substitutedAuthorization documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"SESSION_BINDING_MISMATCH"]);

    NSMutableDictionary *nonCanonicalAuthorization = [TestHelloV2(1, nil) mutableCopy];
    nonCanonicalAuthorization[@"authorization"] =
        [@"{ \"authorization_id\": \"synthetic-review-v1\" }" dataUsingEncoding:NSUTF8StringEncoding];
    nonCanonicalAuthorization[@"authorization_sha256"] =
        @"bd64abb9d612eb002947b4f2fb97ea41a31fe3522b4876dce5e2511c60dd7428";
    error = nil;
    SERVICE_CHECK([core handleRequest:nonCanonicalAuthorization documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"SESSION_BINDING_MISMATCH"]);

    NSMutableDictionary *bounded = TestHelloV2(1, nil);
    NSDictionary *hello = [core handleRequest:bounded documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(hello != nil);
    if (hello == nil) return;
    SERVICE_CHECK([hello[@"service_boot_id"] isEqual:@"boot-1"]);
    SERVICE_CHECK([hello[@"deadline_ns"] unsignedLongLongValue] ==
        clock.nanoseconds + TestMaximumOperationNanoseconds);

    NSString *nonceConnection = [core openConnection:&error];
    SERVICE_CHECK(nonceConnection.length != 0);
    NSMutableDictionary *reusedNonce = TestHelloV2(2, bounded[@"nonce"]);
    error = nil;
    SERVICE_CHECK([core handleRequest:reusedNonce documents:nil sourceFDs:nil
        connectionID:nonceConnection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"REPLAY_REJECTED"]);
    NSMutableDictionary *freshSequenceNonce = TestHelloV2(2, nil);
    error = nil;
    SERVICE_CHECK([core handleRequest:freshSequenceNonce documents:nil sourceFDs:nil
        connectionID:nonceConnection exportFileDescriptor:&exportFD error:&error] != nil);

    NSMutableDictionary *substitution = TestHelloV2(2, nil);
    substitution[@"request_id"] = @"task2-substitution-request";
    substitution[@"deadline_ns"] = @([hello[@"deadline_ns"] unsignedLongLongValue] + 1);
    error = nil;
    SERVICE_CHECK([core handleRequest:substitution documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"SESSION_BINDING_MISMATCH"]);

    NSString *replayConnection = [core openConnection:&error];
    SERVICE_CHECK(replayConnection.length != 0);
    error = nil;
    SERVICE_CHECK([core handleRequest:bounded documents:nil sourceFDs:nil
        connectionID:replayConnection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"REPLAY_REJECTED"]);

    NSString *sessionID = (NSString *)hello[@"session_id"];
    NSNumber *deadline = (NSNumber *)hello[@"deadline_ns"];
    NSString *authorization = (NSString *)bounded[@"authorization_sha256"];
    NSDictionary *recoveryBody = @{@"schema_version": @1, @"operation": @"recovery",
                                   @"connection_id": connection};
    NSMutableDictionary *first = TestSignedRequestV2(recoveryBody, connection, sessionID, 1,
        deadline, authorization, @{});
    SERVICE_CHECK(first != nil);
    NSString *firstRequestID = first[@"request_id"];
    SERVICE_CHECK([core handleRequest:first documents:nil sourceFDs:nil connectionID:connection
        exportFileDescriptor:&exportFD error:&error] != nil);

    for (uint64_t sequence = 2; sequence <= 4098; sequence++) {
        NSMutableDictionary *request = TestSignedRequestV2(recoveryBody, connection, sessionID,
            sequence, deadline, authorization, @{});
        SERVICE_CHECK(request != nil);
        if (request == nil) break;
        NSDictionary *result = [core handleRequest:request documents:nil sourceFDs:nil
            connectionID:connection exportFileDescriptor:&exportFD error:&error];
        SERVICE_CHECK(result != nil);
        if (result == nil) break;
    }
    SERVICE_CHECK(store.recoveryCount == 4098);

    error = nil;
    SERVICE_CHECK([core handleRequest:first documents:nil sourceFDs:nil connectionID:connection
        exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"REPLAY_REJECTED"]);

    NSMutableDictionary *duplicateID = TestSignedRequestV2(recoveryBody, connection, sessionID,
        4099, deadline, authorization, @{});
    duplicateID[@"request_id"] = firstRequestID;
    error = nil;
    SERVICE_CHECK([core handleRequest:duplicateID documents:nil sourceFDs:nil connectionID:connection
        exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);

    AQServiceTestStore *restartStore = [[AQServiceTestStore alloc] init];
    __block NSUInteger restartToken = 0;
    AQServiceSessionCore *restarted = [[AQServiceSessionCore alloc]
        initWithStore:restartStore installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-2" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:clock
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            restartToken++;
            return [NSString stringWithFormat:@"restart-token-%lu", (unsigned long)restartToken];
        } error:&error];
    SERVICE_CHECK(restarted != nil);
    NSString *restartConnection = [restarted openConnection:&error];
    error = nil;
    SERVICE_CHECK([restarted handleRequest:bounded documents:nil sourceFDs:nil
        connectionID:restartConnection exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"SESSION_BINDING_MISMATCH"]);
    SERVICE_CHECK(restartStore.callbackCount == 0);
}

static void TestHelloStoreDeadlineCannotExtendOuterDeadline(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    AQServiceTestClock *clock = [[AQServiceTestClock alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:clock
        ownerVerifier:^BOOL(__unused NSData *data, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
        identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"deadline-token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection.length != 0);
    int exportFD = -1;
    clock.storeTicks = 1000000000000ULL; // Models continuous time advancing during suspend.
    mach_timebase_info_data_t timebase = {0, 0};
    SERVICE_CHECK(mach_timebase_info(&timebase) == KERN_SUCCESS);
    NSDictionary *baselineHello = TestHello();
    uint64_t mappedDeadline = 0;
    SERVICE_CHECK(AQStoreDeadlineTicksForMonotonicDeadline(
        [baselineHello[@"deadline_ns"] unsignedLongLongValue], clock.nanoseconds,
        clock.storeTicks, timebase.numer, timebase.denom, &mappedDeadline));
    NSArray *invalidStoreDeadlines = @[
        @(INT64_MAX),
        @(UINT64_MAX),
        @YES,
        @"not-a-tick-deadline",
        @(clock.storeTicks),
        @(mappedDeadline + 1)
    ];
    for (id storeDeadline in invalidStoreDeadlines) {
        NSMutableDictionary *hello = [TestHello() mutableCopy];
        hello[@"store_deadline_ticks"] = storeDeadline;
        error = nil;
        NSDictionary *response = [core handleRequest:hello documents:nil sourceFDs:nil
            connectionID:connection exportFileDescriptor:&exportFD error:&error];
        SERVICE_CHECK(response == nil);
        SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);
        SERVICE_CHECK(store.callbackCount == 0);
    }

    NSMutableDictionary *mappedHello = [baselineHello mutableCopy];
    mappedHello[@"store_deadline_ticks"] = @(mappedDeadline);
    error = nil;
    NSDictionary *mappedResponse = [core handleRequest:mappedHello documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(mappedResponse != nil && error == nil);
    NSString * _Nullable encodedConsent = mappedResponse[@"consent_envelope"];
    NSData *consentData = nil;
    if (encodedConsent != nil) {
        consentData = [[NSData alloc] initWithBase64EncodedString:encodedConsent ?: @"" options:0];
    }
    NSDictionary *consent = consentData == nil ? nil : AQParseJSON(consentData, NULL);
    SERVICE_CHECK(consent != nil);
    SERVICE_CHECK([consent[@"deadline_ns"] isEqual:mappedHello[@"deadline_ns"]]);
    SERVICE_CHECK([consent[@"store_deadline_ticks"] unsignedLongLongValue] == mappedDeadline);
    SERVICE_CHECK(store.callbackCount == 0);

    uint64_t originalDeadline = [mappedHello[@"deadline_ns"] unsignedLongLongValue];
    clock.nanoseconds = originalDeadline;
    clock.storeTicks = mappedDeadline;
    NSString *reconnect = [core openConnection:&error];
    SERVICE_CHECK(reconnect.length != 0);
    NSMutableDictionary *reconnectedHello = [mappedHello mutableCopy];
    reconnectedHello[@"request_id"] = @"request-2";
    reconnectedHello[@"sequence"] = @2;
    reconnectedHello[@"nonce"] = TestHelloNonce(2);
    error = nil;
    SERVICE_CHECK([core handleRequest:reconnectedHello documents:nil sourceFDs:nil
        connectionID:reconnect exportFileDescriptor:&exportFD error:&error] == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"OWNER_CONSENT_EXPIRED"]);
    SERVICE_CHECK(store.callbackCount == 0);
}

static void TestConcurrentConnectionOpenCloseAndPeerMessages(void) {
    // Hold two opens after their first capacity check to expose a stale count
    // decision, then exercise listener opens against serial peer messages/closes.
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    NSLock *identifierLock = [[NSLock alloc] init];
    __block NSUInteger nextIdentifier = 0;
    __block NSUInteger gatedIdentifiersRemaining = 0;
    dispatch_semaphore_t identifiersAtGate = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseIdentifiers = dispatch_semaphore_create(0);
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
 serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
   ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
       ownerVerifier:^BOOL(__unused NSData *consent, __unused NSData *signature,
                           __unused NSError **verifyError) { return YES; }
  identifierGenerator:^NSString *{
        [identifierLock lock];
        NSUInteger identifier = ++nextIdentifier;
        BOOL shouldWait = gatedIdentifiersRemaining > 0;
        if (shouldWait) gatedIdentifiersRemaining--;
        [identifierLock unlock];
        if (shouldWait) {
            dispatch_semaphore_signal(identifiersAtGate);
            dispatch_semaphore_wait(releaseIdentifiers, DISPATCH_TIME_FOREVER);
        }
        return [NSString stringWithFormat:@"connection-%lu", (unsigned long)identifier];
    }
                error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSMutableArray<NSString *> *connections = [NSMutableArray array];
    for (NSUInteger index = 0; index < 31; index++) {
        error = nil;
        NSString *connection = [core openConnection:&error];
        SERVICE_CHECK(connection.length != 0);
        if (connection != nil) [connections addObject:connection];
    }

    [identifierLock lock];
    gatedIdentifiersRemaining = 2;
    [identifierLock unlock];

    __block NSString *firstConcurrentConnection = nil;
    __block NSString *secondConcurrentConnection = nil;
    __block NSError *firstConcurrentError = nil;
    __block NSError *secondConcurrentError = nil;
    dispatch_queue_t concurrentOpenQueue = dispatch_queue_create(
        "com.argusromtoolkit.fixture-staging.tests.concurrent-open", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t concurrentOpenGroup = dispatch_group_create();
    dispatch_group_async(concurrentOpenGroup, concurrentOpenQueue, ^{
        firstConcurrentConnection = [core openConnection:&firstConcurrentError];
    });
    dispatch_group_async(concurrentOpenGroup, concurrentOpenQueue, ^{
        secondConcurrentConnection = [core openConnection:&secondConcurrentError];
    });

    BOOL bothIdentifiersReachedGate = YES;
    for (NSUInteger index = 0; index < 2; index++) {
        if (dispatch_semaphore_wait(identifiersAtGate,
                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
            bothIdentifiersReachedGate = NO;
        }
    }
    dispatch_semaphore_signal(releaseIdentifiers);
    dispatch_semaphore_signal(releaseIdentifiers);
    long concurrentOpenWait = dispatch_group_wait(concurrentOpenGroup,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    SERVICE_CHECK(bothIdentifiersReachedGate);
    SERVICE_CHECK(concurrentOpenWait == 0);
    if (concurrentOpenWait != 0) {
        dispatch_group_wait(concurrentOpenGroup, DISPATCH_TIME_FOREVER);
    }

    NSUInteger concurrentOpenCount = (firstConcurrentConnection != nil) +
                                     (secondConcurrentConnection != nil);
    SERVICE_CHECK(concurrentOpenCount == 1);
    if (firstConcurrentConnection != nil) [connections addObject:firstConcurrentConnection];
    if (secondConcurrentConnection != nil) [connections addObject:secondConcurrentConnection];
    NSError *failedOpenError = firstConcurrentConnection == nil
        ? firstConcurrentError : secondConcurrentError;
    SERVICE_CHECK([failedOpenError.localizedDescription isEqual:@"LIMIT_EXCEEDED"]);
    SERVICE_CHECK(connections.count == 32);

    dispatch_queue_t peerQueue = AQServiceSerialPeerQueue();
    dispatch_sync(peerQueue, ^{
        for (NSString *connection in connections) {
            [core invalidateConnection:connection reason:@"concurrent_test_reset"];
        }
    });
    [connections removeAllObjects];
    for (NSUInteger index = 0; index < 32; index++) {
        error = nil;
        NSString *connection = [core openConnection:&error];
        SERVICE_CHECK(connection.length != 0);
        if (connection != nil) [connections addObject:connection];
    }

    dispatch_queue_t listenerQueue = dispatch_queue_create(
        "com.argusromtoolkit.fixture-staging.tests.listener", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t availableConnectionSlots = dispatch_semaphore_create(0);
    dispatch_group_t workloadGroup = dispatch_group_create();
    __block NSUInteger listenerFailures = 0;
    __block NSUInteger peerFailures = 0;
    __block NSUInteger peerMessagesCompleted = 0;

    for (NSUInteger index = 0; index < connections.count; index++) {
        NSString *connection = connections[index];
        dispatch_group_enter(workloadGroup);
        dispatch_async(peerQueue, ^{
            NSError *peerError = nil;
            int exportFD = -1;
            NSDictionary *message = [core handleRequest:@{
                @"schema_version": @1,
                @"operation": @"readiness",
                @"request_id": [NSString stringWithFormat:@"initial-%lu", (unsigned long)index]
            } documents:nil sourceFDs:nil connectionID:connection
                exportFileDescriptor:&exportFD error:&peerError];
            if (message == nil || ![message[@"ready"] boolValue]) peerFailures++;
            else peerMessagesCompleted++;
            [core invalidateConnection:connection reason:@"concurrent_test"];
            dispatch_semaphore_signal(availableConnectionSlots);
            dispatch_group_leave(workloadGroup);
        });
    }

    dispatch_group_enter(workloadGroup);
    dispatch_async(listenerQueue, ^{
        for (NSUInteger index = 0; index < 64; index++) {
            if (dispatch_semaphore_wait(availableConnectionSlots,
                    dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
                listenerFailures++;
                break;
            }
            NSError *openError = nil;
            NSString *connection = [core openConnection:&openError];
            if (connection == nil) {
                listenerFailures++;
                break;
            }
            dispatch_group_enter(workloadGroup);
            dispatch_async(peerQueue, ^{
                NSError *peerError = nil;
                int exportFD = -1;
                NSDictionary *message = [core handleRequest:@{
                    @"schema_version": @1,
                    @"operation": @"readiness",
                    @"request_id": [NSString stringWithFormat:@"replacement-%lu",
                                                             (unsigned long)index]
                } documents:nil sourceFDs:nil connectionID:connection
                    exportFileDescriptor:&exportFD error:&peerError];
                if (message == nil || ![message[@"ready"] boolValue]) peerFailures++;
                else peerMessagesCompleted++;
                [core invalidateConnection:connection reason:@"concurrent_test"];
                dispatch_semaphore_signal(availableConnectionSlots);
                dispatch_group_leave(workloadGroup);
            });
        }
        dispatch_group_leave(workloadGroup);
    });

    long workloadWait = dispatch_group_wait(workloadGroup,
        dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    SERVICE_CHECK(workloadWait == 0);
    if (workloadWait != 0) dispatch_group_wait(workloadGroup, DISPATCH_TIME_FOREVER);
    SERVICE_CHECK(listenerFailures == 0);
    SERVICE_CHECK(peerFailures == 0);
    SERVICE_CHECK(peerMessagesCompleted == 32 + 64);
}

static void TestLoaderOverloadVerifiesFreshnessOnce(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    __block NSUInteger verifierCalls = 0;
    NSError *error = nil;
    AQServiceObservingCore *core = [[AQServiceObservingCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(NSData *__unused freshness, NSData *signature,
                            __unused NSError **verifyError) {
            verifierCalls++;
            return [signature isEqualToData:AQTestData(@"owner-signature")];
        } identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error];
    int exportFD = -1;
    NSDictionary *hello = [core handleRequest:TestHello() documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(hello != nil);
    if (hello == nil) return;

    NSUInteger mutationsAfterHello = core.recordMutationCount;
    NSDictionary *body = TestRecoveryBody(@"request-loader-once", connection);
    NSMutableDictionary *request = TestSignedRequest(body, connection,
        (NSString *)hello[@"session_id"], 1, 1, (NSNumber *)hello[@"deadline_ns"],
        (NSString *)TestHello()[@"authorization_sha256"], @{});
    SERVICE_CHECK(request != nil);
    if (request == nil) return;

    error = nil;
    exportFD = 0;
    NSDictionary *result = [core handleRequest:request documentsLoader:nil
        sourceFDsLoader:nil connectionID:connection
        exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result != nil);
    SERVICE_CHECK(verifierCalls == 1);
    SERVICE_CHECK(core.recordMutationCount == mutationsAfterHello + 1);
    SERVICE_CHECK(store.recoveryCount == 1);
    SERVICE_CHECK(exportFD == -1);
}

static void TestLoaderOverloadRejectsIncompatibleAttachmentsBeforeCheckout(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
        serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
        ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(NSData *__unused freshness, NSData *signature,
                            __unused NSError **verifyError) {
            return [signature isEqualToData:AQTestData(@"owner-signature")];
        } identifierGenerator:^NSString *{
            token++;
            return [NSString stringWithFormat:@"token-%lu", (unsigned long)token];
        } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;
    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection.length != 0);

    int exportFD = 123;
    NSDictionary *malformed = @{
        @"schema_version": @1, @"operation": @"hello"
    };
    NSDictionary *result = [core handleRequest:malformed documentsLoader:nil
        sourceFDsLoader:nil connectionID:connection
        exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK(exportFD == -1);

    __block NSUInteger documentLoaderCalls = 0;
    __block NSUInteger sourceFDLoaderCalls = 0;
    AQServiceDocumentsLoader documentsLoader = ^NSDictionary *{
        documentLoaderCalls++;
        return @{@"protected": @"document"};
    };
    AQServiceSourceFDsLoader sourceFDsLoader = ^NSDictionary *{
        sourceFDLoaderCalls++;
        return @{@"source": @1};
    };

    exportFD = 0;
    result = [core handleRequest:TestHello()
        documentsLoader:documentsLoader sourceFDsLoader:sourceFDsLoader
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);
    SERVICE_CHECK(documentLoaderCalls == 0);
    SERVICE_CHECK(sourceFDLoaderCalls == 0);
    SERVICE_CHECK(exportFD == -1);

    NSDictionary *readiness = @{
        @"schema_version": @1, @"operation": @"readiness",
        @"request_id": @"request-readiness-loader"
    };
    exportFD = 0;
    result = [core handleRequest:readiness documentsLoader:documentsLoader
        sourceFDsLoader:sourceFDsLoader connectionID:connection
        exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);
    SERVICE_CHECK(documentLoaderCalls == 0);
    SERVICE_CHECK(sourceFDLoaderCalls == 0);
    SERVICE_CHECK(exportFD == -1);

    exportFD = -1;
    NSDictionary *hello = [core handleRequest:TestHello() documents:nil sourceFDs:nil
        connectionID:connection exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(hello != nil);
    if (hello == nil) return;
    NSMutableDictionary *recovery = TestSignedRequest(
        TestRecoveryBody(@"request-recovery-loader", connection), connection,
        (NSString *)hello[@"session_id"], 1, 1, (NSNumber *)hello[@"deadline_ns"],
        (NSString *)TestHello()[@"authorization_sha256"], @{});
    SERVICE_CHECK(recovery != nil);
    if (recovery == nil) return;

    exportFD = 0;
    result = [core handleRequest:recovery documentsLoader:documentsLoader
        sourceFDsLoader:sourceFDsLoader connectionID:connection
        exportFileDescriptor:&exportFD error:&error];
    SERVICE_CHECK(result == nil);
    SERVICE_CHECK([error.localizedDescription isEqual:@"INVALID_REQUEST"]);
    SERVICE_CHECK(documentLoaderCalls == 0);
    SERVICE_CHECK(sourceFDLoaderCalls == 0);
    SERVICE_CHECK(exportFD == -1);
    SERVICE_CHECK(store.callbackCount == 0);
}

typedef struct {
    NSUInteger callCount;
    NSUInteger failureCall;
    NSUInteger shortWriteCall;
    BOOL observedShortWrite;
    BOOL observedFailure;
    NSUInteger outputLength;
    int requestedLengths[4];
    int returnedLengths[4];
    char output[64];
} AQServiceTestOutputWriter;

static int AQServiceTestWriteOutput(void *context, const char *buffer, int length) {
    AQServiceTestOutputWriter *writer = context;
    writer->callCount++;
    NSUInteger callIndex = writer->callCount - 1;
    if (callIndex < 4) writer->requestedLengths[callIndex] = length;
    if (writer->failureCall != 0 && writer->callCount == writer->failureCall) {
        writer->observedFailure = YES;
        if (callIndex < 4) writer->returnedLengths[callIndex] = -1;
        errno = EIO;
        return -1;
    }
    int acceptedLength = length;
    if (writer->shortWriteCall != 0 && writer->callCount == writer->shortWriteCall) {
        writer->observedShortWrite = length > 1;
        acceptedLength = MIN(length, 1);
    }
    if (acceptedLength > 0) {
        NSUInteger remaining = sizeof(writer->output) - writer->outputLength;
        NSUInteger copied = MIN((NSUInteger)acceptedLength, remaining);
        memcpy(writer->output + writer->outputLength, buffer, copied);
        writer->outputLength += copied;
    }
    if (callIndex < 4) writer->returnedLengths[callIndex] = acceptedLength;
    return acceptedLength;
}

static FILE *AQServiceTestOutputStream(AQServiceTestOutputWriter *writer,
                                       char *buffer, int bufferingMode) {
    FILE *stream = funopen(writer, NULL, AQServiceTestWriteOutput, NULL, NULL);
    SERVICE_CHECK(stream != NULL);
    if (stream == NULL) return NULL;
    int bufferSize = buffer == NULL ? 0 : 128;
    int result = setvbuf(stream, buffer, bufferingMode, bufferSize);
    SERVICE_CHECK(result == 0);
    if (result != 0) {
        fclose(stream);
        return NULL;
    }
    return stream;
}

static void TestSelfCheckOutputReportsWriteAndFlushFailures(void) {
    NSData *payload = [@"SERVICE_READY" dataUsingEncoding:NSUTF8StringEncoding];

    AQServiceTestOutputWriter success = {0};
    FILE *stream = AQServiceTestOutputStream(&success, NULL, _IONBF);
    if (stream == NULL) return;
    SERVICE_CHECK(AQServiceWriteSelfCheckOutputForTesting(payload, stream) == 0);
    SERVICE_CHECK(success.callCount == 2);
    NSData *expectedOutput = [@"SERVICE_READY\n" dataUsingEncoding:NSUTF8StringEncoding];
    SERVICE_CHECK(success.outputLength == expectedOutput.length);
    SERVICE_CHECK(memcmp(success.output, expectedOutput.bytes, expectedOutput.length) == 0);
    fclose(stream);

    AQServiceTestOutputWriter writeFailure = {0};
    writeFailure.failureCall = 1;
    stream = AQServiceTestOutputStream(&writeFailure, NULL, _IONBF);
    if (stream == NULL) return;
    SERVICE_CHECK(AQServiceWriteSelfCheckOutputForTesting(payload, stream) == 2);
    SERVICE_CHECK(writeFailure.callCount == 1);
    fclose(stream);

    AQServiceTestOutputWriter newlineFailure = {0};
    newlineFailure.failureCall = 2;
    stream = AQServiceTestOutputStream(&newlineFailure, NULL, _IONBF);
    if (stream == NULL) return;
    SERVICE_CHECK(AQServiceWriteSelfCheckOutputForTesting(payload, stream) == 2);
    SERVICE_CHECK(newlineFailure.callCount == 2);
    fclose(stream);

    AQServiceTestOutputWriter flushFailure = {0};
    flushFailure.failureCall = 1;
    char buffer[128] = {0};
    stream = AQServiceTestOutputStream(&flushFailure, buffer, _IOFBF);
    if (stream == NULL) return;
    SERVICE_CHECK(AQServiceWriteSelfCheckOutputForTesting(payload, stream) == 2);
    SERVICE_CHECK(flushFailure.callCount == 1);
    fclose(stream);

    AQServiceTestOutputWriter shortWrite = {0};
    shortWrite.shortWriteCall = 1;
    stream = AQServiceTestOutputStream(&shortWrite, NULL, _IONBF);
    if (stream == NULL) return;
    // A positive short sink write is transient: fwrite retries the remainder,
    // and the newline is then issued as a separate write.
    SERVICE_CHECK(AQServiceWriteSelfCheckOutputForTesting(payload, stream) == 0);
    SERVICE_CHECK(shortWrite.callCount == 3);
    SERVICE_CHECK(shortWrite.observedShortWrite);
    SERVICE_CHECK(shortWrite.requestedLengths[0] == (int)payload.length);
    SERVICE_CHECK(shortWrite.returnedLengths[0] == 1);
    SERVICE_CHECK(shortWrite.requestedLengths[1] == (int)payload.length - 1);
    SERVICE_CHECK(shortWrite.returnedLengths[1] == (int)payload.length - 1);
    SERVICE_CHECK(shortWrite.requestedLengths[2] == 1);
    SERVICE_CHECK(shortWrite.returnedLengths[2] == 1);
    SERVICE_CHECK(shortWrite.outputLength == expectedOutput.length);
    SERVICE_CHECK(memcmp(shortWrite.output, expectedOutput.bytes,
                         expectedOutput.length) == 0);
    fclose(stream);

    AQServiceTestOutputWriter shortThenFailure = {0};
    shortThenFailure.shortWriteCall = 1;
    shortThenFailure.failureCall = 2;
    stream = AQServiceTestOutputStream(&shortThenFailure, NULL, _IONBF);
    if (stream == NULL) return;
    // An error on the retry leaves only the accepted prefix in the stream.
    SERVICE_CHECK(AQServiceWriteSelfCheckOutputForTesting(payload, stream) == 2);
    SERVICE_CHECK(shortThenFailure.callCount == 2);
    SERVICE_CHECK(shortThenFailure.observedShortWrite);
    SERVICE_CHECK(shortThenFailure.observedFailure);
    SERVICE_CHECK(shortThenFailure.requestedLengths[0] == (int)payload.length);
    SERVICE_CHECK(shortThenFailure.returnedLengths[0] == 1);
    SERVICE_CHECK(shortThenFailure.requestedLengths[1] == (int)payload.length - 1);
    SERVICE_CHECK(shortThenFailure.returnedLengths[1] == -1);
    SERVICE_CHECK(shortThenFailure.outputLength == 1);
    SERVICE_CHECK(memcmp(shortThenFailure.output, expectedOutput.bytes, 1) == 0);
    fclose(stream);
}

static void TestSelfCheckOutputFailsWithClosedStandardOutput(void) {
    NSData *payload = [@"SERVICE_READY" dataUsingEncoding:NSUTF8StringEncoding];
    SERVICE_CHECK(fflush(stdout) == 0);

    pid_t child = fork();
    SERVICE_CHECK(child >= 0);
    if (child < 0) return;
    if (child == 0) {
        close(STDOUT_FILENO);
        int result = AQServiceWriteSelfCheckOutputForTesting(payload, stdout);
        _exit(result);
    }

    int result = 0;
    pid_t waited = 0;
    do {
        waited = waitpid(child, &result, 0);
    } while (waited < 0 && errno == EINTR);
    SERVICE_CHECK(waited == child);
    SERVICE_CHECK(WIFEXITED(result));
    SERVICE_CHECK(WEXITSTATUS(result) == 2);
}

#if defined(AQ_SERVICE_TESTING) && !defined(AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN)
static void TestProductionIsolationGateRejectsDirectStageRequest(void) {
    AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
    __block NSUInteger token = 0;
    NSError *error = nil;
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:store installationIdentity:@"installation-1"
 serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
   ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
        ownerVerifier:^BOOL(__unused NSData *consent, __unused NSData *signature,
                            __unused NSError **verifyError) { return YES; }
  identifierGenerator:^NSString *{
      token++;
      return [NSString stringWithFormat:@"token-%lu", (unsigned long)token];
  } error:&error];
    SERVICE_CHECK(core != nil);
    if (core == nil) return;

    NSString *connection = [core openConnection:&error];
    SERVICE_CHECK(connection != nil);
    if (connection == nil) return;
    TestPrepareAdmittedState(core, connection);
    NSMutableDictionary *request = TestStageRequest(connection, @"source-a", @{}, 1);
    NSUInteger callbacksBefore = store.callbackCount;
    AQServiceSetSyntheticMutationsAllowedForTesting(NO);
    int exportFD = -1;
    NSDictionary *result = [core handleRequest:request documents:nil sourceFDs:@{}
        connectionID:connection
        exportFileDescriptor:&exportFD error:&error];
    AQServiceSetSyntheticMutationsAllowedForTesting(YES);

    SERVICE_CHECK(result == nil);
    SERVICE_CHECK(error != nil && [error.localizedDescription
                                   isEqual:@"BLOCKED_UNSUPPORTED_EXCLUSIVITY"]);
    SERVICE_CHECK(store.callbackCount == callbacksBefore);
}
#endif

#ifdef AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN
static void TestProductionBuildRejectsLoaderStageAndCleanupRequests(void) {
    for (NSString *operation in @[@"stage", @"cleanup"]) {
        AQServiceTestStore *store = [[AQServiceTestStore alloc] init];
        __block NSUInteger token = 0;
        NSError *error = nil;
        AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
            initWithStore:store installationIdentity:@"installation-1"
     serviceBootIdentity:@"boot-1" brokerRevision:@"broker-1"
       ownerKeyIdentifier:@"owner-key-1" clock:[[AQServiceTestClock alloc] init]
            ownerVerifier:^BOOL(__unused NSData *consent, __unused NSData *signature,
                                __unused NSError **verifyError) { return YES; }
      identifierGenerator:^NSString *{
          token++;
          return [NSString stringWithFormat:@"production-token-%lu", (unsigned long)token];
      } error:&error];
        SERVICE_CHECK(core != nil);
        if (core == nil) continue;

        NSString *connection = [core openConnection:&error];
        SERVICE_CHECK(connection != nil);
        if (connection == nil) continue;
        TestPrepareAdmittedState(core, connection);
        NSDictionary *connections = [core valueForKey:@"connections"];
        id state = [connections objectForKey:connection];
        [state setValue:@[operation] forKey:@"operations"];

        NSDictionary *request = nil;
        __block BOOL sourceFDsLoaded = NO;
        AQServiceSourceFDsLoader sourceFDsLoader = nil;
        if ([operation isEqual:@"stage"]) {
            request = TestStageRequest(connection, @"source-a", @{}, 1);
            sourceFDsLoader = ^NSDictionary *{
                sourceFDsLoaded = YES;
                return @{};
            };
        } else {
            [state setValue:@YES forKey:@"cleanupAuthorized"];
            NSDictionary *body = @{
                @"schema_version": @1, @"operation": @"cleanup",
                @"connection_id": connection, @"session_id": @"stage-session",
                @"grant_id": @"grant-1", @"epoch": @1, @"sequence": @1,
                @"expected_generation": @0
            };
            request = TestSignedRequest(body, connection, @"stage-session", 1, 1,
                @1000, TestReviewAuthorizationSHA256(), @{});
        }
        SERVICE_CHECK(request != nil);
        if (request == nil) continue;

        NSUInteger callbacksBefore = store.callbackCount;
        int exportFD = -1;
        NSDictionary *result = [core handleRequest:request documentsLoader:nil
            sourceFDsLoader:sourceFDsLoader connectionID:connection
            exportFileDescriptor:&exportFD error:&error];
        SERVICE_CHECK(result == nil);
        SERVICE_CHECK(error != nil && [error.localizedDescription
                                       isEqual:@"BLOCKED_UNSUPPORTED_EXCLUSIVITY"]);
        SERVICE_CHECK(!sourceFDsLoaded);
        SERVICE_CHECK(store.callbackCount == callbacksBefore);
    }
}
#endif

int AQRunServiceTests(void) {
    @autoreleasepool {
        serviceFailures = 0;
        TestSelfCheckOutputReportsWriteAndFlushFailures();
        TestSelfCheckOutputFailsWithClosedStandardOutput();
        TestAdmitRejectsBeforeProtectedPayloadAccess();
        TestServiceSessionBinding();
        TestServiceRejectsStaleSignedFreshnessBeforeDispatch();
#if defined(AQ_SERVICE_TESTING) && !defined(AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN)
    TestWireHelloAuthorizationBinding();
    TestHelloRejectsAuthorizationPinMismatches();
    TestWireFreshnessRejectsBeforeProtectedPayloadAccess();
    TestAuthenticatedReceiptRecordAndQueryBoundary();
    TestReceiptJournalReservationRelease();
        TestReceiptJournalReleaseSyncFailureRetainsRecoveryObligation();
    TestReceiptJournalRecoversStaleTemporaryFiles();
    TestReceiptJournalRejectsTemporarySymlinks();
    TestReceiptLookupRejectsFIFOWithoutBlocking();
#endif
        TestServiceStrictFreshnessAndSequence();
        TestTask2TimingEpochNonceAndRequestIdentity();
        TestHelloStoreDeadlineCannotExtendOuterDeadline();
        TestConcurrentConnectionOpenCloseAndPeerMessages();
        TestServiceRejectsPriorSessionFreshness();
        TestServiceRejectsSignedRequestAfterRestart();
#if defined(AQ_SERVICE_TESTING) && !defined(AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN)
        TestFreshAdmissionRecoveryPolicy();
    TestAdmissionFailureReleasesOnlyItsReceiptReservation();
    TestAdmissionFailureReleaseFailureIsBlocked();
#endif
        TestExportAdmissionFailsClosedForRecoveryAndReceiptCapacity();
    TestFreshRecoverySessionCanStageAndExportDuringRestartRecovery();
    TestUnmarkedConnectionCannotOperateDuringRestartRecovery();
        TestStageBindsSignedSourceDescriptorIdentity();
#if defined(AQ_SERVICE_TESTING) && !defined(AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN)
        TestProductionIsolationGateRejectsDirectStageRequest();
#endif
    TestLoaderOverloadVerifiesFreshnessOnce();
    TestLoaderOverloadRejectsIncompatibleAttachmentsBeforeCheckout();
        fprintf(stderr, "service tests: %d failure(s)\n", serviceFailures);
        return serviceFailures;
    }
}

#if defined(AQ_SERVICE_TEST_MAIN) && !defined(AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN)
int main(void) { return AQRunServiceTests() == 0 ? 0 : 1; }
#endif

#ifdef AQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN
int main(void) {
    @autoreleasepool {
        serviceFailures = 0;
        TestProductionBuildRejectsLoaderStageAndCleanupRequests();
        fprintf(stderr, "production boundary tests: %d failure(s)\n", serviceFailures);
        return serviceFailures == 0 ? 0 : 1;
    }
}
#endif
