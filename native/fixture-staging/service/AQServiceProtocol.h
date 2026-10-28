#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

NS_ASSUME_NONNULL_BEGIN

/** Fixed service failures. Localized descriptions are stable machine codes and
 * never include peer text, paths, JSON fragments, signatures, or key material. */
FOUNDATION_EXPORT NSString *const AQServiceErrorDomain;

#ifdef AQ_SERVICE_TESTING
/** Controls synthetic state-changing requests in the service test binary only. */
FOUNDATION_EXPORT void AQServiceSetSyntheticMutationsAllowedForTesting(BOOL allowed);
#endif

/** Returns the process-wide serial target queue for accepted service peers. */
FOUNDATION_EXPORT dispatch_queue_t AQServiceSerialPeerQueue(void);

/** Largest canonical request envelope accepted from one authenticated peer. */
FOUNDATION_EXPORT const NSUInteger AQServiceMaximumRequestBytes;
/** Maximum bounded payload for authenticated, read-only receipt control and
 * completion records. Ordinary service requests remain limited to 64 KiB. */
FOUNDATION_EXPORT const NSUInteger AQServiceMaximumReceiptBytes;

/** Limits for admission documents and source descriptors. Payload member bytes
 * are streamed by AQStore and are not subject to these metadata limits. */
FOUNDATION_EXPORT const NSUInteger AQServiceMaximumDocumentBytes;
FOUNDATION_EXPORT const NSUInteger AQServiceMaximumDocuments;
FOUNDATION_EXPORT const NSUInteger AQServiceMaximumSourceDescriptors;

/** Maximum owner-authorized operation duration for a schema-1 service
 * deadline. Hello admission rejects a deadline more than this duration ahead
 * of the service's monotonic nanosecond clock. */
FOUNDATION_EXPORT const uint64_t AQServiceMaximumOperationNanoseconds;

/** Lazily supplies protected payloads after request authentication. The
 * executable passes each block only when its corresponding XPC attachment is
 * present: documents for admit and source descriptors for stage. The service
 * rejects a block for an incompatible operation without invoking either
 * loader, so malformed or unauthenticated requests cannot trigger document
 * copies or source-descriptor duplication. */
typedef NSDictionary * _Nullable (^AQServiceDocumentsLoader)(void);
typedef NSDictionary<NSString *, NSNumber *> * _Nullable (^AQServiceSourceFDsLoader)(void);

/** The service executable attaches exact reviewed authorization bytes in the
 * decoded request's `authorization` member. The owner-supplied
 * `authorization_sha256` must equal SHA-256 over those bytes, and the bytes
 * must already be canonical JSON. The raw attachment never enters canonical
 * request JSON or protected store payloads. */

typedef NS_ENUM(NSInteger, AQServiceErrorCode) {
    AQServiceInvalidRequest = 1,
    AQServiceLimitExceeded,
    AQServiceUnsupportedVersion,
    AQServiceUnauthenticatedConnection,
    AQServiceConsentRequired,
    AQServiceConsentDenied,
    AQServiceConsentExpired,
    AQServiceBindingMismatch,
    AQServiceReplayRejected,
    AQServiceOperationDenied,
    AQServiceCoverageDenied,
    AQServiceReferenceDenied,
    AQServiceStoreDenied,
    AQServiceReceiptCapacityDenied,
    AQServiceUnsupportedInstallation,
    AQServiceUnsupportedExclusivity,
    AQServiceInternalFailure,
};

/** Returns a fixed sanitized error in AQServiceErrorDomain. */
FOUNDATION_EXPORT NSError *AQServiceError(AQServiceErrorCode code);

/** The subset of AQStore consumed by the protocol state machine. AQStore
 * conforms through an adapter in the service executable; tests may provide a
 * deterministic in-memory implementation without gaining production
 * authority. All methods retain AQStore's at-most-once semantics. */
@protocol AQServiceStore <NSObject>
- (BOOL)reserveReceiptCapacityForSessionID:(NSString *)sessionID
                                     error:(NSError **)error;
