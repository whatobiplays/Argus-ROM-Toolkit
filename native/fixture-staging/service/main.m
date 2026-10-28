#import "AQJSON.h"
#import "AQSecurity.h"
#import "AQServiceProtocol.h"
#import "AQServiceReceiptJournal.h"
#import "AQStore.h"
#import "AQTiming.h"

#import <Security/Security.h>
#import <xpc/xpc.h>

#include <mach/mach_time.h>
#include <stdio.h>
#include <unistd.h>

static const NSUInteger AQServiceWireMaximumValueCount = 256;
static AQServiceReceiptJournal *AQServiceRuntimeReceiptJournal;

@interface AQStore (AQServiceReceiptCapacity)
- (BOOL)reserveReceiptCapacityForSessionID:(NSString *)sessionID error:(NSError **)error;
@end

@implementation AQStore (AQServiceReceiptCapacity)
- (BOOL)reserveReceiptCapacityForSessionID:(NSString *)sessionID error:(NSError **)error {
    AQServiceReceiptJournal *journal = AQServiceRuntimeReceiptJournal;
    if (journal == nil) {
        if (error != NULL) *error = AQServiceError(AQServiceReceiptCapacityDenied);
        return NO;
    }
    return [journal reserveCapacityForSessionID:sessionID error:error];
}
- (BOOL)reserveReceiptCapacityForSessionID:(NSString *)sessionID
                                    created:(BOOL *)created
                                      error:(NSError **)error {
    AQServiceReceiptJournal *journal = AQServiceRuntimeReceiptJournal;
    if (journal == nil) {
        if (error != NULL) *error = AQServiceError(AQServiceReceiptCapacityDenied);
        return NO;
    }
    return [journal reserveCapacityForSessionID:sessionID created:created error:error];
}
- (BOOL)releaseReceiptCapacityForSessionID:(NSString *)sessionID error:(NSError **)error {
    AQServiceReceiptJournal *journal = AQServiceRuntimeReceiptJournal;
    if (journal == nil) {
        if (error != NULL) *error = AQServiceError(AQServiceReceiptCapacityDenied);
        return NO;
    }
    return [journal releaseCapacityForSessionID:sessionID error:error];
}
@end

#ifdef AQ_SERVICE_TESTING
static NSUInteger AQServiceTestDocumentAccessCount;
static NSUInteger AQServiceTestDescriptorDecodeCount;
static NSUInteger AQServiceTestDescriptorDuplicateCount;
static NSUInteger AQServiceTestDispatchCount;

void AQServiceResetWireAccessCountersForTesting(void) {
    AQServiceTestDocumentAccessCount = 0;
    AQServiceTestDescriptorDecodeCount = 0;
    AQServiceTestDescriptorDuplicateCount = 0;
    AQServiceTestDispatchCount = 0;
}

void AQServiceSetReceiptJournalForTesting(AQServiceReceiptJournal *journal) {
    AQServiceRuntimeReceiptJournal = journal;
}

NSUInteger AQServiceDocumentAccessCountForTesting(void) {
    return AQServiceTestDocumentAccessCount;
}

NSUInteger AQServiceDescriptorDecodeCountForTesting(void) {
    return AQServiceTestDescriptorDecodeCount;
}

NSUInteger AQServiceDescriptorDuplicateCountForTesting(void) {
    return AQServiceTestDescriptorDuplicateCount;
}

NSUInteger AQServiceDispatchCountForTesting(void) {
    return AQServiceTestDispatchCount;
}
#endif

@interface AQServiceRuntimeClock : NSObject <AQServiceClock>
@end

@implementation AQServiceRuntimeClock
- (uint64_t)monotonicNanoseconds {
    uint64_t now = 0;
    return AQServiceMonotonicNanosecondsNow(&now) ? now : UINT64_MAX;
}
- (uint64_t)continuousTicks {
    return mach_continuous_time();
}
@end

static NSString *AQRandomToken(void) {
    uint8_t bytes[32] = {0};
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;
    NSMutableString *value = [NSMutableString stringWithCapacity:sizeof(bytes) * 2];
    for (NSUInteger index = 0; index < sizeof(bytes); ++index) {
        [value appendFormat:@"%02x", bytes[index]];
    }
    return value;
}

