#import "AQBrokerProtocol.h"
#import "AQContract.h"
#import "AQJSON.h"
#import "AQSecurity.h"
#import "AQServiceProtocol.h"

#import <xpc/xpc.h>

#include <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

static const uint64_t AQBrokerReceiptQueryMaximumTimeoutNanoseconds = 5000000000ULL;

#define AQBrokerMaximumSessionLineBytes (12U * 1024U * 1024U)
#define AQBrokerMaximumDocumentsBytes (8U * 1024U * 1024U)

static NSError *AQBrokerRelayError(AQBrokerErrorCode code, NSString *description);

static BOOL AQBrokerWriteJSONLineToFDWithMaximumBytes(
    int fd, NSDictionary *value, NSUInteger maximumBytes,
    uint64_t deadlineNanoseconds, AQBrokerMonotonicClock clock, NSError **error) {
    NSData *encoded = AQCanonicalJSONWithMaximumBytes(value, maximumBytes, error);
    if (encoded == nil) return NO;
    NSMutableData *line = [encoded mutableCopy];
    [line appendBytes:"\n" length:1];
    if (deadlineNanoseconds != 0) {
        return AQBrokerWriteAllUntilDeadline(fd, line, deadlineNanoseconds, clock, error);
    }
    return AQBrokerWriteAll(fd, line, error);
}

static BOOL AQBrokerWriteJSONLineToFD(int fd, NSDictionary *value,
                                      uint64_t deadlineNanoseconds,
                                      AQBrokerMonotonicClock clock,
                                      NSError **error) {
    return AQBrokerWriteJSONLineToFDWithMaximumBytes(
        fd, value, AQServiceMaximumRequestBytes, deadlineNanoseconds, clock, error);
}

static BOOL AQBrokerWriteReceiptJSONLineToFD(int fd, NSDictionary *value,
                                             uint64_t deadlineNanoseconds,
                                             AQBrokerMonotonicClock clock,
                                             NSError **error) {
    return AQBrokerWriteJSONLineToFDWithMaximumBytes(
        fd, value, AQServiceMaximumReceiptBytes, deadlineNanoseconds, clock, error);
}

/** Converts a closed output pipe into EPIPE so the request state machine can
 * retain its uncertainty and fail closed instead of terminating on SIGPIPE. */
static BOOL AQBrokerConfigureSIGPIPE(void) {
    struct sigaction action = {0};
    action.sa_handler = SIG_IGN;
    sigemptyset(&action.sa_mask);
    return sigaction(SIGPIPE, &action, NULL) == 0;
}

static BOOL AQBrokerPrintCodeTo(FILE *stream, NSString *status, NSString *code) {
    NSDictionary *value = @{@"status": status, @"code": code};
    return AQBrokerWriteJSONLineToFD(fileno(stream), value, 0, nil, NULL);
}

static int AQBrokerRelayFailure(NSString *code) {
    (void)AQBrokerPrintCodeTo(stderr, @"BLOCKED", code);
    return 2;
}

static BOOL AQBrokerPrintCode(NSString *status, NSString *code) {
    return AQBrokerPrintCodeTo(stdout, status, code);
}

static NSData *AQBrokerReadStdin(void) {
    NSMutableData *data = [NSMutableData data];
    uint8_t chunk[4096];
    for (;;) {
        ssize_t count = read(STDIN_FILENO, chunk, sizeof(chunk));
        if (count == 0) break;
        if (count < 0 || data.length > AQServiceMaximumRequestBytes - (NSUInteger)count) return nil;
        [data appendBytes:chunk length:(NSUInteger)count];
    }
    return data.length == 0 ? nil : data;
}

/** Reads one bounded input file only when it is an owner-only, single-link
 * regular file. O_NOFOLLOW prevents pathname substitution by a symlink, and
 * O_NONBLOCK lets fstat reject a FIFO before reading from it could block. */
static NSData *AQBrokerReadPrivateFile(NSString *path, uid_t owner, NSError **error) {
    int fd = open(path.fileSystemRepresentation,
                  O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    struct stat info = {0};
    if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_nlink != 1 ||
        info.st_uid != owner || (info.st_mode & 077) != 0 || info.st_size <= 0 ||
        info.st_size > (off_t)AQServiceMaximumRequestBytes) {
        if (fd >= 0) close(fd);
        if (error != NULL) *error = [NSError errorWithDomain:AQBrokerErrorDomain
                                                        code:AQBrokerInvalidFrame
                                                    userInfo:@{NSLocalizedDescriptionKey:@"CONSENT_FILE_INVALID"}];
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
    ssize_t total = 0;
    while (total < info.st_size) {
        ssize_t count = read(fd, (uint8_t *)data.mutableBytes + total, (size_t)(info.st_size - total));
        if (count <= 0) { close(fd); return nil; }
        total += count;
    }
    close(fd);
    return data;
}

static BOOL AQBrokerLoadPolicy(AQInstallationPolicy **policy, NSError **error) {
    *policy = AQLoadInstallationPolicy(error);
    return *policy != nil && (*policy).ownerPublicKey != nil;
}

#if defined(AQ_BROKER_TESTING)
static BOOL (*AQBrokerSelfCheckPolicyLoader)(AQInstallationPolicy **, NSError **) =
    AQBrokerLoadPolicy;
static BOOL (*AQBrokerSelfCheckPeerAPIProbe)(NSError **) = AQAuthenticatedPeerAPIsAvailable;
static BOOL (*AQBrokerSelfCheckServiceIdentityProbe)(AQInstallationPolicy *, NSError **) =
    AQValidateNonLoginServiceIdentity;
#define AQ_BROKER_SELF_CHECK_POLICY_LOADER AQBrokerSelfCheckPolicyLoader
#define AQ_BROKER_SELF_CHECK_PEER_API_PROBE AQBrokerSelfCheckPeerAPIProbe
#define AQ_BROKER_SELF_CHECK_SERVICE_IDENTITY_PROBE AQBrokerSelfCheckServiceIdentityProbe
#else
#define AQ_BROKER_SELF_CHECK_POLICY_LOADER AQBrokerLoadPolicy
#define AQ_BROKER_SELF_CHECK_PEER_API_PROBE AQAuthenticatedPeerAPIsAvailable
#define AQ_BROKER_SELF_CHECK_SERVICE_IDENTITY_PROBE AQValidateNonLoginServiceIdentity
#endif

static int AQBrokerSelfCheck(void) {
    NSError *error = nil;
    AQInstallationPolicy *policy = nil;
    if (!AQ_BROKER_SELF_CHECK_POLICY_LOADER(&policy, &error)) {
        AQBrokerPrintCode(@"BLOCKED", @"POLICY_OR_OWNER_KEY_UNAVAILABLE");
        return 2;
    }
    if (!AQ_BROKER_SELF_CHECK_PEER_API_PROBE(&error)) {
        AQBrokerPrintCode(@"BLOCKED", @"AUTHENTICATED_PEER_API_UNAVAILABLE");
        return 2;
    }
    if (!AQ_BROKER_SELF_CHECK_SERVICE_IDENTITY_PROBE(policy, &error)) {
        AQBrokerPrintCode(@"BLOCKED", @"SERVICE_IDENTITY_INVALID");
        return 2;
    }
    AQBrokerPrintCode(@"NOT_READY", @"AWAITING_XPC_DEPENDENCY_PROOF");
    return 2;
}

static NSMutableArray<NSNumber *> *AQBrokerSourceFDs(int argc, const char *argv[], int start) {
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    for (int index = start; index < argc; ++index) {
        if (strncmp(argv[index], "--source-fd=", 12) != 0) continue;
        NSString *value = [NSString stringWithUTF8String:argv[index] + 12];
        NSArray *parts = [value componentsSeparatedByString:@"="];
        if (parts.count != 2) return nil;
        int fd = [parts[1] intValue];
        if (fd < 0) return nil;
        [result addObject:@(fd)];
    }
    return result;
}

static id _Nullable AQBrokerDecodeDocumentValue(id value, NSUInteger *totalBytes) {
    if ([value isKindOfClass:NSString.class]) {
        NSString *encoded = value;
        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        if (decoded == nil ||
            ![[decoded base64EncodedStringWithOptions:0] isEqual:encoded] ||
            decoded.length > AQServiceMaximumDocumentBytes ||
            *totalBytes > AQBrokerMaximumDocumentsBytes - decoded.length) return nil;
        *totalBytes += decoded.length;
        return decoded;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            id decoded = AQBrokerDecodeDocumentValue(item, totalBytes);
            if (decoded == nil) return nil;
            [result addObject:decoded];
        }
        return result;
    }
    return nil;
}

static NSDictionary * _Nullable AQBrokerDecodeDocuments(id value, NSError **error) {
    NSSet *keys = [NSSet setWithArray:@[
        @"consent", @"signature", @"manifest", @"plan", @"oracles", @"evidence"
    ]];
    if (![value isKindOfClass:NSDictionary.class] ||
        [(NSDictionary *)value count] != keys.count) {
        if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                                        @"ADMISSION_DOCUMENTS_INVALID");
        return nil;
    }
    NSDictionary *wire = value;
    for (id key in wire) {
        if (![key isKindOfClass:NSString.class] || ![keys containsObject:key]) {
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                                            @"ADMISSION_DOCUMENTS_INVALID");
            return nil;
        }
    }
    NSUInteger total = 0;
    NSMutableDictionary *decoded = [NSMutableDictionary dictionary];
    for (NSString *key in wire) {
        id value = AQBrokerDecodeDocumentValue(wire[key], &total);
        if (value == nil) {
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                                            @"ADMISSION_DOCUMENTS_INVALID");
            return nil;
        }
        decoded[key] = value;
    }
    return decoded;
}

static NSError *AQBrokerRelayError(AQBrokerErrorCode code, NSString *description);

static NSString * _Nullable AQBrokerOptionValue(int argc, const char *argv[], int start,
                                                NSString *prefix, NSError **error) {
    NSString *value = nil;
    for (int index = start; index < argc; ++index) {
        NSString *argument = [NSString stringWithUTF8String:argv[index]];
        if (argument == nil || ![argument hasPrefix:prefix]) continue;
        NSString *candidate = [argument substringFromIndex:prefix.length];
        if (candidate.length == 0 || value != nil) {
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                            @"BROKER_OPTION_INVALID");
            }
            return nil;
        }
        value = candidate;
    }
    return value;
}

static NSData * _Nullable AQBrokerAuthorizationData(NSString *path,
                                                    AQInstallationPolicy *policy,
                                                    NSError **error) {
    NSData *data = AQBrokerReadPrivateFile(path, policy.ownerUID, error);
    if (data == nil) return nil;
    NSError *parseError = nil;
    id authorization = AQParseJSON(data, &parseError);
    NSData *canonical = [authorization isKindOfClass:NSDictionary.class]
        ? AQCanonicalJSON(authorization, NULL) : nil;
    if (![authorization isKindOfClass:NSDictionary.class] ||
        ![canonical isEqualToData:data]) {
        if (error != NULL) {
            *error = AQBrokerRelayError(AQBrokerFreshAuthenticationRequired,
                                        @"AUTHORIZATION_FILE_INVALID");
        }
        return nil;
    }
    return data;
}