- (BOOL)reserveReceiptCapacityForSessionID:(NSString *)sessionID
                                    created:(BOOL *)created
                                      error:(NSError **)error;
- (BOOL)releaseReceiptCapacityForSessionID:(NSString *)sessionID
                                      error:(NSError **)error;
- (nullable NSDictionary *)admitManifest:(NSDictionary *)manifest
                              authority:(NSDictionary *)authority
                                  error:(NSError **)error;
- (nullable NSDictionary *)stageRequest:(NSDictionary *)request
                              sourceFDs:(NSDictionary<NSString *, NSNumber *> *)sourceFDs
                                  error:(NSError **)error;
- (nullable NSDictionary *)inspectSession:(NSString *)sessionID;
- (nullable NSDictionary *)eligibilityForRequest:(NSDictionary *)request
                                            error:(NSError **)error;
- (int)exportPipeForRequest:(NSDictionary *)request error:(NSError **)error;
- (nullable NSDictionary *)cleanupRequest:(NSDictionary *)request
                                    error:(NSError **)error;
- (NSDictionary *)classifyRecovery;
- (void)revokeSession:(NSString *)sessionID reason:(NSString *)reason;
@end

/** Clock domains used by schema-1 service authorization and the internal store.
 * monotonicNanoseconds returns integer nanoseconds from a clock that excludes
 * suspended time; production converts mach_absolute_time() with the platform
 * timebase. continuousTicks returns raw mach_continuous_time() ticks for
 * validating and enforcing AQStore's persisted deadline. Hello checks that the
 * store deadline does not extend the signed nanosecond deadline. A sentinel or
 * unrepresentable value fails closed. */
@protocol AQServiceClock <NSObject>
- (uint64_t)monotonicNanoseconds;
- (uint64_t)continuousTicks;
@end

/** Verifies the owner's signature over the exact consent bytes returned by the
 * service. Production binds this block to AQSecurity and the installed policy.
 * The block is not accepted over IPC. */
typedef BOOL (^AQServiceOwnerVerifier)(NSData *canonicalConsent,
                                      NSData *signature,
                                      NSError **error);

/** Returns a fresh bounded ASCII token. Production uses platform randomness. */
typedef NSString * _Nullable (^AQServiceIdentifierGenerator)(void);

/** Connection-scoped protocol state. The class is not an IPC surface. The
 * service executable calls it only after AQValidatePeerMessage succeeds for a
 * broker connection. It creates registry entries on the listener/main queue
 * and routes peer messages and invalidation to AQServiceSerialPeerQueue(). A
 * private lock protects the connection registry across those queues; mutable
 * per-session freshness state remains on the serial peer queue.
 *
 * Messages are Foundation dictionaries produced by a strict XPC converter.
 * Strings, booleans, unsigned integers, arrays, and data are bounded before
 * this boundary. Hello carries the next owner-journal sequence and a nonce
 * derived by SHA-256 from installation, service boot epoch, broker revision,
 * owner key, sequence, and reviewed authorization bytes. The service keeps a
 * single sequence high-water mark per installed owner for this process boot;
 * a repeated or skipped sequence is rejected. Because the nonce is a
 * deterministic function of the signed boot epoch and sequence, neither a
 * nonce set nor a TTL is needed to detect reuse across sequences. The owner
 * consent envelope later binds and signs that nonce. A session is bound to the service-generated
 * connection_id, owner-consented operation set, grant, service boot identity,
 * installation, and immutable schema-1 nanosecond deadline.
 * After hello, every request carries a base64 canonical freshness envelope in
 * freshness_envelope and an owner signature in freshness_signature. The signed
 * record binds the installed installation, service boot, broker revision, and
 * owner key; connection; session; service boot identity as the process epoch;
 * deterministic request ID; strictly increasing sequence; operation; canonical
 * request digest; authorization digest; approval-consent digest; and original deadline_ns. The request
 * ID is SHA-256(session_id, sequence, operation, request_sha256), giving
 * constant replay state while retaining a stable AQStore idempotency key.
 * These bindings and the signature are checked before operation-specific
 * fields, documents, source descriptors, or store callbacks are read. A stage
 * request signs source_identities containing each path and live descriptor's
 * fstat device, inode, mode, size, and link count. The service checks the
 * claimed identity against its duplicated descriptor before dispatch, so
 * attachment substitution changes the signed request identity. That descriptor
 * remains open through the AQStore callback. Replay
 * state is the session's sequence cursor; there is no request-ID set, quota,
 * TTL, wall-clock window, or eviction policy.
 *
 * A reconnect never restores mutation authority. The prior connection is
 * revoked so its store session is blocked_retained. The authenticated broker
 * may issue only inspect and recovery requests on the replacement connection.
 */