static NSString *AQServiceBlocker(NSError *error, NSString *fallback) {
    if ([error.domain isEqual:AQSecurityErrorDomain]) {
        switch ((AQSecurityError)error.code) {
            case AQSecurityInvalidPolicy: return @"INSTALLATION_POLICY_INVALID";
            case AQSecurityUntrustedInstallation: return @"INSTALLATION_UNTRUSTED";
            case AQSecurityUnsupportedPlatform: return @"AUTHENTICATED_PEER_API_UNAVAILABLE";
            case AQSecurityNotEnrolled: return @"OWNER_KEY_NOT_ENROLLED";
            default: return fallback;
        }
    }
    if ([error.domain isEqual:AQServiceErrorDomain]) {
        return error.localizedDescription.length != 0 ? error.localizedDescription : fallback;
    }
    return fallback;
}

static __attribute__((unused)) void AQPrintBlockedCheck(NSString *code) {
    printf("{\"status\":\"BLOCKED\",\"code\":\"%s\",\"authority\":\"NOT_RUN\"}\n",
           code.UTF8String);
}

static BOOL AQStrictXPCValue(xpc_object_t value, NSUInteger depth,
                             NSUInteger *items, id _Nullable *result) {
    if (depth > 32 || ++(*items) > AQServiceWireMaximumValueCount) return NO;
    xpc_type_t type = xpc_get_type(value);
    if (type == XPC_TYPE_STRING) {
        const char *text = xpc_string_get_string_ptr(value);
        if (text == NULL || strlen(text) > 4096) return NO;
        *result = [NSString stringWithUTF8String:text];
        return *result != nil;
    }
    if (type == XPC_TYPE_BOOL) {
        *result = @(xpc_bool_get_value(value));
        return YES;
    }
    if (type == XPC_TYPE_UINT64) {
        uint64_t integer = xpc_uint64_get_value(value);
        if (integer > INT64_MAX) return NO;
        *result = @(integer);
        return YES;
    }
    if (type == XPC_TYPE_DATA) {
        size_t length = 0;
        const void *bytes = xpc_data_get_bytes_ptr(value);
        length = xpc_data_get_length(value);
        if (length > AQServiceMaximumDocumentBytes || (length != 0 && bytes == NULL)) return NO;
        *result = [NSData dataWithBytes:bytes length:length];
        return YES;
    }
    if (type == XPC_TYPE_ARRAY) {
        if (xpc_array_get_count(value) > AQServiceWireMaximumValueCount) return NO;
        NSMutableArray *array = [NSMutableArray array];
        for (size_t index = 0; index < xpc_array_get_count(value); ++index) {
            id converted = nil;
            if (!AQStrictXPCValue(xpc_array_get_value(value, index), depth + 1, items,
                                  &converted)) return NO;
            [array addObject:converted];
        }
        *result = array;
        return YES;
    }
    if (type == XPC_TYPE_DICTIONARY) {
        if (xpc_dictionary_get_count(value) > AQServiceWireMaximumValueCount) return NO;
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        __block BOOL valid = YES;
        xpc_dictionary_apply(value, ^bool(const char *key, xpc_object_t item) {
            id converted = nil;
            NSString *name = key == NULL ? nil : [NSString stringWithUTF8String:key];
            if (name.length == 0 || !AQStrictXPCValue(item, depth + 1, items, &converted)) {
                valid = NO;
                return false;
            }
            dictionary[name] = converted;
            return true;
        });
        if (!valid) return NO;
        *result = dictionary;
        return YES;
    }
    return NO;
}