static NSError *AQBrokerRelayError(AQBrokerErrorCode code, NSString *description) {
    return [NSError errorWithDomain:AQBrokerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL AQBrokerOwnerToken(id value) {
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

static BOOL AQBrokerOwnerDigest(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 64) return NO;
    static NSCharacterSet *hexadecimal;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hexadecimal = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    });
    return [value rangeOfCharacterFromSet:hexadecimal.invertedSet].location == NSNotFound;
}

static NSString *AQBrokerExactBytesSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); ++index) {
        [text appendFormat:@"%02x", digest[index]];
    }
    return text;
}

static xpc_object_t _Nullable AQBrokerCreateXPCValue(id value) {
    if ([value isKindOfClass:NSString.class]) {
        const char *text = [(NSString *)value UTF8String];
        return text == NULL ? NULL : xpc_string_create(text);
    }
    if ([value isKindOfClass:NSData.class]) {
        NSData *data = value;
        if (data.length > 64 * 1024) return NULL;
        return xpc_data_create(data.bytes, data.length);
    }
    if ([value isKindOfClass:NSNumber.class]) {
        NSNumber *number = value;
        if (CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) {
            return xpc_bool_create(number.boolValue);
        }
        if (strcmp(number.objCType, @encode(double)) == 0 ||
            strcmp(number.objCType, @encode(float)) == 0 || number.longLongValue < 0) {
            return NULL;
        }
        return xpc_uint64_create(number.unsignedLongLongValue);
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSArray *array = value;
        if (array.count > 256) return NULL;
        xpc_object_t result = xpc_array_create(NULL, 0);
        if (result == NULL) return NULL;
        for (id item in array) {
            xpc_object_t child = AQBrokerCreateXPCValue(item);
            if (child == NULL) return NULL;
            xpc_array_set_value(result, XPC_ARRAY_APPEND, child);
        }
        return result;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = value;
        if (dictionary.count > 256) return NULL;
        xpc_object_t result = xpc_dictionary_create(NULL, NULL, 0);
        if (result == NULL) return NULL;
        for (id key in dictionary) {
            if (![key isKindOfClass:NSString.class]) return NULL;
            xpc_object_t child = AQBrokerCreateXPCValue(dictionary[key]);
            if (child == NULL) return NULL;
            const char *name = [(NSString *)key UTF8String];
            if (name == NULL) return NULL;
            xpc_dictionary_set_value(result, name, child);
        }
        return result;
    }
    return NULL;
}

/** Builds the service XPC envelope while copying reviewed authorization bytes
 * into a distinct message field. JSON request data cannot carry NSData, so
 * losing this attachment would make a structurally valid hello impossible for
 * the service to authenticate. */
static xpc_object_t _Nullable AQBrokerCreateXPCRequestMessage(
    NSData *serviceRequestData,
    NSArray<NSNumber *> *sourceFDs,
    NSDictionary *documents,
    NSData * _Nullable authorizationData) {
    if (![serviceRequestData isKindOfClass:NSData.class] || serviceRequestData.length == 0 ||
        serviceRequestData.length > AQServiceMaximumRequestBytes ||
        ![sourceFDs isKindOfClass:NSArray.class] ||
        sourceFDs.count > AQServiceMaximumSourceDescriptors ||
        (authorizationData != nil &&
         (![authorizationData isKindOfClass:NSData.class] || authorizationData.length == 0 ||
          authorizationData.length > AQServiceMaximumDocumentBytes))) {
        return NULL;
    }
    const void * _Nullable authorizationBytes = NULL;
    if (authorizationData != nil) {
        authorizationBytes = authorizationData.bytes;
        if (authorizationBytes == NULL) return NULL;
    }
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    if (message == NULL) return NULL;
    xpc_dictionary_set_uint64(message, "version", 1);
    xpc_dictionary_set_data(message, "request", serviceRequestData.bytes,
                            serviceRequestData.length);
    if (authorizationData != nil) {
        xpc_dictionary_set_data(message, "authorization", authorizationBytes,
                                authorizationData.length);
    }
    if (documents != nil) {
        xpc_object_t converted = AQBrokerCreateXPCValue(documents);
        if (converted == NULL || xpc_get_type(converted) != XPC_TYPE_DICTIONARY) return NULL;
        xpc_dictionary_set_value(message, "documents", converted);
    }
    if (sourceFDs.count != 0) {
        xpc_object_t array = xpc_array_create(NULL, 0);
        if (array == NULL) return NULL;
        for (NSNumber *descriptor in sourceFDs) {
            if (![descriptor isKindOfClass:NSNumber.class]) {
                return NULL;
            }
            int fd = descriptor.intValue;
            if (fd < 0 || fcntl(fd, F_GETFD) < 0) {
                return NULL;
            }
            xpc_array_set_fd(array, XPC_ARRAY_APPEND, fd);
        }
        xpc_dictionary_set_value(message, "source_fds", array);
    }
    return message;
}

@interface AQBrokerReplyCapture : NSObject
@property(nonatomic, strong, nullable) NSDictionary *response;
@property(nonatomic, strong, nullable) NSError *error;
@property(nonatomic) int exportFD;
- (BOOL)finishWithResponse:(nullable NSDictionary *)response
                     error:(nullable NSError *)error
                  exportFD:(int)exportFD;
- (BOOL)waitUntilDeadline:(dispatch_time_t)deadline;
- (BOOL)abandon;
@end

@implementation AQBrokerReplyCapture {
    NSLock *_lock;
    dispatch_semaphore_t _completed;
    BOOL _finished;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _lock = [[NSLock alloc] init];
    _completed = dispatch_semaphore_create(0);
    _exportFD = -1;
    return self;
}

- (BOOL)finishWithResponse:(NSDictionary *)response
                     error:(NSError *)error
                  exportFD:(int)exportFD {
    [_lock lock];
    if (_finished) {
        [_lock unlock];
        if (exportFD >= 0) close(exportFD);
        return NO;
    }
    _finished = YES;
    self.response = response;
    self.error = error;
    self.exportFD = exportFD;
    [_lock unlock];
    dispatch_semaphore_signal(_completed);
    return YES;
}

- (BOOL)waitUntilDeadline:(dispatch_time_t)deadline {
    long waitResult = dispatch_semaphore_wait(_completed, deadline);
    [_lock lock];
    if (_finished) {
        [_lock unlock];
        return YES;
    }
    if (waitResult != 0) {
        _finished = YES;
        int exportFD = self.exportFD;
        self.exportFD = -1;
        [_lock unlock];
        if (exportFD >= 0) close(exportFD);
        return NO;
    }
    _finished = YES;
    [_lock unlock];
    return YES;
}

- (BOOL)abandon {
    [_lock lock];
    if (_finished) {
        [_lock unlock];
        return NO;
    }
    _finished = YES;
    int exportFD = self.exportFD;
    self.exportFD = -1;
    [_lock unlock];
    if (exportFD >= 0) close(exportFD);
    dispatch_semaphore_signal(_completed);
    return YES;
}
@end

/* Owns one broker-owned XPC connection. Configuration installs the service's
 * code requirement before resume; every reply is independently authenticated
 * before its JSON or descriptor reaches session state. A failed or timed-out
 * operation causes the connection to be discarded so later work cannot carry
 * an old reply into a new generation. */
@interface AQBrokerXPCTransport : NSObject
@property(nonatomic, strong) AQInstallationPolicy *policy;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong, nullable) xpc_connection_t connection;
- (instancetype)initWithPolicy:(AQInstallationPolicy *)policy;
- (BOOL)ensureConnectionWithError:(NSError **)error;
- (void)invalidate;
- (nullable NSDictionary *)exchangeReceiptControl:(NSDictionary *)request
                              deadlineNanoseconds:(uint64_t)deadline
                                            error:(NSError **)error;
- (nullable NSDictionary *)exchangeRequest:(NSDictionary *)request
                        serviceRequestData:(NSData *)serviceRequestData
                                sourceFDs:(NSArray<NSNumber *> *)sourceFDs
                                documents:(NSDictionary *)documents
                         authorizationData:(NSData *)authorizationData
                                  session:(AQBrokerSequentialSession *)session
                                    token:(uint64_t *)token
                               exportFDOut:(int *)exportFD
                             outcomeKnown:(BOOL *)outcomeKnown
                                    error:(NSError **)error;
@end

@implementation AQBrokerXPCTransport
- (instancetype)initWithPolicy:(AQInstallationPolicy *)policy {
    if (!(self = [super init])) return nil;
    _policy = policy;
    _queue = dispatch_queue_create("com.argusromtoolkit.fixture-staging.broker.xpc",
                                   DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)ensureConnectionWithError:(NSError **)error {
    if (self.connection != nil) return YES;
    const char *serviceName = AQMachServiceName.UTF8String;
    if (serviceName == NULL) {
        if (error != NULL) {
            *error = AQBrokerRelayError(AQBrokerInvalidRequest, @"SERVICE_NAME_UNAVAILABLE");
        }
        return NO;
    }
    xpc_connection_t connection = xpc_connection_create_mach_service(serviceName, self.queue, 0);
    NSError *authenticationError = nil;
    if (connection == NULL ||
        !AQConfigurePeerRequirement(connection, self.policy, AQPeerService,
                                    &authenticationError)) {
        if (connection != NULL) xpc_connection_cancel(connection);
        if (error != NULL) {
            *error = AQBrokerRelayError(
                AQBrokerReconnectRequired,
                authenticationError.localizedDescription ?:
                    @"SERVICE_CONNECTION_AUTHENTICATION_FAILED");
        }
        return NO;
    }
    self.connection = connection;
    xpc_connection_resume(connection);
    return YES;
}

- (nullable NSDictionary *)exchangeReceiptControl:(NSDictionary *)request
                              deadlineNanoseconds:(uint64_t)deadline
                                            error:(NSError **)error {
    if (![self ensureConnectionWithError:error]) return nil;
    NSData *encoded = AQCanonicalJSONWithMaximumBytes(
        request, AQServiceMaximumReceiptBytes, error);
    if (encoded == nil || encoded.length > AQServiceMaximumReceiptBytes) return nil;
    xpc_connection_t connection = self.connection;
    if (connection == nil) return nil;
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(message, "version", 1);
    xpc_dictionary_set_data(message, "request", encoded.bytes, encoded.length);
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block xpc_object_t captured = NULL;
    xpc_connection_send_message_with_reply(connection, message,
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(xpc_object_t reply) {
            captured = reply;
            dispatch_semaphore_signal(semaphore);
        });
    uint64_t now = AQBrokerSystemClockNanoseconds();
    if (now == UINT64_MAX || now >= deadline ||
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)MIN(deadline - now, (uint64_t)INT64_MAX))) != 0) {
        if (error != NULL) *error = AQBrokerRelayError(AQBrokerDeadlineExpired,
                                                       @"RECEIPT_CONTROL_TIMEOUT");
        return nil;
    }
    NSError *peerError = nil;
    size_t length = 0;
    const void *bytes = captured == NULL ? NULL : xpc_dictionary_get_data(captured, "response", &length);
    NSDictionary *response = nil;
    if (captured != NULL && AQValidatePeerMessage(captured, self.policy, AQPeerService, &peerError) &&
        bytes != NULL && length <= AQServiceMaximumReceiptBytes) {
        id decoded = AQParseJSONWithMaximumBytes(
            [NSData dataWithBytes:bytes length:length], AQServiceMaximumReceiptBytes, &peerError);
        if ([decoded isKindOfClass:NSDictionary.class]) response = decoded;
    }
    if (response == nil || ![response[@"status"] isEqual:@"OK"]) {
        if (error != NULL) *error = AQBrokerRelayError(AQBrokerBindingMismatch,
                                                       @"RECEIPT_CONTROL_REJECTED");
        return nil;
    }
    return response;
}