@interface AQServiceSessionCore : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Creates a core only after installation policy, executable identity,
 * protected staging root, store journal, and authenticated-peer APIs have all
 * passed. No pathname, policy, key, or verifier is accepted over IPC.
 * installationIdentity and brokerRevision are immutable installed values. */
- (nullable instancetype)initWithStore:(id<AQServiceStore>)store
                 installationIdentity:(NSString *)installationIdentity
                    serviceBootIdentity:(NSString *)serviceBootIdentity
                        brokerRevision:(NSString *)brokerRevision
                       ownerKeyIdentifier:(NSString *)ownerKeyIdentifier
                              clock:(id<AQServiceClock>)clock
                     ownerVerifier:(AQServiceOwnerVerifier)ownerVerifier
                 identifierGenerator:(AQServiceIdentifierGenerator)identifierGenerator
                                 error:(NSError **)error;

/** Allocates the service-generated connection identifier used by the first
 * hello response. Call after the OS peer requirement and per-message identity
 * have established that this is the approved broker. */
- (nullable NSString *)openConnection:(NSError **)error;

/** Handles one decoded request. documents may be non-nil only for admit and
 * sourceFDs may be non-nil only for stage. exportFileDescriptor is initialized
 * to -1 before request validation and receives the AQStore-owned read end only
 * when export succeeds; the caller owns and closes a nonnegative descriptor.
 * Owner freshness is verified and request replay state is advanced once before
 * dispatch. */
- (nullable NSDictionary *)handleRequest:(NSDictionary *)request
                              documents:(NSDictionary * _Nullable)documents
                              sourceFDs:(NSDictionary<NSString *, NSNumber *> * _Nullable)sourceFDs
                          connectionID:(NSString *)connectionID
                   exportFileDescriptor:(int *)exportFileDescriptor
                                  error:(NSError **)error;

/** Executable entry point for protected payloads. A loader must be non-nil
 * only when the corresponding XPC attachment is present and the operation
 * accepts it: documents for admit and source file descriptors for stage.
 * Incompatible attachment loaders are rejected without invoking either block.
 * Signed freshness is verified and replay state is advanced once before an
 * accepted loader runs. Dispatch receives that verified result and rechecks
 * only the current connection phase and deadline before mutation.
 * exportFileDescriptor has the same initialization and ownership contract as
 * handleRequest:documents:sourceFDs:connectionID:exportFileDescriptor:error:. */
- (nullable NSDictionary *)handleRequest:(NSDictionary *)request
                       documentsLoader:(AQServiceDocumentsLoader _Nullable)documentsLoader
                         sourceFDsLoader:(AQServiceSourceFDsLoader _Nullable)sourceFDsLoader
                            connectionID:(NSString *)connectionID
                    exportFileDescriptor:(int *)exportFileDescriptor
                                   error:(NSError **)error;

/** Revokes the connection's admitted session, clears pending consent, and
 * permanently rejects further messages on that connection. Safe to call more
 * than once. */
- (void)invalidateConnection:(NSString *)connectionID reason:(NSString *)reason;

/** Read-only readiness facts for an authenticated connection after successful
 * construction. The response identifies the installed installation, service
 * boot, broker revision, and owner key. It grants no operation authority and
 * contains no secrets. */
- (NSDictionary *)readinessFacts;

@end

NS_ASSUME_NONNULL_END