static NSDictionary *AQDecodeRequestMessage(xpc_object_t message, NSError **error) {
    const NSUInteger maximumReceiptMessageBytes = AQServiceMaximumReceiptBytes;
    NSSet *allowed = [NSSet setWithArray:@[
        @"version", @"request", @"authorization", @"documents", @"source_fds"
    ]];
    __block BOOL keysValid = YES;
    xpc_dictionary_apply(message, ^bool(const char *key, __unused xpc_object_t value) {
        NSString *keyString = key ? [NSString stringWithUTF8String:key] : nil;
        keysValid = keysValid && keyString != nil && [allowed containsObject:keyString];
        return keysValid;
    });
    if (!keysValid || xpc_dictionary_get_uint64(message, "version") != 1) {
        if (error != NULL) *error = AQServiceError(AQServiceInvalidRequest);
        return nil;
    }
    xpc_object_t requestValue = xpc_dictionary_get_value(message, "request");
    size_t requestLength = requestValue != NULL && xpc_get_type(requestValue) == XPC_TYPE_DATA
        ? xpc_data_get_length(requestValue) : 0;
    if (requestLength == 0 || requestLength > maximumReceiptMessageBytes) {
        if (error != NULL) *error = AQServiceError(AQServiceLimitExceeded);
        return nil;
    }
    NSData *requestData = [NSData dataWithBytes:xpc_data_get_bytes_ptr(requestValue)
                                         length:requestLength];
    id requestObject = requestLength <= AQServiceMaximumRequestBytes
        ? AQParseJSON(requestData, error)
        : AQParseJSONWithMaximumBytes(requestData, maximumReceiptMessageBytes, error);
    if (![requestObject isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *request = [requestObject mutableCopy];
    if (requestLength > AQServiceMaximumRequestBytes &&
        ![request[@"operation"] isEqual:@"receipt_query"] &&
        ![request[@"operation"] isEqual:@"receipt_record"]) {
        if (error != NULL) *error = AQServiceError(AQServiceLimitExceeded);
        return nil;
    }
    xpc_object_t authorizationValue = xpc_dictionary_get_value(message, "authorization");
    if (authorizationValue != NULL) {
        if (xpc_get_type(authorizationValue) != XPC_TYPE_DATA) {
            if (error != NULL) *error = AQServiceError(AQServiceInvalidRequest);
            return nil;
        }
        size_t authorizationLength = xpc_data_get_length(authorizationValue);
        const void *authorizationBytes = xpc_data_get_bytes_ptr(authorizationValue);
        if (authorizationLength == 0 || authorizationLength > AQServiceMaximumDocumentBytes ||
            (authorizationLength != 0 && authorizationBytes == NULL)) {
            if (error != NULL) *error = AQServiceError(AQServiceInvalidRequest);
            return nil;
        }
        request[@"authorization"] = [NSData dataWithBytes:authorizationBytes
                                                   length:authorizationLength];
    }
    return request;
}

static void AQCloseDescriptors(NSArray<NSNumber *> *descriptors) {
    for (NSNumber *descriptor in descriptors) close([descriptor intValue]);
}

static BOOL AQDecodeDocuments(xpc_object_t message, NSDictionary * _Nullable *documents,
                              NSError **error) {
    *documents = nil;
    xpc_object_t value = xpc_dictionary_get_value(message, "documents");
    if (value == NULL) return YES;
#ifdef AQ_SERVICE_TESTING
    AQServiceTestDocumentAccessCount++;
#endif
    NSUInteger items = 0;
    id converted = nil;
    if (!AQStrictXPCValue(value, 0, &items, &converted) ||
        ![converted isKindOfClass:NSDictionary.class]) {
        if (error != NULL) *error = AQServiceError(AQServiceInvalidRequest);
        return NO;
    }
    *documents = converted;
    return YES;
}

static BOOL AQDecodeSourceDescriptors(xpc_object_t message, NSArray<NSNumber *> **descriptors,
                                      NSError **error) {
    *descriptors = @[];
    xpc_object_t fdValue = xpc_dictionary_get_value(message, "source_fds");
    if (fdValue == NULL) return YES;
#ifdef AQ_SERVICE_TESTING
    AQServiceTestDescriptorDecodeCount++;
#endif
    if (xpc_get_type(fdValue) != XPC_TYPE_ARRAY ||
        xpc_array_get_count(fdValue) > AQServiceMaximumSourceDescriptors) {
        if (error != NULL) *error = AQServiceError(AQServiceLimitExceeded);
        return NO;
    }

    NSMutableArray<NSNumber *> *duplicatedDescriptors = [NSMutableArray array];
    for (size_t index = 0; index < xpc_array_get_count(fdValue); ++index) {
        xpc_object_t entry = xpc_array_get_value(fdValue, index);
        if (xpc_get_type(entry) != XPC_TYPE_FD) {
            AQCloseDescriptors(duplicatedDescriptors);
            if (error != NULL) *error = AQServiceError(AQServiceInvalidRequest);
            return NO;
        }
#ifdef AQ_SERVICE_TESTING
        AQServiceTestDescriptorDuplicateCount++;
#endif
        int duplicated = xpc_fd_dup(entry);
        if (duplicated < 0) {
            AQCloseDescriptors(duplicatedDescriptors);
            if (error != NULL) *error = AQServiceError(AQServiceInvalidRequest);
            return NO;
        }
        [duplicatedDescriptors addObject:@(duplicated)];
    }
    *descriptors = duplicatedDescriptors;
    return YES;
}

static NSDictionary<NSString *, NSNumber *> *AQMapSourceDescriptors(NSDictionary *request,
                                                                   NSArray<NSNumber *> *descriptors) {
    NSArray *paths = request[@"source_paths"];
    if (![paths isKindOfClass:NSArray.class] || paths.count != descriptors.count) return nil;
    NSMutableDictionary<NSString *, NSNumber *> *mapped = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < paths.count; ++index) {
        if (![paths[index] isKindOfClass:NSString.class]) return nil;
        mapped[paths[index]] = descriptors[index];
    }
    return mapped;
}

static __attribute__((unused)) BOOL AQLoadRuntime(AQInstallationPolicy **policyOut,
                                                  AQServiceSessionCore **coreOut,
                                                  NSString **blockerOut) {
    NSError *error = nil;
    AQInstallationPolicy *policy = AQLoadInstallationPolicy(&error);
    if (policy == nil) { *blockerOut = AQServiceBlocker(error, @"POLICY_UNAVAILABLE"); return NO; }
    if (policy.ownerPublicKey == nil) {
        *blockerOut = @"OWNER_KEY_NOT_ENROLLED"; return NO;
    }
    if (!AQValidateNonLoginServiceIdentity(policy, &error)) {
        *blockerOut = AQServiceBlocker(error, @"SERVICE_IDENTITY_INVALID"); return NO;
    }
    if (geteuid() != policy.serviceUID) {
        *blockerOut = @"SERVICE_UID_MISMATCH"; return NO;
    }
    if (!AQAuthenticatedPeerAPIsAvailable(&error)) {
        *blockerOut = AQServiceBlocker(error, @"AUTHENTICATED_PEER_API_UNAVAILABLE"); return NO;
    }
    int rootFD = AQOpenProductionStagingRoot(policy, &error);
    if (rootFD < 0) {
        *blockerOut = @"PRODUCTION_ROOT_UNAVAILABLE"; return NO;
    }
    AQServiceReceiptJournal *receiptJournal =
        [[AQServiceReceiptJournal alloc] initWithProtectedRootFD:rootFD error:&error];
    if (receiptJournal == nil) {
        close(rootFD);
        *blockerOut = @"RECEIPT_JOURNAL_UNAVAILABLE";
        return NO;
    }
    NSDictionary *installation = @{
        @"team_id": policy.teamIdentifier,
        @"broker_cdhash": policy.brokerCDHash,
        @"service_cdhash": policy.serviceCDHash,
        @"owner_uid": @(policy.ownerUID),
        @"service_uid": @(policy.serviceUID),
        @"owner_key_id": policy.keyTag
    };
    NSString *installationID = AQDigest(@"argus.fixture-staging.installation.v1", installation, &error);
    AQStore *store = [[AQStore alloc] initWithRootFD:rootFD installationIdentity:installationID error:&error];
    close(rootFD);
    if (store == nil) { *blockerOut = @"STORE_INITIALIZATION_FAILED"; return NO; }
    NSString *bootID = AQRandomToken();
    if (installationID == nil || bootID == nil) {
        *blockerOut = @"RANDOMNESS_UNAVAILABLE"; return NO;
    }
    AQServiceOwnerVerifier ownerVerifier = ^BOOL(NSData *consent, NSData *signature, NSError **verifyError) {
        return AQVerifyOwnerSignature(policy, consent, signature, verifyError);
    };
    AQServiceSessionCore *core = [[AQServiceSessionCore alloc]
        initWithStore:(id<AQServiceStore>)store
 installationIdentity:installationID
    serviceBootIdentity:bootID
        brokerRevision:policy.brokerCDHash
      ownerKeyIdentifier:policy.keyTag
                  clock:[[AQServiceRuntimeClock alloc] init]
          ownerVerifier:ownerVerifier
     identifierGenerator:^NSString * _Nullable{ return AQRandomToken(); }
                   error:&error];
    if (core == nil) { *blockerOut = @"SERVICE_STATE_INITIALIZATION_FAILED"; return NO; }
    AQServiceRuntimeReceiptJournal = receiptJournal;
    *policyOut = policy;
    *coreOut = core;
    return YES;
}

static void AQSendResponse(xpc_connection_t connection, NSDictionary *response, int exportFD) {
    const NSUInteger maximumReceiptMessageBytes = AQServiceMaximumReceiptBytes;
    NSError *error = nil;
    NSData *encoded = AQCanonicalJSON(response, &error);
    if (encoded == nil && [response[@"completion"] isKindOfClass:NSDictionary.class]) {
        encoded = AQCanonicalJSONWithMaximumBytes(
            response, maximumReceiptMessageBytes, &error);
    }
    if (encoded == nil || encoded.length > maximumReceiptMessageBytes ||
        (encoded.length > AQServiceMaximumRequestBytes &&
         ![response[@"completion"] isKindOfClass:NSDictionary.class])) {
        encoded = [@"{\"code\":\"INTERNAL_FAILURE\",\"status\":\"BLOCKED\"}"
            dataUsingEncoding:NSUTF8StringEncoding];
    }
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(message, "version", 1);
    xpc_dictionary_set_data(message, "response", encoded.bytes, encoded.length);
    if (exportFD >= 0) xpc_dictionary_set_fd(message, "export_fd", exportFD);
    xpc_connection_send_message(connection, message);
}

typedef void (^AQServiceWireResponseSender)(NSDictionary *response, int exportFD);
typedef void (^AQServiceWireInvalidator)(NSString *reason);

/* Processes an authenticated broker message. Payload decoding and core dispatch
   live here so the executable boundary can be exercised without an XPC pair. */
static void AQServiceHandleWireMessage(AQServiceSessionCore *core, NSString *connectionID,
                                       xpc_object_t event,
                                       AQServiceWireResponseSender sendResponse,
                                       AQServiceWireInvalidator invalidate) {
    NSError *peerError = nil;
    NSDictionary *request = AQDecodeRequestMessage(event, &peerError);
    if (request == nil) {
        sendResponse(@{@"status": @"BLOCKED",
                       @"code": AQServiceError(AQServiceInvalidRequest).localizedDescription}, -1);
        invalidate(@"malformed_message");
        return;
    }

    /* These two narrow messages are handled only after the listener validates
     * the live broker code identity. Receipt lookup is read-only; recording is
     * limited to the broker's complete, durable receiver completion record. */
    NSString *operation = request[@"operation"];
    AQServiceReceiptJournal *receiptJournal = AQServiceRuntimeReceiptJournal;
    if ([operation isEqual:@"receipt_query"] ||
        [operation isEqual:@"receipt_record"]) {
        NSDictionary *binding = request[@"binding"];
        NSError *receiptError = nil;
        NSDictionary *completion = nil;
        BOOL accepted = NO;
        if ([binding isKindOfClass:NSDictionary.class] && receiptJournal != nil) {
            if ([operation isEqual:@"receipt_query"]) {
                completion = [receiptJournal receiptForBinding:binding error:&receiptError];
                accepted = completion != nil;
            } else {
                NSDictionary *candidate = request[@"completion"];
                if ([candidate isKindOfClass:NSDictionary.class]) {
                    NSMutableDictionary *boundCandidate = [candidate mutableCopy];
                    if (boundCandidate[@"service_boot_id"] == nil &&
                        binding[@"service_boot_id"] != nil) {
                        boundCandidate[@"service_boot_id"] = binding[@"service_boot_id"];
                    }
                    if (boundCandidate[@"sequence"] == nil && binding[@"sequence"] != nil) {
                        boundCandidate[@"sequence"] = binding[@"sequence"];
                    }
                    accepted = [receiptJournal recordBrokerCompletion:boundCandidate
                                                              binding:binding
                                                                error:&receiptError];
                    if (accepted) completion = boundCandidate;
                }
            }
        }
        if (accepted) {
            sendResponse(@{@"status": @"OK", @"request_id": request[@"request_id"] ?: @"",
                           @"completion": completion ?: @{}}, -1);
        } else {
            sendResponse(@{@"status": @"BLOCKED", @"code": @"RECEIPT_UNAVAILABLE",
                           @"request_id": request[@"request_id"] ?: @""}, -1);
        }
        return;
    }

    __block NSArray<NSNumber *> *descriptors = @[];
    __block NSString *payloadFailure = nil;
    __block NSError *documentsError = nil;
    __block NSError *descriptorsError = nil;
    __block BOOL loaderCheckoutStarted = NO;
    int exportFD = -1;
    NSDictionary *result = [core handleRequest:request
        documentsLoader:(xpc_dictionary_get_value(event, "documents") != NULL ? ^NSDictionary *{
            if (!loaderCheckoutStarted) {
#ifdef AQ_SERVICE_TESTING
                AQServiceTestDispatchCount++;
#endif
                loaderCheckoutStarted = YES;
            }
            NSDictionary *documents = nil;
            if (!AQDecodeDocuments(event, &documents, &documentsError)) {
                payloadFailure = @"malformed_documents";
                return @{};
        }
        return documents;
        } : nil)
        sourceFDsLoader:(xpc_dictionary_get_value(event, "source_fds") != NULL ? ^NSDictionary *{
            if (!loaderCheckoutStarted) {
#ifdef AQ_SERVICE_TESTING
                AQServiceTestDispatchCount++;
#endif
                loaderCheckoutStarted = YES;
            }
            if (!AQDecodeSourceDescriptors(event, &descriptors, &descriptorsError)) {
                payloadFailure = @"malformed_message";
                return @{};
            }
            if ([request[@"operation"] isEqual:@"stage"]) {
                NSDictionary *sourceFDs = AQMapSourceDescriptors(request, descriptors);
                if (sourceFDs == nil) payloadFailure = @"source_binding_failed";
                return sourceFDs ?: @{};
        }
        return descriptors.count == 0 ? nil : @{};
        } : nil)
        connectionID:connectionID exportFileDescriptor:&exportFD error:&peerError];
    AQCloseDescriptors(descriptors);
    if (result == nil) {
        NSString *code = peerError.localizedDescription ?: @"STORE_DENIED";
        NSMutableDictionary *response = [@{
            @"status": @"BLOCKED", @"code": code,
            @"request_id": request[@"request_id"] ?: @""
        } mutableCopy];
        sendResponse(response, -1);
        if (payloadFailure != nil) {
            invalidate(payloadFailure);
        } else if ([code isEqual:@"UNAUTHENTICATED_CONNECTION"] ||
            [code isEqual:@"SESSION_BINDING_MISMATCH"] ||
            [code isEqual:@"OWNER_CONSENT_DENIED"] || [code isEqual:@"REPLAY_REJECTED"]) {
            invalidate(@"protocol_rejection");
        }
    } else {
        sendResponse(@{
            @"status": @"OK", @"request_id": request[@"request_id"] ?: @"", @"result": result
        }, exportFD);
        if (exportFD >= 0) close(exportFD);
    }
}

#ifdef AQ_SERVICE_TESTING
BOOL AQServiceHandleWireMessageForTesting(AQServiceSessionCore *core, NSString *connectionID,
                                          xpc_object_t event, NSDictionary **responseOut,
                                          NSString **invalidationReasonOut) {
    __block NSDictionary *capturedResponse = nil;
    __block NSString *capturedReason = nil;
    AQServiceHandleWireMessage(core, connectionID, event,
                               ^(NSDictionary *response, __unused int exportFD) {
        capturedResponse = response;
    }, ^(NSString *reason) {
        capturedReason = reason;
    });
    if (responseOut != NULL) *responseOut = capturedResponse;
    if (invalidationReasonOut != NULL) *invalidationReasonOut = capturedReason;
    return capturedResponse != nil;
}
#endif

static __attribute__((unused)) void AQConfigureBrokerConnection(
    xpc_connection_t connection, AQInstallationPolicy *policy, AQServiceSessionCore *core) {
    xpc_connection_set_target_queue(connection, AQServiceSerialPeerQueue());
    NSError *error = nil;
    if (!AQConfigurePeerRequirement(connection, policy, AQPeerBroker, &error)) {
        xpc_connection_cancel(connection);
        return;
    }
    __block NSString *connectionID = [core openConnection:&error];
    if (connectionID == nil) { xpc_connection_cancel(connection); return; }
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_ERROR) {
            [core invalidateConnection:connectionID reason:@"connection_error"];
            return;
        }
        NSError *peerError = nil;
        if (!AQValidatePeerMessage(event, policy, AQPeerBroker, &peerError)) {
            [core invalidateConnection:connectionID reason:@"peer_authentication_failed"];
            xpc_connection_cancel(connection);
            return;
        }
        AQServiceHandleWireMessage(core, connectionID, event,
            ^(NSDictionary *response, int exportFD) {
                AQSendResponse(connection, response, exportFD);
            }, ^(NSString *reason) {
                [core invalidateConnection:connectionID reason:reason];
                xpc_connection_cancel(connection);
            });
    });
    xpc_connection_resume(connection);
}