- (void)invalidate {
    xpc_connection_t connection = self.connection;
    if (connection == nil) return;
    xpc_connection_cancel(connection);
    self.connection = nil;
}

- (nullable NSDictionary *)exchangeRequest:(NSDictionary *)request
                        serviceRequestData:(NSData *)serviceRequestData
                                sourceFDs:(NSArray<NSNumber *> *)sourceFDs
                                documents:(NSDictionary *)documents
                         authorizationData:(NSData *)authorizationData
                                  session:(AQBrokerSequentialSession *)session
                                    token:(uint64_t *)token
                               exportFDOut:(int *)exportFD
                             outcomeKnown:(BOOL *)outcomeKnown
                                    error:(NSError **)error {
    if (token != NULL) *token = 0;
    if (exportFD != NULL) *exportFD = -1;
    if (outcomeKnown != NULL) *outcomeKnown = NO;
    if (error != NULL) *error = nil;

    if (session.requiresFreshAuthentication && !session.hasActiveRequest) [self invalidate];
    if (![self ensureConnectionWithError:error]) return nil;
    (void)[session connectionOpened];

    uint64_t grantedToken = 0;
    if (![session beginRequest:request token:&grantedToken error:error]) return nil;
    if (token != NULL) *token = grantedToken;

    uint64_t remaining = 0;
    if (![session remainingNanosecondsForToken:grantedToken remaining:&remaining error:error]) {
        [session completeRequestForToken:grantedToken outcomeKnown:NO error:NULL];
        [self invalidate];
        return nil;
    }
    int64_t relativeNanoseconds = remaining > (uint64_t)INT64_MAX
        ? INT64_MAX : (int64_t)remaining;
    dispatch_time_t waitDeadline = dispatch_time(DISPATCH_TIME_NOW, relativeNanoseconds);

    BOOL hello = [request[@"operation"] isEqual:@"hello"];
    if (hello) {
        NSString *expectedAuthorizationSHA256 = request[@"authorization_sha256"];
        if (![authorizationData isKindOfClass:NSData.class] || authorizationData.length == 0 ||
            authorizationData.length > AQServiceMaximumDocumentBytes ||
            ![expectedAuthorizationSHA256 isKindOfClass:NSString.class] ||
            ![AQBrokerExactBytesSHA256(authorizationData)
                isEqual:expectedAuthorizationSHA256]) {
            [session completeRequestForToken:grantedToken outcomeKnown:YES error:NULL];
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerFreshAuthenticationRequired,
                                            @"AUTHORIZATION_BYTES_REQUIRED");
            }
            return nil;
        }
    } else {
        authorizationData = nil;
    }
    xpc_object_t message = AQBrokerCreateXPCRequestMessage(serviceRequestData, sourceFDs,
                                                           documents, authorizationData);
    if (message == NULL) {
        [session completeRequestForToken:grantedToken outcomeKnown:YES error:NULL];
        if (error != NULL) {
            *error = AQBrokerRelayError(AQBrokerInvalidRequest, @"XPC_REQUEST_INVALID");
        }
        return nil;
    }

    AQBrokerReplyCapture *capture = [[AQBrokerReplyCapture alloc] init];
    xpc_connection_t connection = self.connection;
    if (connection == nil) {
        [session completeRequestForToken:grantedToken outcomeKnown:NO error:NULL];
        if (error != NULL) {
            *error = AQBrokerRelayError(AQBrokerReconnectRequired,
                                        @"SERVICE_CONNECTION_UNAVAILABLE");
        }
        return nil;
    }
    xpc_connection_send_message_with_reply(connection, message, self.queue,
                                           ^(xpc_object_t reply) {
        NSError *replyError = nil;
        NSDictionary *parsed = nil;
        if (reply == NULL || xpc_get_type(reply) == XPC_TYPE_ERROR ||
            !AQValidatePeerMessage(reply, self.policy, AQPeerService, &replyError)) {
            [capture finishWithResponse:nil
                                  error:replyError ?: AQBrokerRelayError(
                                      AQBrokerReconnectRequired,
                                      @"SERVICE_CONNECTION_AUTHENTICATION_FAILED")
                               exportFD:-1];
            return;
        }

        size_t length = 0;
        const void *bytes = xpc_dictionary_get_data(reply, "response", &length);
        id candidate = (bytes != NULL && length <= AQServiceMaximumRequestBytes)
            ? AQParseJSON([NSData dataWithBytes:bytes length:length], NULL) : nil;
        if (![candidate isKindOfClass:NSDictionary.class]) {
            [capture finishWithResponse:nil
                                  error:AQBrokerRelayError(AQBrokerInvalidRequest,
                                                           @"SERVICE_RESPONSE_INVALID")
                               exportFD:-1];
            return;
        }
        parsed = candidate;

        NSError *acceptError = nil;
        if (![session acceptResponseForToken:grantedToken
                                    response:parsed
                                       error:&acceptError]) {
            [capture finishWithResponse:nil
                                  error:acceptError ?: AQBrokerRelayError(
                                      AQBrokerLateReply, @"LATE_REPLY_REJECTED")
                               exportFD:-1];
            return;
        }

        int duplicatedExportFD = -1;
        xpc_object_t fdValue = xpc_dictionary_get_value(reply, "export_fd");
        if (fdValue != NULL && xpc_get_type(fdValue) == XPC_TYPE_FD) {
            duplicatedExportFD = xpc_fd_dup(fdValue);
        }
        if ([request[@"operation"] isEqual:@"export"] && duplicatedExportFD < 0) {
            [capture finishWithResponse:nil
                                  error:AQBrokerRelayError(AQBrokerBindingMismatch,
                                                           @"EXPORT_BINDING_INVALID")
                               exportFD:-1];
            return;
        }
        [capture finishWithResponse:parsed error:nil exportFD:duplicatedExportFD];
    });

    if (![capture waitUntilDeadline:waitDeadline]) {
        [session completeRequestForToken:grantedToken outcomeKnown:NO error:NULL];
        [self invalidate];
        if (error != NULL) {
            *error = AQBrokerRelayError(AQBrokerDeadlineExpired,
                                        @"SERVICE_RESPONSE_TIMEOUT");
        }
        return nil;
    }
    if (capture.error != nil || capture.response == nil) {
        if (capture.exportFD >= 0) close(capture.exportFD);
        [session connectionLostWithOutcomeKnown:NO];
        [self invalidate];
        if (error != NULL) {
            *error = capture.error ?: AQBrokerRelayError(AQBrokerInvalidRequest,
                                                         @"SERVICE_RESPONSE_INVALID");
        }
        return nil;
    }

    if (exportFD != NULL) *exportFD = capture.exportFD;
    if (outcomeKnown != NULL) *outcomeKnown = YES;
    return capture.response;
}
@end

