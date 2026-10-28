#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const AQBrokerErrorDomain;
typedef NS_ENUM(NSInteger, AQBrokerErrorCode) {
    AQBrokerInvalidFrame = 1,
    AQBrokerFrameTooLarge,
    AQBrokerFrameDigestMismatch,
    AQBrokerFrameMemberMismatch,
    AQBrokerBindingMismatch,
    AQBrokerSpoolUnavailable,
    AQBrokerSpoolCapacityDenied,
    AQBrokerUncertainEffect,
    AQBrokerReconnectRequired,
    AQBrokerInvalidRequest,
    AQBrokerDeadlineExpired,
    AQBrokerOperationInProgress,
    AQBrokerLateReply,
    AQBrokerSequenceMismatch,
    AQBrokerSessionOwnershipMismatch,
    AQBrokerFreshAuthenticationRequired,
    AQBrokerDurableReceiptFailed,
};

/** Returns the stable broker error for one broker error code. The localized
 * description is a machine code suitable for the broker's JSON diagnostics. */
FOUNDATION_EXPORT NSError *AQBrokerErrorForCode(AQBrokerErrorCode code);

/** Receives member bytes in manifest order only after the complete frame,
 * terminal digest, and trusted-request binding have been verified. Each
 * callback receives independently owned immutable data with a maximum length
 * of 64 KiB, so retaining the NSData is safe. Delivery is synchronous and
 * ordered; the verifier does not advance to the next chunk until the callback
 * returns. The callback must consume the bytes, or retain them and apply its
 * own backpressure, before returning YES. Returning NO stops delivery,
 * prevents creation of a completion record, and makes finish fail. A failed
 * verification invokes this callback zero times. */
typedef BOOL (^AQBrokerExportSink)(NSString *path, NSData *bytes, uint64_t offset);

typedef uint64_t (^AQBrokerMonotonicClock)(void);

/** Writes every byte in bytes to fd. Partial writes and EINTR are retried;
 * a zero-byte write or any other error fails. Returns YES only after the
 * complete buffer has been accepted by the descriptor. An empty buffer
 * succeeds without invoking write. */
FOUNDATION_EXPORT BOOL AQBrokerWriteAll(int fd, NSData *bytes, NSError **error);

/** Writes every byte without blocking beyond an absolute monotonic deadline.
 * The descriptor is temporarily made nonblocking while callers wait for
 * writability. Every retry recomputes the remaining lifetime from the original
 * deadline; zero-byte writes, descriptor errors, clock failure, or deadline
 * expiry fail with a diagnostic that preserves the underlying errno where
 * applicable. */
FOUNDATION_EXPORT BOOL AQBrokerWriteAllUntilDeadline(int fd, NSData *bytes,
                                                     uint64_t deadlineNanoseconds,
                                                     AQBrokerMonotonicClock clock,
                                                     NSError **error);

#if defined(AQ_BROKER_TESTING)
typedef ssize_t (^AQBrokerTestWriteOperation)(int fd, const void *bytes, size_t length);

/** Deterministic write-all variant for syscall-failure tests. */
FOUNDATION_EXPORT BOOL AQBrokerTestWriteAll(int fd, NSData *bytes,
                                            AQBrokerTestWriteOperation _Nullable operation,
                                            NSError **error);
#endif

/** Incrementally verifies an AQStore export frame. Synthetic test builds use
 * an unlinked named temporary spool for streaming regressions. Production
 * builds fail closed before spool creation because the supported macOS target
 * provides no anonymous from inception spool or enforced isolation boundary;
 * no payload is delivered and no completion is published. Test spool hashes
 * detect corruption but do not establish same-UID confidentiality. */
@interface AQBrokerExportVerifier : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSink:(nullable AQBrokerExportSink)sink
                    expectedSessionID:(NSString *)sessionID
                   expectedGeneration:(uint64_t)generation
             expectedManifestSHA256:(NSString *)manifestSHA256
                   authorizationSHA256:(NSString *)authorizationSHA256
                     approvedManifest:(NSDictionary *)manifest
                            requestID:(NSString *)requestID
                 deadlineNanoseconds:(uint64_t)deadlineNanoseconds
                                  clock:(AQBrokerMonotonicClock)clock
                       receiptDirectory:(NSString *)receiptDirectory
                                error:(NSError **)error;
- (BOOL)consumeData:(NSData *)data error:(NSError **)error;
- (BOOL)finishWithError:(NSError **)error;
@property(nonatomic, readonly, copy, nullable) NSDictionary *header;
/** Set once a complete frame, its ordered members, and terminal digest have
 * verified. This proves transport framing only; it does not acknowledge
 * payload delivery. */