static int AQServiceWriteSelfCheckOutput(NSData *encoded, FILE *stream) {
    if (fwrite(encoded.bytes, 1, encoded.length, stream) != encoded.length) {
        return 2;
    }
    if (fputc('\n', stream) == EOF) {
        return 2;
    }
    if (fflush(stream) != 0) {
        return 2;
    }
    return 0;
}

#ifdef AQ_SERVICE_TESTING
int AQServiceWriteSelfCheckOutputForTesting(NSData *encoded, FILE *stream) {
    return AQServiceWriteSelfCheckOutput(encoded, stream);
}
#endif

#ifndef AQ_SERVICE_TESTING
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL checkOnly = argc == 2 && strcmp(argv[1], "--self-check") == 0;
        AQInstallationPolicy *policy = nil;
        AQServiceSessionCore *core = nil;
        NSString *blocker = nil;
        if (!AQLoadRuntime(&policy, &core, &blocker)) {
            AQPrintBlockedCheck(blocker ?: @"SERVICE_READINESS_FAILED");
            return 2;
        }
        NSDictionary *facts = [core readinessFacts];
        if (checkOnly) {
            NSError *error = nil;
            NSData *encoded = AQCanonicalJSON(facts, &error);
            if (encoded == nil) return 2;
        return AQServiceWriteSelfCheckOutput(encoded, stdout);
        }
    const char *serviceName = AQMachServiceName.UTF8String;
    if (serviceName == NULL) {
        AQPrintBlockedCheck(@"SERVICE_NAME_UNAVAILABLE");
        return 2;
    }
    xpc_connection_t listener = xpc_connection_create_mach_service(
        serviceName, dispatch_get_main_queue(),
            XPC_CONNECTION_MACH_SERVICE_LISTENER);
        NSError *error = nil;
        if (listener == NULL ||
            !AQConfigurePeerRequirement(listener, policy, AQPeerBroker, &error)) {
            AQPrintBlockedCheck(@"LISTENER_AUTHENTICATION_FAILED");
            return 2;
        }
        xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
            if (xpc_get_type(peer) == XPC_TYPE_CONNECTION) {
                AQConfigureBrokerConnection((xpc_connection_t)peer, policy, core);
            }
        });
        xpc_connection_resume(listener);
        dispatch_main();
    }
}
#endif