static BOOL AQBrokerProcessRequest(NSDictionary *request,
                                   BOOL sessionMode,
                                   AQInstallationPolicy *policy,
                                   AQBrokerXPCTransport *transport,
                                   AQBrokerSequentialSession *session,
                                   NSArray<NSNumber *> *sourceFDs,
                                   NSData * _Nullable authorizationData,
                                   NSString * _Nullable receiverReceiptDirectory,
                                    int deliveryFD,
                                   BOOL *responsePrinted,
                                   BOOL *fatalOutputFailure,
                                   NSError **error) {
    if (responsePrinted != NULL) *responsePrinted = NO;
    if (fatalOutputFailure != NULL) *fatalOutputFailure = NO;
    (void)sessionMode;
    (void)policy;
    NSString *operation = request[@"operation"];
    if ([operation isEqual:@"receipt_query"]) {
        NSDictionary *binding = request[@"binding"];
        NSNumber *deadlineNumber = [binding isKindOfClass:NSDictionary.class]
            ? binding[@"deadline_ns"] : nil;
        if (![deadlineNumber isKindOfClass:NSNumber.class] ||
            CFGetTypeID((__bridge CFTypeRef)deadlineNumber) != CFNumberGetTypeID() ||
            deadlineNumber.unsignedLongLongValue == 0) {
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                                            @"RECEIPT_QUERY_INVALID");
            return NO;
        }
        NSNumber *queryDeadlineNumber = request[@"query_deadline_ns"];
        if (![queryDeadlineNumber isKindOfClass:NSNumber.class] ||
            CFGetTypeID((__bridge CFTypeRef)queryDeadlineNumber) != CFNumberGetTypeID() ||
            CFNumberIsFloatType((__bridge CFNumberRef)queryDeadlineNumber)) {
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                @"RECEIPT_QUERY_DEADLINE_INVALID");
            return NO;
        }
        uint64_t queryDeadline = queryDeadlineNumber.unsignedLongLongValue;
        uint64_t now = AQBrokerSystemClockNanoseconds();
        if (now == UINT64_MAX || queryDeadline <= now) {
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerDeadlineExpired,
                @"RECEIPT_QUERY_DEADLINE_EXPIRED");
            return NO;
        }
        if (queryDeadline - now > AQBrokerReceiptQueryMaximumTimeoutNanoseconds) {
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                @"RECEIPT_QUERY_DEADLINE_TOO_FAR");
            return NO;
        }

        /* Recovery may begin after the operation deadline. Keep that original
         * deadline in the receipt binding and use a separate short budget only
         * for this read-only query and its response. */
        NSMutableDictionary *controlRequest = [request mutableCopy];
        [controlRequest removeObjectForKey:@"query_deadline_ns"];
        NSDictionary *reply = [transport exchangeReceiptControl:controlRequest
            deadlineNanoseconds:queryDeadline error:error];
        if (reply == nil || !AQBrokerWriteReceiptJSONLineToFD(STDOUT_FILENO, reply,
            queryDeadline,
            ^uint64_t { return AQBrokerSystemClockNanoseconds(); }, error)) return NO;
        if (responsePrinted != NULL) *responsePrinted = YES;
        return YES;
    }
    NSDictionary *approvedManifest = nil;
    NSString *manifestSHA256 = nil;
    NSString *authorizationSHA256 = nil;
    NSString *receiptDirectory = receiverReceiptDirectory ?: @"";
    NSMutableDictionary *serviceRequest = [request mutableCopy];
    id encodedDocuments = serviceRequest[@"documents_b64"];
    NSDictionary *documents = nil;
    if (encodedDocuments != nil) {
        if (![operation isEqual:@"admit"] ||
            (documents = AQBrokerDecodeDocuments(encodedDocuments, error)) == nil) return NO;
        [serviceRequest removeObjectForKey:@"documents_b64"];
    } else if ([operation isEqual:@"admit"]) {
        if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                                        @"ADMISSION_DOCUMENTS_REQUIRED");
        return NO;
    }
    if (![operation isEqual:@"admit"] && documents != nil) return NO;
    if ([operation isEqual:@"export"]) {
        approvedManifest = serviceRequest[@"export_manifest"];
        manifestSHA256 = request[@"manifest_sha256"];
        authorizationSHA256 = request[@"authorization_sha256"];
        NSString *computedManifestSHA256 = [approvedManifest isKindOfClass:NSDictionary.class]
            ? AQDigest(@"", approvedManifest, NULL) : nil;
        if (![approvedManifest isKindOfClass:NSDictionary.class] ||
            ![manifestSHA256 isKindOfClass:NSString.class] ||
            ![authorizationSHA256 isKindOfClass:NSString.class] ||
            ![computedManifestSHA256 isEqual:manifestSHA256] ||
            ![receiverReceiptDirectory isKindOfClass:NSString.class] ||
            receiptDirectory.length == 0) {
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerBindingMismatch,
                                            @"EXPORT_BINDING_INVALID");
            }
            return NO;
        }
        struct stat deliveryInfo = {0};
        if (deliveryFD < 0 || fstat(deliveryFD, &deliveryInfo) != 0 ||
            !S_ISREG(deliveryInfo.st_mode) || deliveryInfo.st_uid != getuid() ||
            deliveryInfo.st_nlink != 1 || (deliveryInfo.st_mode & 0777) != 0600 ||
            deliveryInfo.st_size != 0 || lseek(deliveryFD, 0, SEEK_CUR) != 0) {
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                            @"PRIVATE_DELIVERY_DESCRIPTOR_INVALID");
            }
            return NO;
        }
    }
    [serviceRequest removeObjectForKey:@"export_manifest"];
    NSData *serviceRequestData = AQCanonicalJSON(serviceRequest, error);
    if (serviceRequestData == nil) return NO;

    /* The inherited descriptors and JSON source paths form one binding. Check
     * the collection type and bound before inspecting either collection. */
    id encodedSourcePaths = serviceRequest[@"source_paths"];
    NSArray *sourcePaths = encodedSourcePaths == nil ? @[] : encodedSourcePaths;
    BOOL validSourcePaths = [sourcePaths isKindOfClass:NSArray.class] &&
        sourcePaths.count <= AQServiceMaximumSourceDescriptors;
    for (id path in validSourcePaths ? sourcePaths : @[]) {
        if (![path isKindOfClass:NSString.class]) {
            validSourcePaths = NO;
            break;
        }
    }
    NSArray<NSNumber *> *requestSourceFDs = [operation isEqual:@"stage"] ? sourceFDs : @[];
    if (!validSourcePaths || requestSourceFDs.count != sourcePaths.count) {
        if (error != NULL) {
            *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                        @"SOURCE_BINDING_INVALID");
        }
        return NO;
    }

    uint64_t token = 0;
    int exportFD = -1;
    NSDictionary *response = [transport exchangeRequest:request
                                     serviceRequestData:serviceRequestData
                                             sourceFDs:requestSourceFDs
                                             documents:documents
                                     authorizationData:authorizationData
                                               session:session
                                                 token:&token
                                            exportFDOut:&exportFD
                                          outcomeKnown:NULL
                                                 error:error];
    if (response == nil) return NO;

    if (![operation isEqual:@"export"]) {
        if (exportFD >= 0) {
            close(exportFD);
            (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
            [transport invalidate];
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerBindingMismatch,
                                            @"EXPORT_BINDING_INVALID");
            }
            return NO;
        }
        NSError *deliveryError = nil;
        uint64_t deadline = 0;
        if (![session deadlineNanosecondsForToken:token deadline:&deadline error:&deliveryError] ||
            !AQBrokerWriteJSONLineToFD(STDOUT_FILENO, response, deadline,
                                       ^uint64_t { return AQBrokerSystemClockNanoseconds(); },
                                       &deliveryError)) {
            if (error != NULL) *error = deliveryError;
            if (fatalOutputFailure != NULL) *fatalOutputFailure = YES;
            (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
            [transport invalidate];
            return NO;
        }
        if (responsePrinted != NULL) *responsePrinted = YES;
        if (![session completeRequestForToken:token outcomeKnown:YES error:error]) {
            if (fatalOutputFailure != NULL) *fatalOutputFailure = YES;
            [transport invalidate];
            return NO;
        }
        if (session.requiresFreshAuthentication) [transport invalidate];
        return YES;
    }

    id sessionID = request[@"session_id"];
    id requestID = request[@"request_id"];
    id generation = request[@"expected_generation"];
    NSDictionary *exportResult = response[@"result"];
    if (![sessionID isKindOfClass:NSString.class] ||
        ![requestID isKindOfClass:NSString.class] ||
        ![generation isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)generation) == CFBooleanGetTypeID() ||
        [generation longLongValue] < 0 ||
        ![response[@"status"] isEqual:@"OK"] ||
        ![exportResult isKindOfClass:NSDictionary.class] ||
        ![exportResult[@"export_transport"] isEqual:@"anonymous_pipe_read_only"] ||
        ![exportResult[@"receiver_verification"] isEqual:@"required"] ||
        ![exportResult[@"delivery"] isEqual:@"not_yet_confirmed"] ||
        exportFD < 0) {
        if (exportFD >= 0) close(exportFD);
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        if (error != NULL) {
            *error = AQBrokerRelayError(AQBrokerBindingMismatch,
                                        @"EXPORT_BINDING_INVALID");
        }
        return NO;
    }

    __block NSError *writeError = nil;
    __block BOOL outputStarted = NO;
    __block uint64_t deliveredBytes = 0;
    __block BOOL deliverySynced = NO;
    uint64_t expectedDeliveryBytes = 0;
    NSArray *approvedMembers = approvedManifest[@"members"];
    if (![approvedMembers isKindOfClass:NSArray.class]) {
        close(exportFD);
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        if (error != NULL) *error = AQBrokerRelayError(AQBrokerBindingMismatch,
                                                       @"EXPORT_BINDING_INVALID");
        return NO;
    }
    for (NSDictionary *member in approvedMembers) {
        NSNumber *size = [member isKindOfClass:NSDictionary.class] ? member[@"size"] : nil;
        if (![size isKindOfClass:NSNumber.class] || size.longLongValue < 0 ||
            UINT64_MAX - expectedDeliveryBytes < size.unsignedLongLongValue) {
            close(exportFD);
            (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
            [transport invalidate];
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerBindingMismatch,
                                                           @"EXPORT_BINDING_INVALID");
            return NO;
        }
        expectedDeliveryBytes += size.unsignedLongLongValue;
    }
    if (expectedDeliveryBytes == 0) {
        if (fsync(deliveryFD) != 0) {
            close(exportFD);
            (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
            [transport invalidate];
            if (error != NULL) *error = AQBrokerRelayError(AQBrokerInvalidFrame,
                                                           @"PRIVATE_DELIVERY_SYNC_FAILED");
            return NO;
        }
        deliverySynced = YES;
    }
    uint64_t exportDeadline = 0;
    if (![session deadlineNanosecondsForToken:token deadline:&exportDeadline error:error]) {
        close(exportFD);
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        return NO;
    }
    AQBrokerExportVerifier *verifier = [[AQBrokerExportVerifier alloc]
        initWithSink:^BOOL(NSString *path, NSData *bytes, uint64_t offset) {
            (void)path;
            (void)offset;
            outputStarted = YES;
            if (!AQBrokerWriteAllUntilDeadline(
                    deliveryFD, bytes, exportDeadline,
                    ^uint64_t { return AQBrokerSystemClockNanoseconds(); }, &writeError)) {
                return NO;
            }
            deliveredBytes += bytes.length;
            if (deliveredBytes > expectedDeliveryBytes) return NO;
            if (deliveredBytes == expectedDeliveryBytes) {
                if (fsync(deliveryFD) != 0) {
                    writeError = AQBrokerRelayError(AQBrokerInvalidFrame,
                                                    @"PRIVATE_DELIVERY_SYNC_FAILED");
                    return NO;
                }
                deliverySynced = YES;
            }
            return YES;
        }
        expectedSessionID:sessionID
        expectedGeneration:(uint64_t)[generation unsignedLongLongValue]
        expectedManifestSHA256:manifestSHA256
        authorizationSHA256:authorizationSHA256
        approvedManifest:approvedManifest
        requestID:requestID
        deadlineNanoseconds:exportDeadline
        clock:^uint64_t { return AQBrokerSystemClockNanoseconds(); }
        receiptDirectory:receiptDirectory
        error:error];
    if (verifier == nil) {
        close(exportFD);
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        return NO;
    }

    uint8_t chunk[1024 * 1024];
    BOOL failed = NO;
    for (;;) {
        NSError *deadlineError = nil;
        int timeout = [session pollTimeoutMillisecondsForToken:token error:&deadlineError];
        if (timeout < 0) {
            if (error != NULL) *error = deadlineError;
            failed = YES;
            break;
        }
        struct pollfd pollFD = {.fd = exportFD, .events = POLLIN | POLLHUP};
        int ready = poll(&pollFD, 1, timeout);
        if (ready < 0 && errno == EINTR) continue;
        if (ready == 0) continue;
        if (ready < 0 || (pollFD.revents & (POLLERR | POLLNVAL)) != 0) {
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerInvalidFrame,
                                            @"EXPORT_READ_FAILED");
            }
            failed = YES;
            break;
        }
        ssize_t count = read(exportFD, chunk, sizeof(chunk));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (count == 0) break;
        if (count < 0 || ![verifier consumeData:[NSData dataWithBytes:chunk
                                                               length:(NSUInteger)count]
                                          error:error]) {
            failed = YES;
            break;
        }
    }
    close(exportFD);
    if (failed) {
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        return NO;
    }

    if (![verifier finishWithError:error] || writeError != nil || !deliverySynced ||
        deliveredBytes != expectedDeliveryBytes ||
        verifier.transportCompletion == nil || verifier.completion == nil) {
        if (error != NULL && *error == nil) *error = writeError;
        if (fatalOutputFailure != NULL) *fatalOutputFailure = outputStarted;
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        return NO;
    }

    /* The receiver has now completed full-frame verification and synced its
     * protected receipt. Submit that exact completion over the already
     * authenticated service XPC connection before reporting a known outcome. */
    NSString *freshnessBase64 = request[@"freshness_envelope"];
    NSData *freshnessData = [freshnessBase64 isKindOfClass:NSString.class]
        ? [[NSData alloc] initWithBase64EncodedString:freshnessBase64 options:0] : nil;
    NSDictionary *freshness = freshnessData == nil ? nil : AQParseJSON(freshnessData, NULL);
    NSMutableDictionary *serviceCompletion = [verifier.completion mutableCopy];
    if ([freshness isKindOfClass:NSDictionary.class]) {
        serviceCompletion[@"service_boot_id"] = freshness[@"service_boot_id"] ?: @"";
        serviceCompletion[@"sequence"] = freshness[@"sequence"] ?: @0;
    }
    NSDictionary *receiptBinding = @{
        @"request_id": serviceCompletion[@"request_id"] ?: @"",
        @"session_id": serviceCompletion[@"session_id"] ?: @"",
        @"service_boot_id": serviceCompletion[@"service_boot_id"] ?: @"",
        @"sequence": serviceCompletion[@"sequence"] ?: @0,
        @"deadline_ns": serviceCompletion[@"deadline_ns"] ?: @0,
        @"manifest_sha256": serviceCompletion[@"manifest_sha256"] ?: @"",
        @"generation": serviceCompletion[@"generation"] ?: @0,
        @"members": serviceCompletion[@"members"] ?: @[]
    };
    NSDictionary *receiptReply = [transport exchangeReceiptControl:@{
        @"operation": @"receipt_record",
        @"request_id": serviceCompletion[@"request_id"] ?: @"",
        @"binding": receiptBinding,
        @"completion": serviceCompletion
    } deadlineNanoseconds:exportDeadline error:error];
    if (receiptReply == nil ||
        ![receiptReply[@"completion"] isEqual:serviceCompletion]) {
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        if (error != NULL && *error == nil) {
            *error = AQBrokerRelayError(AQBrokerDurableReceiptFailed,
                                        @"SERVICE_RECEIPT_NOT_DURABLE");
        }
        return NO;
    }

    AQBrokerMonotonicClock clock = ^uint64_t { return AQBrokerSystemClockNanoseconds(); };
    NSError *receiptOutputError = nil;
    BOOL receiptOutput = AQBrokerWriteJSONLineToFD(fileno(stderr), response, exportDeadline,
                                                   clock, &receiptOutputError) &&
        AQBrokerWriteJSONLineToFD(fileno(stderr), verifier.transportCompletion, exportDeadline,
                                  clock, &receiptOutputError) &&
        AQBrokerWriteReceiptJSONLineToFD(fileno(stderr), serviceCompletion, exportDeadline,
                                  clock, &receiptOutputError);
    if (!receiptOutput) {
        if (error != NULL) *error = receiptOutputError;
        if (fatalOutputFailure != NULL) *fatalOutputFailure = YES;
        (void)[session completeRequestForToken:token outcomeKnown:NO error:NULL];
        [transport invalidate];
        return NO;
    }
    if (responsePrinted != NULL) *responsePrinted = YES;
    if (![session completeRequestForToken:token outcomeKnown:YES error:error]) {
        if (fatalOutputFailure != NULL) *fatalOutputFailure = YES;
        [transport invalidate];
        return NO;
    }
    if (session.requiresFreshAuthentication) [transport invalidate];
    return YES;
}