@property(nonatomic, readonly, copy, nullable) NSDictionary *transportCompletion;
/** Set only after complete verification, deadline-bounded verified-payload
 * delivery, file sync, directory sync, and creation of the request-bound
 * durable receiver receipt. A nil value after finish means the owner must
 * treat the export as failed or uncertain. */
@property(nonatomic, readonly, copy, nullable) NSDictionary *completion;
@end

#if defined(AQ_BROKER_TESTING)
/** Returns the test spool descriptor after frame consumption has created it. */
FOUNDATION_EXPORT int AQBrokerTestSpoolDescriptor(AQBrokerExportVerifier *verifier);

/** Returns the pathname used when creating the current synthetic test spool. */
FOUNDATION_EXPORT NSString * _Nullable AQBrokerTestSpoolPath(
    AQBrokerExportVerifier *verifier);

/** Replaces the filesystem-capacity query in test builds so the exact reserve
 * boundary can be exercised without allocating a multi-gigabyte volume. */
FOUNDATION_EXPORT void AQBrokerTestSetSpoolAvailableBytes(uint64_t availableBytes);
FOUNDATION_EXPORT void AQBrokerTestClearSpoolAvailableBytes(void);
/** Forces test spool creation to fail before creating a named temporary file. */
FOUNDATION_EXPORT void AQBrokerTestForceSpoolUnavailableForTesting(BOOL unavailable);

/** Forces the next descriptor sync in a broker verifier to fail with errno.
 * The test setting applies to one sync operation and is then cleared. */
FOUNDATION_EXPORT void AQBrokerTestSetNextSyncFailure(int errorNumber);
/** Injects a sync failure after the requested number of successful syncs. */
FOUNDATION_EXPORT void AQBrokerTestSetSyncFailureAfter(NSUInteger successfulSyncs,
                                                       int errorNumber);
/** Fails a deadline-bounded write after this many bytes have been written. */
FOUNDATION_EXPORT void AQBrokerTestSetWriteFailureAfterBytes(NSUInteger bytes);
#endif

/** Prevents a reconnect from silently reapplying an operation whose result was
 * lost. A mutation dispatched on a connection is marked uncertain when that
 * connection is lost or its reply deadline expires. Read-only inspection
 * remains available after a new authenticated connection opens. Another
 * mutation requires the caller to resolve the durable outcome and start a new
 * broker session.
 *
 * Only one operation may be in flight. Callers normally begin with an open
 * connection, call exactly one of dispatchInspection or dispatchMutation, and
 * then call operationCompleted after a trustworthy response arrived. Calling
 * connectionOpened after a reconnect starts a new connection generation. */
@interface AQBrokerReconnectGuard : NSObject
- (BOOL)connectionOpened;
- (BOOL)dispatchInspection;
- (BOOL)dispatchMutation;
- (void)operationCompleted;
- (void)connectionLostWithOutcomeKnown:(BOOL)known;
- (BOOL)canDispatchInspection;
- (BOOL)canDispatchMutation;
@property(nonatomic, readonly, getter=isOperationInFlight) BOOL operationInFlight;
@property(nonatomic, readonly) BOOL uncertainEffect;
@property(nonatomic, readonly) BOOL outcomeUnknown;
@property(nonatomic, readonly) NSUInteger generation;
@end

/** Reads the same monotonic nanosecond clock used by schema-1 authorization
 * deadlines. An unavailable or unrepresentable clock is reported as
 * UINT64_MAX so every deadline comparison fails closed. */
FOUNDATION_EXPORT uint64_t AQBrokerSystemClockNanoseconds(void);

/** Calculates the time left before an immutable monotonic deadline. The
 * deadline is exclusive: now >= deadline is already expired. */
FOUNDATION_EXPORT BOOL AQBrokerDeadlineRemaining(uint64_t deadlineNanoseconds,
                                                  uint64_t nowNanoseconds,
                                                  uint64_t *remainingNanoseconds,
                                                  NSError **error);

/** Coerces one broker session's sequential request stream.
 *
 * A session accepts readiness before a handshake, one unbound hello, and then
 * strictly ordered post-handshake requests. Every request has a positive
 * request_id and an immutable deadline_ns. Post-handshake deadlines and
 * ordering fields come from the canonical freshness_envelope. The first
 * hello establishes the owner, installation, service boot, broker revision,
 * owner key, grant bindings, and immutable session deadline. A later hello is
 * accepted only after a connection loss and must preserve those bindings and
 * the original deadline. Every later request uses that same absolute deadline.
 *
 * beginRequest reserves the sole in-flight slot. acceptResponseForToken
 * verifies the response request identifier and deadline without releasing the
 * operation. completeRequestForToken releases it after the caller has a known
 * result; for an export this must wait until the complete frame has been
 * verified and delivered. An unknown completion, timeout, or lost connection
 * marks a mutation uncertain and requires fresh authentication. Replies for
 * completed, expired, or unknown operations are rejected as late replies.
 *
 * A process that intentionally supports only the legacy one-request relay can
 * construct the class with enforceOrdering=NO. That mode still enforces the
 * one-operation gate, immutable deadline, reconnect guard, and late-reply
 * rules; it does not claim session ownership or sequence state. */