static BOOL AQBrokerReadSessionLine(NSMutableData *buffer,
                                    NSData **line,
                                    BOOL *reachedEOF,
                                    NSError **error) {
    *line = nil;
    if (reachedEOF != NULL) *reachedEOF = NO;
    for (;;) {
        const char newline = '\n';
        NSRange newlineRange = [buffer rangeOfData:[NSData dataWithBytes:&newline length:1]
                                           options:0
                                             range:NSMakeRange(0, buffer.length)];
        if (newlineRange.location != NSNotFound) {
            /* The limit includes the newline, so the JSON payload is at most max - 1. */
            if (newlineRange.location >= AQBrokerMaximumSessionLineBytes) {
                if (error != NULL) {
                    *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                                @"INVALID_BROKER_REQUEST");
                }
                return NO;
            }
            *line = [buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(newlineRange))
                              withBytes:NULL length:0];
            return YES;
        }
        if (buffer.length >= AQBrokerMaximumSessionLineBytes) {
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                            @"INVALID_BROKER_REQUEST");
            }
            return NO;
        }
        uint8_t chunk[4096];
        NSUInteger remaining = AQBrokerMaximumSessionLineBytes - buffer.length;
        size_t readLength = MIN(sizeof(chunk), (size_t)remaining);
        ssize_t count = read(STDIN_FILENO, chunk, readLength);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) {
            if (error != NULL) {
                *error = AQBrokerRelayError(AQBrokerInvalidRequest,
                                            @"INVALID_BROKER_REQUEST");
            }
            return NO;
        }
        if (count == 0) {
            if (reachedEOF != NULL) *reachedEOF = YES;
            if (buffer.length == 0) return NO;
            *line = [buffer copy];
            [buffer setLength:0];
            return YES;
        }
        [buffer appendBytes:chunk length:(NSUInteger)count];
    }
}

#if defined(AQ_BROKER_TESTING)
static BOOL AQBrokerTestUseSyntheticOwnerSignature;
static NSUInteger AQBrokerTestOwnerSignatureRequestCount;
#endif

static NSData *AQBrokerSignOwnerEnvelope(AQInstallationPolicy *policy,
                                             NSData *canonicalEnvelope,
                                             NSError **error) {
    if (policy == nil || canonicalEnvelope.length == 0) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return nil;
    }
#if defined(AQ_BROKER_TESTING)
    if (AQBrokerTestUseSyntheticOwnerSignature) {
        AQBrokerTestOwnerSignatureRequestCount++;
        return [@"synthetic-owner-signature" dataUsingEncoding:NSUTF8StringEncoding];
    }
#endif
    __block BOOL completed = NO;
    __block NSData *signature = nil;
    __block NSError *signingError = nil;
    AQRequestOwnerSignature(policy, canonicalEnvelope, ^(NSData *result, NSError *signError) {
        signature = [result copy];
        signingError = signError;
        completed = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:300];
    while (!completed && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    if (!completed || signature.length == 0) {
        if (error != NULL) *error = signingError ?: AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return nil;
    }
    return signature;
}

static BOOL AQBrokerExactKeys(NSDictionary *dictionary, NSArray<NSString *> *keys) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return NO;
    for (id key in dictionary.allKeys) {
        if (![key isKindOfClass:NSString.class]) return NO;
    }
    return [[NSSet setWithArray:dictionary.allKeys] isEqualToSet:[NSSet setWithArray:keys]];
}

static BOOL AQBrokerOwnerUnsignedInteger(id value, uint64_t minimum, uint64_t maximum,
                                         uint64_t *result) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) != CFNumberGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    long long integer = [value longLongValue];
    if (integer < 0 || (uint64_t)integer < minimum || (uint64_t)integer > maximum) return NO;
    if (result != NULL) *result = (uint64_t)integer;
    return YES;
}

static BOOL AQBrokerValidateOwnerConsentEnvelope(NSDictionary *consent,
                                                NSDictionary *helloRequest,
                                                NSString *connectionID,
                                                NSString *sessionID,
                                                NSString *authorizationSHA256,
                                                NSArray *templates,
                                                NSError **error) {
    NSArray<NSString *> *consentKeys = @[
        @"schema_version", @"owner_key_id", @"broker_revision", @"installation_id",
        @"service_boot_id", @"session_id", @"connection_id", @"challenge", @"nonce",
        @"grant_id", @"authorization_sha256", @"approval_sha256", @"manifest_sha256",
        @"plan_sha256", @"rules_sha256", @"operations", @"deadline_ns",
        @"store_deadline_ticks", @"host_reserve_bytes", @"destination_reserve_bytes",
        @"cleanup_authorized"
    ];
    NSArray<NSString *> *digestKeys = @[
        @"authorization_sha256", @"approval_sha256", @"manifest_sha256",
        @"plan_sha256", @"rules_sha256"
    ];
    NSDictionary *expectedBindings = @{
        @"owner_key_id": helloRequest[@"owner_key_id"] ?: NSNull.null,
        @"broker_revision": helloRequest[@"broker_revision"] ?: NSNull.null,
        @"installation_id": helloRequest[@"installation_id"] ?: NSNull.null,
        @"service_boot_id": helloRequest[@"service_boot_id"] ?: NSNull.null,
        @"nonce": helloRequest[@"nonce"] ?: NSNull.null,
        @"grant_id": helloRequest[@"grant_id"] ?: NSNull.null,
        @"authorization_sha256": authorizationSHA256 ?: NSNull.null,
        @"approval_sha256": helloRequest[@"approval_sha256"] ?: NSNull.null,
        @"manifest_sha256": helloRequest[@"manifest_sha256"] ?: NSNull.null,
        @"plan_sha256": helloRequest[@"plan_sha256"] ?: NSNull.null,
        @"rules_sha256": helloRequest[@"rules_sha256"] ?: NSNull.null,
        @"operations": helloRequest[@"operations"] ?: NSNull.null,
        @"deadline_ns": helloRequest[@"deadline_ns"] ?: NSNull.null,
        @"store_deadline_ticks": helloRequest[@"store_deadline_ticks"] ?: NSNull.null,
        @"host_reserve_bytes": helloRequest[@"host_reserve_bytes"] ?: NSNull.null,
        @"destination_reserve_bytes": helloRequest[@"destination_reserve_bytes"] ?: NSNull.null,
        @"cleanup_authorized": helloRequest[@"cleanup_authorized"] ?: NSNull.null
    };
    BOOL valid = AQBrokerExactKeys(consent, consentKeys) &&
        AQBrokerOwnerUnsignedInteger(consent[@"schema_version"], 1, 1, NULL) &&
        AQBrokerOwnerToken(consent[@"session_id"]) &&
        [consent[@"session_id"] isEqual:sessionID] &&
        AQBrokerOwnerToken(consent[@"connection_id"]) &&
        [consent[@"connection_id"] isEqual:connectionID] &&
        AQBrokerOwnerToken(consent[@"challenge"]) &&
        AQBrokerOwnerUnsignedInteger(consent[@"deadline_ns"], 1, INT64_MAX, NULL) &&
        AQBrokerOwnerUnsignedInteger(consent[@"store_deadline_ticks"], 1, INT64_MAX, NULL) &&
        AQBrokerOwnerUnsignedInteger(consent[@"host_reserve_bytes"], 0, INT64_MAX, NULL) &&
        AQBrokerOwnerUnsignedInteger(consent[@"destination_reserve_bytes"], 0, INT64_MAX, NULL) &&
        [consent[@"cleanup_authorized"] isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)consent[@"cleanup_authorized"]) == CFBooleanGetTypeID();
    for (NSString *key in digestKeys) valid = valid && AQBrokerOwnerDigest(consent[key]);
    for (NSString *key in expectedBindings) {
        id expected = expectedBindings[key];
        valid = valid && expected != NSNull.null && [consent[key] isEqual:expected];
    }

    NSArray *operations = consent[@"operations"];
    NSSet *allowedOperations = [NSSet setWithArray:@[@"stage", @"eligibility", @"export", @"cleanup"]];
    NSMutableSet *seenOperations = [NSMutableSet set];
    if (![operations isKindOfClass:NSArray.class] || operations.count == 0) {
        valid = NO;
    } else {
        for (id operation in operations) {
            if (!AQBrokerOwnerToken(operation) || ![allowedOperations containsObject:operation] ||
                [seenOperations containsObject:operation]) valid = NO;
            else [seenOperations addObject:operation];
        }
    }

    NSMutableSet<NSString *> *requestIDs = [NSMutableSet set];
    NSMutableSet<NSString *> *nonces = [NSMutableSet set];
    uint64_t previousSequence = 0;
    for (NSUInteger index = 0; index < templates.count; ++index) {
        NSDictionary *template = templates[index];
        NSDictionary *claims = template[@"freshness_claims"];
        NSString *operation = template[@"operation"];
        NSString *requestID = (NSString *)template[@"request_id"];
        NSString *nonce = (NSString *)template[@"nonce"];
        uint64_t sequence = 0, deadline = 0;
        BOOL templateValid = [template isKindOfClass:NSDictionary.class] &&
            AQBrokerOwnerToken(operation) && AQBrokerOwnerToken(template[@"request_id"]) &&
            AQBrokerOwnerToken(template[@"nonce"]) &&
            AQBrokerOwnerUnsignedInteger(template[@"sequence"], 1, INT64_MAX, &sequence) &&
            AQBrokerOwnerUnsignedInteger(template[@"deadline_ns"], 1, INT64_MAX, &deadline) &&
            AQBrokerOwnerDigest(template[@"manifest_sha256"]) &&
            [template[@"manifest_sha256"] isEqual:consent[@"manifest_sha256"]] &&
            AQBrokerExactKeys(claims, @[@"request_sha256"]) &&
            AQBrokerOwnerDigest(claims[@"request_sha256"]) &&
            deadline == [consent[@"deadline_ns"] unsignedLongLongValue] &&
            sequence == previousSequence + 1 &&
            ![requestIDs containsObject:requestID] &&
            ![nonces containsObject:nonce];
        if (![operation isEqual:@"admit"] && ![seenOperations containsObject:operation]) {
            templateValid = NO;
        }
        if (templateValid) {
            [requestIDs addObject:requestID];
            [nonces addObject:nonce];
            previousSequence = sequence;
        } else {
            valid = NO;
        }
    }

    if (!valid) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return NO;
    }
    return YES;
}

static BOOL AQBrokerValidateOwnerWorkflowTemplates(NSArray *templates,
                                                    NSError **error) {
    NSArray<NSString *> *expectedOperations = @[@"admit", @"stage", @"export"];
    if (![templates isKindOfClass:NSArray.class] ||
        templates.count != expectedOperations.count) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return NO;
    }
    for (NSUInteger index = 0; index < expectedOperations.count; index++) {
        NSDictionary *template = templates[index];
        if (![template isKindOfClass:NSDictionary.class]) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return NO;
        }
        NSDictionary *claims = template[@"freshness_claims"];
        if (![claims isKindOfClass:NSDictionary.class] ||
            !AQBrokerExactKeys(claims, @[@"request_sha256"]) ||
            ![template[@"operation"] isEqual:expectedOperations[index]] ||
            template[@"freshness_envelope"] != nil ||
            template[@"freshness_signature"] != nil ||
            template[@"consent_signature"] != nil) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return NO;
        }
        for (NSString *key in @[@"request_id", @"sequence", @"deadline_ns", @"nonce"]) {
            if (template[key] == nil) {
                if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
                return NO;
            }
        }
        if (!AQBrokerOwnerToken(template[@"request_id"]) ||
            !AQBrokerOwnerDigest(claims[@"request_sha256"])) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return NO;
        }
        if ([expectedOperations[index] isEqual:@"admit"] &&
            ![template[@"documents_b64"] isKindOfClass:NSDictionary.class]) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return NO;
        }
        if ([expectedOperations[index] isEqual:@"export"]) {
            for (NSString *key in @[@"manifest_sha256", @"generation", @"members"]) {
                if (template[key] == nil) {
                    if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
                    return NO;
                }
            }
            if (!AQBrokerOwnerDigest(template[@"manifest_sha256"])) {
                if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
                return NO;
            }
        }
    }
    return YES;
}

static BOOL AQBrokerOwnerStringArray(id value, BOOL nonempty,
                                     NSArray<NSString *> **result) {
    if (![value isKindOfClass:NSArray.class] ||
        [value count] > AQServiceMaximumDocuments || (nonempty && [value count] == 0)) {
        return NO;
    }
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:NSString.class] || [item length] == 0 ||
            [seen containsObject:item]) return NO;
        [seen addObject:item];
    }
    if (result != NULL) *result = [value copy];
    return YES;
}

static BOOL AQBrokerValidateOwnerAdmission(NSData *authorizationData,
                                          NSDictionary *helloRequest,
                                          NSArray *templates,
                                          NSError **error) {
    NSString *authorizationSHA256 = AQBrokerExactBytesSHA256(authorizationData);
    NSError *parseError = nil;
    id authorizationValue = AQParseJSON(authorizationData, &parseError);
    NSData *canonicalAuthorization = [authorizationValue isKindOfClass:NSDictionary.class]
        ? AQCanonicalJSON(authorizationValue, NULL) : nil;
    NSDictionary *authorization = [authorizationValue isKindOfClass:NSDictionary.class]
        ? authorizationValue : nil;
    NSDictionary *authorizationPlan = authorization[@"plan"];
    NSString *manifestPin = helloRequest[@"manifest_sha256"];
    NSString *planPin = helloRequest[@"plan_sha256"];
    NSString *rulesPin = helloRequest[@"rules_sha256"];
    if (canonicalAuthorization == nil ||
        ![canonicalAuthorization isEqualToData:authorizationData] ||
        ![authorizationSHA256 isEqual:helloRequest[@"authorization_sha256"]] ||
        !AQBrokerOwnerDigest(manifestPin) || !AQBrokerOwnerDigest(planPin) ||
        !AQBrokerOwnerDigest(rulesPin) ||
        ![authorizationPlan isKindOfClass:NSDictionary.class] ||
        ![authorization[@"fixture_manifest_sha256"] isEqual:manifestPin] ||
        ![authorizationPlan[@"plan_sha256"] isEqual:planPin] ||
        ![authorizationPlan[@"rules_sha256"] isEqual:rulesPin]) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerBindingMismatch);
        return NO;
    }

    NSDictionary *admitTemplate = templates.firstObject;
    NSDictionary *encoded = admitTemplate[@"documents_b64"];
    NSDictionary *documents = AQBrokerDecodeDocuments(encoded, error);
    NSData *manifestData = documents[@"manifest"];
    NSData *planData = documents[@"plan"];
    NSArray *oracles = documents[@"oracles"];
    NSArray *evidence = documents[@"evidence"];
    if (documents == nil || ![manifestData isKindOfClass:NSData.class] ||
        ![planData isKindOfClass:NSData.class] ||
        ![oracles isKindOfClass:NSArray.class] ||
        ![evidence isKindOfClass:NSArray.class] ||
        oracles.count > AQServiceMaximumDocuments ||
        evidence.count > AQServiceMaximumDocuments) {
        if (error != NULL && *error == nil) {
            *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        }
        return NO;
    }
    for (id document in [oracles arrayByAddingObjectsFromArray:evidence]) {
        if (![document isKindOfClass:NSData.class]) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return NO;
        }
    }

    id planValue = AQParseJSON(planData, &parseError);
    NSData *canonicalPlan = [planValue isKindOfClass:NSDictionary.class]
        ? AQCanonicalJSON(planValue, NULL) : nil;
    NSDictionary *plan = [planValue isKindOfClass:NSDictionary.class] ? planValue : nil;
    NSDictionary *rules = plan[@"rules"];
    NSData *canonicalRules = [rules isKindOfClass:NSDictionary.class]
        ? AQCanonicalJSON(rules, NULL) : nil;
    if (canonicalPlan == nil || ![canonicalPlan isEqualToData:planData] ||
        ![AQBrokerExactBytesSHA256(planData) isEqual:planPin] ||
        canonicalRules == nil || ![AQBrokerExactBytesSHA256(canonicalRules) isEqual:rulesPin]) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerBindingMismatch);
        return NO;
    }

    uint64_t schemaVersion = 0, planReserve = 0, helloReserve = 0;
    NSDictionary *coverage = plan[@"fixture_coverage"];
    if (!AQBrokerOwnerUnsignedInteger(plan[@"schema_version"], 1, 1, &schemaVersion) ||
        !AQBrokerOwnerUnsignedInteger(plan[@"host_reserve_bytes"], 0, INT64_MAX,
                                      &planReserve) ||
        !AQBrokerOwnerUnsignedInteger(helloRequest[@"host_reserve_bytes"], 0, INT64_MAX,
                                      &helloReserve) || planReserve != helloReserve ||
        !AQBrokerExactKeys(coverage, @[
            @"mode", @"required_fixture_ids", @"selected_fixture_ids",
            @"mandatory_fixture_ids"
        ]) || ![coverage[@"mode"] isKindOfClass:NSString.class]) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return NO;
    }
    NSArray<NSString *> *required = nil, *selected = nil, *mandatory = nil;
    if (!AQBrokerOwnerStringArray(coverage[@"required_fixture_ids"], NO, &required) ||
        !AQBrokerOwnerStringArray(coverage[@"selected_fixture_ids"], NO, &selected) ||
        !AQBrokerOwnerStringArray(coverage[@"mandatory_fixture_ids"], YES, &mandatory)) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return NO;
    }

    NSError *contractError = nil;
    NSDictionary *contract = AQValidateSnapshotContract(manifestData, oracles, evidence,
        manifestPin, planPin, rulesPin, &contractError);
    id manifestValue = AQParseJSON(manifestData, &parseError);
    NSDictionary *manifest = [manifestValue isKindOfClass:NSDictionary.class]
        ? manifestValue : nil;
    NSArray *manifestIDs = manifest[@"selected_fixture_ids"];
    NSMutableArray<NSString *> *contractIDs = [NSMutableArray array];
    for (NSDictionary *assessment in contract[@"fixtures"]) {
        if (![assessment isKindOfClass:NSDictionary.class]) {
            contract = nil;
            break;
        }
        id fixtureID = assessment[@"fixture_id"];
        if (![fixtureID isKindOfClass:NSString.class]) {
            contract = nil;
            break;
        }
        [contractIDs addObject:(NSString *)fixtureID];
    }
    NSSet *requiredSet = [NSSet setWithArray:required];
    NSSet *selectedSet = [NSSet setWithArray:selected];
    NSSet *mandatorySet = [NSSet setWithArray:mandatory];
    NSString *mode = coverage[@"mode"];
    BOOL coverageValid = contract != nil && [manifest isKindOfClass:NSDictionary.class] &&
        [manifest[@"coverage_mode"] isEqual:mode] &&
        [manifestIDs isEqualToArray:selected] && [contractIDs isEqualToArray:selected] &&
        [selectedSet isSubsetOfSet:requiredSet] &&
        [mandatorySet isSubsetOfSet:selectedSet];
    if ([mode isEqual:@"mandatory_full_plan"]) {
        coverageValid = coverageValid && [selectedSet isEqualToSet:requiredSet] &&
            [mandatorySet isEqualToSet:requiredSet];
    } else if ([mode isEqual:@"authorized_partial_plan"]) {
        coverageValid = coverageValid && selectedSet.count < requiredSet.count;
    } else {
        coverageValid = NO;
    }
    if (!coverageValid) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return NO;
    }
    return YES;
}