/** Holds one hello-bound owner export until the private journal acknowledges it.
 * The prepared workflow is immutable, mutations are released only in
 * admit/stage/export order, and the caller must provide native owner
 * signatures before preparation succeeds. */
@interface AQBrokerOwnerExportContinuation : NSObject
- (nullable instancetype)initWithHelloResponse:(NSDictionary *)helloResponse
                               installationID:(NSString *)installationID
                                brokerRevision:(NSString *)brokerRevision
                                     ownerKeyID:(NSString *)ownerKeyID
                          authorizationSHA256:(NSString *)authorizationSHA256
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (BOOL)prepareAttempt:(NSDictionary *)attempt
              workflow:(NSArray<NSDictionary *> *)workflow
                 error:(NSError **)error;
- (BOOL)acknowledgeJournalAttemptSHA256:(NSString *)attemptSHA256
                                  error:(NSError **)error;
- (BOOL)beginDispatchOperation:(NSString *)operation
                       request:(NSDictionary *)request
                         error:(NSError **)error;
- (BOOL)completeDispatchOperation:(NSString *)operation error:(NSError **)error;
@property(nonatomic, readonly, copy) NSString *attemptSHA256;
@property(nonatomic, readonly, getter=isDispatchComplete) BOOL dispatchComplete;
@end

@interface AQBrokerSequentialSession : NSObject
- (instancetype)init;
- (instancetype)initWithClock:(AQBrokerMonotonicClock)clock;
- (instancetype)initWithClock:(AQBrokerMonotonicClock)clock
               enforceOrdering:(BOOL)enforceOrdering NS_DESIGNATED_INITIALIZER;

/** Opens the next connection generation without clearing an uncertain mutation
 * from an earlier generation. */
- (BOOL)connectionOpened;

/** Starts exactly one request and returns a nonzero token. Validation and the
 * reconnect guard run before any transport dispatch is permitted. */
- (BOOL)beginRequest:(NSDictionary *)request
                token:(uint64_t *)token
                error:(NSError **)error;

/** Validates an authenticated response against the captured request identity
 * and original absolute deadline. The in-flight slot remains reserved until
 * completeRequestForToken so export framing can finish under the same
 * authorization. */
- (BOOL)acceptResponseForToken:(uint64_t)token
                      response:(NSDictionary *)response
                         error:(NSError **)error;

/** Releases the in-flight request. A known export completion is valid only if
 * the original deadline remains live. Unknown completion permanently blocks
 * later mutations in this session. */
- (BOOL)completeRequestForToken:(uint64_t)token
                  outcomeKnown:(BOOL)known
                         error:(NSError **)error;

- (void)connectionLostWithOutcomeKnown:(BOOL)known;

/** Returns the remaining lifetime of the active operation's immutable
 * deadline. Transport waits must derive their timeout from this value on each
 * call instead of introducing a separate operation timeout. */
- (BOOL)remainingNanosecondsForToken:(uint64_t)token
                          remaining:(uint64_t *)remaining
                              error:(NSError **)error;

/** Returns the original absolute deadline for token. A successful reconnect
 * handshake never rebases this value or a later request's deadline. */
- (BOOL)deadlineNanosecondsForToken:(uint64_t)token
                           deadline:(uint64_t *)deadline
                              error:(NSError **)error;

/** Computes a poll timeout from the remaining nanoseconds. A positive result
 * rounds up to at most one millisecond; callers must recheck the absolute
 * deadline after poll returns. Expired and stale tokens fail. */
- (int)pollTimeoutMillisecondsForToken:(uint64_t)token error:(NSError **)error;

@property(nonatomic, readonly) BOOL enforcesOrdering;
@property(nonatomic, readonly) BOOL outcomeUnknown;
@property(nonatomic, readonly) BOOL requiresFreshAuthentication;
@property(nonatomic, readonly, copy, nullable) NSString *sessionID;
@property(nonatomic, readonly, copy, nullable) NSString *connectionID;
@property(nonatomic, readonly) BOOL hasActiveRequest;
@property(nonatomic, readonly) AQBrokerReconnectGuard *reconnectGuard;
@end

NS_ASSUME_NONNULL_END