static NSDictionary *AQBrokerPrepareOwnerExport(NSDictionary *request,
                                                 NSDictionary *helloRequest,
                                                 AQInstallationPolicy *policy,
                                                 AQBrokerSequentialSession *session,
                                                 NSData *authorizationData,
                                                 NSError **error) {
    NSDictionary *consentEnvelope = request[@"consent_envelope"];
    NSArray *templates = request[@"workflow_templates"];
    NSString *connectionID = session.connectionID;
    NSString *sessionID = session.sessionID;
    NSString *installationID = helloRequest[@"installation_id"];
    NSString *serviceBootID = helloRequest[@"service_boot_id"];
    NSString *brokerRevision = helloRequest[@"broker_revision"];
    NSString *ownerKeyID = helloRequest[@"owner_key_id"];
    if (authorizationData.length == 0) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerBindingMismatch);
        return nil;
    }
    NSString *authorizationSHA256 = AQBrokerExactBytesSHA256(authorizationData);
    if (![consentEnvelope isKindOfClass:NSDictionary.class] ||
        ![templates isKindOfClass:NSArray.class] || templates.count != 3 ||
        authorizationData.length == 0 ||
        !AQBrokerOwnerToken(connectionID) || !AQBrokerOwnerToken(sessionID) ||
        !AQBrokerOwnerToken(installationID) || !AQBrokerOwnerToken(serviceBootID) ||
        !AQBrokerOwnerToken(brokerRevision) || !AQBrokerOwnerToken(ownerKeyID) ||
        !AQBrokerOwnerDigest(authorizationSHA256)) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerBindingMismatch);
        return nil;
    }
    if (!AQBrokerValidateOwnerWorkflowTemplates(templates, error)) return nil;
    if (!AQBrokerValidateOwnerAdmission(authorizationData, helloRequest, templates, error)) {
        return nil;
    }
    if (!AQBrokerValidateOwnerConsentEnvelope(consentEnvelope, helloRequest,
            connectionID, sessionID, authorizationSHA256, templates, error)) return nil;

    NSData *consentBytes = AQCanonicalJSON(consentEnvelope, error);
    if (consentBytes == nil) return nil;
    NSData *consentSignature = AQBrokerSignOwnerEnvelope(policy, consentBytes, error);
    if (consentSignature == nil) return nil;
    NSString *consentSHA256 = AQBrokerExactBytesSHA256(consentBytes);
    NSString *encodedConsent = [consentBytes base64EncodedStringWithOptions:0];
    NSString *encodedConsentSignature = [consentSignature base64EncodedStringWithOptions:0];

    NSDictionary *identity = @{
        @"installation_id": installationID,
        @"service_boot_id": serviceBootID,
        @"broker_revision": brokerRevision,
        @"owner_key_id": ownerKeyID,
        @"connection_id": connectionID,
        @"session_id": sessionID,
        @"authorization_sha256": authorizationSHA256,
        @"consent_sha256": consentSHA256,
    };
    NSMutableArray<NSDictionary *> *workflow = [NSMutableArray arrayWithObject:helloRequest];
    NSArray<NSString *> *expectedOperations = @[@"admit", @"stage", @"export"];
    for (NSUInteger index = 0; index < expectedOperations.count; index++) {
        NSDictionary *template = templates[index];
        NSDictionary *claims = template[@"freshness_claims"];
        if (![template isKindOfClass:NSDictionary.class] ||
            ![claims isKindOfClass:NSDictionary.class] ||
            ![template[@"operation"] isEqual:expectedOperations[index]] ||
            template[@"freshness_envelope"] != nil ||
            template[@"freshness_signature"] != nil ||
            template[@"consent_signature"] != nil) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return nil;
        }
        NSMutableDictionary *signedRequest = [template mutableCopy];
        [signedRequest removeObjectForKey:@"freshness_claims"];
        [signedRequest addEntriesFromDictionary:identity];
        signedRequest[@"consent_signature"] = encodedConsentSignature;

        NSMutableDictionary *freshness = [claims mutableCopy];
        [freshness addEntriesFromDictionary:identity];
        for (NSString *key in @[@"request_id", @"operation", @"sequence", @"deadline_ns", @"nonce"]) {
            id value = signedRequest[key];
            if (value == nil) {
                if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
                return nil;
            }
            freshness[key] = value;
        }
        if (!AQBrokerOwnerToken(freshness[@"request_id"]) ||
            !AQBrokerOwnerDigest(freshness[@"request_sha256"]) ||
            !AQBrokerOwnerDigest(freshness[@"authorization_sha256"]) ||
            !AQBrokerOwnerDigest(freshness[@"consent_sha256"])) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return nil;
        }
        NSData *freshnessBytes = AQCanonicalJSON(freshness, error);
        if (freshnessBytes == nil) return nil;
        NSData *freshnessSignature = AQBrokerSignOwnerEnvelope(policy, freshnessBytes, error);
        if (freshnessSignature == nil) return nil;
        signedRequest[@"freshness_envelope"] =
            [freshnessBytes base64EncodedStringWithOptions:0];
        signedRequest[@"freshness_signature"] =
            [freshnessSignature base64EncodedStringWithOptions:0];

        if ([expectedOperations[index] isEqual:@"admit"]) {
            id encodedDocuments = signedRequest[@"documents_b64"];
            if (![encodedDocuments isKindOfClass:NSDictionary.class]) {
                if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
                return nil;
            }
            NSMutableDictionary *documents = [encodedDocuments mutableCopy];
            documents[@"consent"] = encodedConsent;
            documents[@"signature"] = encodedConsentSignature;
            signedRequest[@"documents_b64"] = documents;
        }
        [workflow addObject:signedRequest];
    }

    NSDictionary *signedExport = workflow.lastObject;
    NSData *signedExportBytes = AQCanonicalJSON(signedExport, error);
    if (signedExportBytes == nil) return nil;
    NSString *requestSHA256 = AQBrokerExactBytesSHA256(signedExportBytes);
    NSMutableDictionary *attempt = [NSMutableDictionary dictionaryWithDictionary:identity];
    for (NSString *key in @[
        @"operation", @"request_id", @"sequence", @"nonce", @"deadline_ns",
        @"manifest_sha256", @"generation", @"members"
    ]) {
        id value = signedExport[key];
        if (value == nil) {
            if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
            return nil;
        }
        attempt[key] = value;
    }
    attempt[@"request_sha256"] = requestSHA256;
    if (![attempt[@"operation"] isEqual:@"export"] ||
        !AQBrokerOwnerDigest(attempt[@"manifest_sha256"]) ||
        !AQBrokerOwnerDigest(attempt[@"request_sha256"])) {
        if (error != NULL) *error = AQBrokerErrorForCode(AQBrokerInvalidRequest);
        return nil;
    }
    return @{
        @"attempt": attempt,
        @"signed_request": signedExport,
        @"workflow": workflow,
    };
}

static int AQBrokerSession(int argc, const char *argv[]) {
    NSError *error = nil;
    AQInstallationPolicy *policy = nil;
    if (!AQBrokerLoadPolicy(&policy, &error)) return AQBrokerRelayFailure(@"POLICY_UNAVAILABLE");
    NSMutableArray<NSNumber *> *sourceFDs = AQBrokerSourceFDs(argc, argv, 2);
    if (sourceFDs == nil) return AQBrokerRelayFailure(@"SOURCE_BINDING_INVALID");
    NSString *authorizationPath = AQBrokerOptionValue(
        argc, argv, 2, @"--authorization-file=", &error);
    if (error != nil) return AQBrokerRelayFailure(@"AUTHORIZATION_FILE_INVALID");
    NSData *authorizationData = authorizationPath == nil ? nil :
        AQBrokerAuthorizationData(authorizationPath, policy, &error);
    if (authorizationPath != nil && authorizationData == nil) {
        return AQBrokerRelayFailure(@"AUTHORIZATION_FILE_INVALID");
    }
    NSString *receiptDirectory = AQBrokerOptionValue(
        argc, argv, 2, @"--receiver-receipt-dir=", &error);
    if (error != nil) return AQBrokerRelayFailure(@"RECEIVER_RECEIPT_DIRECTORY_INVALID");
    NSString *deliveryFDText = AQBrokerOptionValue(argc, argv, 2, @"--delivery-fd=", &error);
    if (error != nil) return AQBrokerRelayFailure(@"PRIVATE_DELIVERY_DESCRIPTOR_INVALID");
    int deliveryFD = -1;
    if (deliveryFDText != nil) {
        char *end = NULL;
        long value = strtol(deliveryFDText.UTF8String, &end, 10);
        if (end == deliveryFDText.UTF8String || *end != '\0' || value < 0 || value > INT_MAX) {
            return AQBrokerRelayFailure(@"PRIVATE_DELIVERY_DESCRIPTOR_INVALID");
        }
        deliveryFD = (int)value;
    }

    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc] init];
    AQBrokerXPCTransport *transport = [[AQBrokerXPCTransport alloc] initWithPolicy:policy];
    NSDictionary *helloRequest = nil;
    AQBrokerOwnerExportContinuation *ownerContinuation = nil;
    NSDictionary *preparedAttempt = nil;
    NSArray<NSDictionary *> *preparedWorkflow = nil;
    NSMutableData *buffer = [NSMutableData data];
    for (;;) {
        NSData *line = nil;
        BOOL eof = NO;
        if (!AQBrokerReadSessionLine(buffer, &line, &eof, &error)) {
            if (line == nil && eof) return 0;
            AQBrokerPrintCodeTo(stdout, @"BLOCKED",
                                error.localizedDescription ?: @"REQUEST_INVALID");
            return 2;
        }
        if (line.length == 0) {
            if (eof) return 0;
            continue;
        }
        id request = AQParseJSONWithMaximumBytes(
            line, AQBrokerMaximumSessionLineBytes - 1U, &error);
        if (![request isKindOfClass:NSDictionary.class]) {
            AQBrokerPrintCodeTo(stdout, @"BLOCKED", @"REQUEST_INVALID");
            if (eof) return 0;
            continue;
        }
        NSString *brokerOperation = request[@"broker_operation"];
        if ([brokerOperation isEqual:@"prepare_export"]) {
            id schemaVersion = request[@"schema_version"];
            if (helloRequest == nil || ownerContinuation != nil ||
                ![request isKindOfClass:NSDictionary.class] ||
                [(NSDictionary *)request count] != 4 ||
                ![schemaVersion isKindOfClass:NSNumber.class] ||
                CFGetTypeID((__bridge CFTypeRef)schemaVersion) != CFNumberGetTypeID() ||
                [schemaVersion integerValue] != 1) {
                AQBrokerPrintCodeTo(stdout, @"BLOCKED", @"OWNER_EXPORT_PREPARE_INVALID");
                return 2;
            }
            NSDictionary *prepared = AQBrokerPrepareOwnerExport(
                request, helloRequest, policy, session, authorizationData, &error);
            if (prepared == nil) {
                AQBrokerPrintCodeTo(stdout, @"BLOCKED",
                                    error.localizedDescription ?: @"OWNER_AUTHORITY_UNAVAILABLE");
                return 2;
            }
            NSDictionary *helloBindings = @{
                @"connection_id": session.connectionID ?: @"",
                @"session_id": session.sessionID ?: @"",
                @"service_boot_id": helloRequest[@"service_boot_id"] ?: @"",
            };
            ownerContinuation = [[AQBrokerOwnerExportContinuation alloc]
                initWithHelloResponse:helloBindings
                installationID:([helloRequest[@"installation_id"] isKindOfClass:NSString.class]
                    ? (NSString *)helloRequest[@"installation_id"] : @"")
                brokerRevision:([helloRequest[@"broker_revision"] isKindOfClass:NSString.class]
                    ? (NSString *)helloRequest[@"broker_revision"] : @"")
                ownerKeyID:([helloRequest[@"owner_key_id"] isKindOfClass:NSString.class]
                    ? (NSString *)helloRequest[@"owner_key_id"] : @"")
                authorizationSHA256:AQBrokerExactBytesSHA256(authorizationData)];
            preparedAttempt = prepared[@"attempt"];
            preparedWorkflow = prepared[@"workflow"];
            if (ownerContinuation == nil ||
                ![ownerContinuation prepareAttempt:preparedAttempt
                                           workflow:preparedWorkflow
                                              error:&error]) {
                AQBrokerPrintCodeTo(stdout, @"BLOCKED", @"OWNER_EXPORT_BINDING_INVALID");
                return 2;
            }
            NSDictionary *response = @{
                @"status": @"PREPARED",
                @"attempt": preparedAttempt,
                @"signed_request": ([prepared[@"signed_request"] isKindOfClass:NSDictionary.class]
                    ? prepared[@"signed_request"] : @{}),
                @"workflow": preparedWorkflow,
                @"attempt_sha256": ownerContinuation.attemptSHA256,
            };
            if (!AQBrokerWriteJSONLineToFD(STDOUT_FILENO, response, 0, nil, &error)) return 2;
            continue;
        }
        if ([brokerOperation isEqual:@"journal_ack"]) {
            id schemaVersion = request[@"schema_version"];
            if (ownerContinuation == nil ||
                ![request isKindOfClass:NSDictionary.class] ||
                [(NSDictionary *)request count] != 3 ||
                ![schemaVersion isKindOfClass:NSNumber.class] ||
                CFGetTypeID((__bridge CFTypeRef)schemaVersion) != CFNumberGetTypeID() ||
                [schemaVersion integerValue] != 1 ||
                ![ownerContinuation acknowledgeJournalAttemptSHA256:
                    ([request[@"attempt_sha256"] isKindOfClass:NSString.class]
                        ? request[@"attempt_sha256"] : @"")
                                                               error:&error]) {
                AQBrokerPrintCodeTo(stdout, @"BLOCKED", @"OWNER_JOURNAL_ACK_INVALID");
                return 2;
            }
            NSDictionary *response = @{
                @"status": @"JOURNAL_ACKNOWLEDGED",
                @"attempt_sha256": ownerContinuation.attemptSHA256,
            };
            if (!AQBrokerWriteJSONLineToFD(STDOUT_FILENO, response, 0, nil, &error)) return 2;
            continue;
        }
        if ([brokerOperation isEqual:@"dispatch_prepared"]) {
            id schemaVersion = request[@"schema_version"];
            if (ownerContinuation == nil ||
                ![request isKindOfClass:NSDictionary.class] ||
                [(NSDictionary *)request count] != 2 ||
                ![schemaVersion isKindOfClass:NSNumber.class] ||
                CFGetTypeID((__bridge CFTypeRef)schemaVersion) != CFNumberGetTypeID() ||
                [schemaVersion integerValue] != 1) {
                AQBrokerPrintCodeTo(stdout, @"BLOCKED", @"OWNER_EXPORT_DISPATCH_INVALID");
                return 2;
            }
            for (NSUInteger index = 1; index < preparedWorkflow.count; index++) {
                NSDictionary *operationRequest = preparedWorkflow[index];
                NSString *operation = operationRequest[@"operation"];
                if (![ownerContinuation beginDispatchOperation:operation
                                                        request:operationRequest
                                                          error:&error]) {
                    AQBrokerPrintCodeTo(stdout, @"BLOCKED", @"OWNER_EXPORT_DISPATCH_ORDER_INVALID");
                    return 2;
                }
                BOOL operationResponsePrinted = NO;
                BOOL operationFatalOutputFailure = NO;
                if (!AQBrokerProcessRequest(operationRequest, YES, policy, transport, session,
                                            sourceFDs, authorizationData, receiptDirectory,
                                            deliveryFD, &operationResponsePrinted,
                                            &operationFatalOutputFailure, &error) ||
                    ![ownerContinuation completeDispatchOperation:operation error:&error]) {
                    if (operationFatalOutputFailure) return 2;
                    AQBrokerPrintCodeTo(stdout, @"BLOCKED",
                                        error.localizedDescription ?: @"OWNER_EXPORT_DISPATCH_FAILED");
                    return 2;
                }
            }
            return ownerContinuation.dispatchComplete ? 0 : 2;
        }
        BOOL responsePrinted = NO;
        BOOL fatalOutputFailure = NO;
        NSString *serviceOperation = request[@"operation"];
        if ([@[@"admit", @"stage", @"export"] containsObject:serviceOperation]) {
            AQBrokerPrintCodeTo(stdout, @"BLOCKED",
                                ownerContinuation == nil ? @"OWNER_EXPORT_PREPARE_REQUIRED" :
                                @"OWNER_JOURNAL_ACK_REQUIRED");
            return 2;
        }
        if ([serviceOperation isEqual:@"hello"]) {
            if (authorizationData.length == 0) {
                AQBrokerPrintCodeTo(stdout, @"BLOCKED", @"AUTHORIZATION_UNAVAILABLE");
                return 2;
            }
            NSMutableDictionary *authorizedHello = [request mutableCopy];
            authorizedHello[@"authorization_sha256"] =
                AQBrokerExactBytesSHA256(authorizationData);
            request = authorizedHello;
        }
        BOOL accepted = AQBrokerProcessRequest(request, YES, policy, transport, session,
                                                sourceFDs, authorizationData, receiptDirectory,
                                                deliveryFD,
                                                &responsePrinted,
                                                &fatalOutputFailure, &error);
        if (!accepted) {
            if (fatalOutputFailure) return 2;
            AQBrokerPrintCodeTo(stdout, @"BLOCKED",
                                error.localizedDescription ?: @"SERVICE_RESPONSE_INVALID");
        }
        if (accepted && responsePrinted && [serviceOperation isEqual:@"hello"]) {
            helloRequest = request;
        }
        if (eof) return 0;
    }
}

static int AQBrokerRelay(int argc, const char *argv[]) {
    NSError *error = nil;
    AQInstallationPolicy *policy = nil;
    if (!AQBrokerLoadPolicy(&policy, &error)) return AQBrokerRelayFailure(@"POLICY_UNAVAILABLE");
    NSData *requestData = AQBrokerReadStdin();
    id request = requestData == nil ? nil : AQParseJSON(requestData, &error);
    if (![request isKindOfClass:NSDictionary.class]) {
        return AQBrokerRelayFailure(@"REQUEST_INVALID");
    }
    NSMutableArray<NSNumber *> *sourceFDs = AQBrokerSourceFDs(argc, argv, 2);
    if (sourceFDs == nil) return AQBrokerRelayFailure(@"SOURCE_BINDING_INVALID");
    NSString *authorizationPath = AQBrokerOptionValue(
        argc, argv, 2, @"--authorization-file=", &error);
    if (error != nil) return AQBrokerRelayFailure(@"AUTHORIZATION_FILE_INVALID");
    NSData *authorizationData = authorizationPath == nil ? nil :
        AQBrokerAuthorizationData(authorizationPath, policy, &error);
    if (authorizationPath != nil && authorizationData == nil) {
        return AQBrokerRelayFailure(@"AUTHORIZATION_FILE_INVALID");
    }
    NSString *receiptDirectory = AQBrokerOptionValue(
        argc, argv, 2, @"--receiver-receipt-dir=", &error);
    if (error != nil) return AQBrokerRelayFailure(@"RECEIVER_RECEIPT_DIRECTORY_INVALID");

    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return AQBrokerSystemClockNanoseconds(); }
        enforceOrdering:NO];
    AQBrokerXPCTransport *transport = [[AQBrokerXPCTransport alloc] initWithPolicy:policy];
    BOOL responsePrinted = NO;
    BOOL fatalOutputFailure = NO;
    if (!AQBrokerProcessRequest(request, NO, policy, transport, session, sourceFDs,
                                authorizationData, receiptDirectory, -1,
                                &responsePrinted, &fatalOutputFailure, &error)) {
        return AQBrokerRelayFailure(error.localizedDescription ?: @"REQUEST_FAILED");
    }
    return 0;
}
#if !defined(AQ_BROKER_TEST_MAIN)
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (!AQBrokerConfigureSIGPIPE()) {
            AQBrokerPrintCode(@"BLOCKED", @"SIGPIPE_CONFIGURATION_FAILED");
            return 2;
        }
        if (argc == 2 && strcmp(argv[1], "--self-check") == 0) return AQBrokerSelfCheck();
        if (argc >= 2 && strcmp(argv[1], "session") == 0) return AQBrokerSession(argc, argv);
        if (argc >= 2 && strcmp(argv[1], "relay") == 0) return AQBrokerRelay(argc, argv);
        AQBrokerPrintCode(@"BLOCKED", @"USAGE");
        return 2;
    }
}
#endif
