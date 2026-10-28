#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const AQStoreErrorDomain;
FOUNDATION_EXPORT const NSUInteger AQStoreIOChunkSize; // 1 MiB maximum IO request.
/** Shared canonical export metadata-header bound; member payload bytes are uncapped. */
FOUNDATION_EXPORT const NSUInteger AQStoreMaximumExportMetadataHeaderBytes;
FOUNDATION_EXPORT NSString *const AQStoreProductionRoot;

/** Stable failures returned by the store boundary. */
typedef NS_ENUM(NSInteger, AQStoreErrorCode) {
    AQStoreInvalidInput = 1,
    AQStoreUnauthorizedRoot,
    AQStoreInvalidState,
    AQStoreSourceDenied,
    AQStoreCapacityDenied,
    AQStoreIntegrityFailure,
    AQStoreDeadlineExpired,
    AQStoreRevoked,
    AQStoreJournalCorrupt,
    AQStoreBusy,
    AQStoreIOFailure,
    AQStoreMetadataHeaderTooLarge,
};

/** Checked arithmetic used by real streaming/capacity checks; no payload-size cap. */
FOUNDATION_EXPORT BOOL AQStoreAddBytes(uint64_t left, uint64_t right, uint64_t *result);
FOUNDATION_EXPORT BOOL AQStoreCapacityAllows(uint64_t available, uint64_t remaining,
                                            uint64_t hostReserve, uint64_t destinationReserve);

/** Native-internal clock. Production uses raw mach_continuous_time() ticks.
 * The parent authenticates boot identity, timebase and wall-clock bounds.
 */
@protocol AQStoreClock <NSObject>
- (uint64_t)continuousTicks;
@end

#if defined(AQ_STORE_TESTING)
/** Fault seams exist only in the test target, never IPC or environment input.
 * Returning NO simulates a failed boundary, preserving whatever preceded it.
 * Names and ordering are specified in store-contract.md.
 */
@interface AQStoreTestHooks : NSObject
@property(nonatomic, copy, nullable) BOOL (^boundary)(NSString *name);
@property(nonatomic, copy, nullable) NSNumber *_Nullable (^availableBytes)(void);
/** Observes a journal record only after its durable append has completed. */
@property(nonatomic, copy, nullable) void (^recordWritten)(NSString *event, NSDictionary *session);
@end

/** Exercises canonical export-header validation without creating a store session. */
FOUNDATION_EXPORT BOOL AQStoreExportHeaderWithinLimitForTesting(
    NSDictionary *manifest, NSString *sessionID, NSString *manifestSHA256,
    uint64_t generation, NSError **error);
#endif

/** Service-internal immutable snapshot state machine. This is NOT an IPC API.
 * Production obtains rootFD only from its fixed protected namespace after
 * AQSecurity admission. The initializer requires an euid-owned 0700 directory
 * with no extended ACL and duplicates the borrowed descriptor; production also
 * relies on AQSecurity's protected-ancestor validation. This private root is
 * required because unlinkat cannot atomically compare an entry's inode identity.
 * installationIdentity is the parent's immutable installation digest.
 * No pathname, authority flag, clock or test-hook is accepted over IPC.
 * Parent verifies owner signature, XPC identity, canonical request digest,
 * manifest/oracle contract, plan coverage, installation and timing schema 2.
 * The core independently binds and consumes the exact authenticated fields.
 */
@interface AQStore : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (nullable instancetype)initWithRootFD:(int)rootFD
                  installationIdentity:(NSString *)installationIdentity
                                 error:(NSError **)error;

#if defined(AQ_STORE_TESTING)
- (nullable instancetype)initForTestingWithRootFD:(int)rootFD
                           installationIdentity:(NSString *)installationIdentity
                                          clock:(id<AQStoreClock>)clock
                                          hooks:(nullable AQStoreTestHooks *)hooks
                                          error:(NSError **)error;
#endif

/** Immutable deep copies. Authority keys: session_id, grant_id, connection_id,
 * epoch, manifest_sha256, plan_sha256, rules_sha256, deadline_ticks,
 * host_reserve_bytes, destination_reserve_bytes, operations.
 * IDs are nonempty printable ASCII, digests lowercase SHA-256; integer values
 * are nonnegative signed-64-bit JSON integers (deadline strictly positive).
 * operations is a distinct subset of stage, eligibility, export, cleanup.
 * Manifest is the complete normalized schema-2 document (legacy fixtures,
 * files and companions retained), already independently validated by parent.
 * Admission consumes a session/grant permanently; no replacement or renewal.
 */
- (nullable NSDictionary *)admitManifest:(NSDictionary *)manifest
                              authority:(NSDictionary *)authority error:(NSError **)error;

/** Every operation request has exactly: session_id, grant_id, connection_id,
 * epoch, operation, sequence, request_sha256, expected_generation.
 * Sequence starts at 1 and advances once for every accepted dispatch, including
 * a later failed operation. expected_generation comes from inspectSession:.
 * Parent computes/verifies request_sha256 over its complete canonical signed
 * envelope INCLUDING source identities. Core rejects reused digests and checks
 * all immutable bindings. It never claims to authenticate a supplied digest.
 */
- (nullable NSDictionary *)stageRequest:(NSDictionary *)request
                             sourceFDs:(NSDictionary<NSString *, NSNumber *> *)sourceFDs
                                 error:(NSError **)error;

/** Source FD keys are fixture_id + '/' + file.path in manifest order. Each FD
 * must be O_RDONLY, regular, single-linked. Descriptors are duplicated before
 * dispatch and never closed on behalf of the caller. All payload IO uses
 * descriptor-relative nofollow traversal. No source is reopened after seal.
 */
- (nullable NSDictionary *)inspectSession:(NSString *)sessionID;
- (nullable NSDictionary *)eligibilityForRequest:(NSDictionary *)request error:(NSError **)error;

/** Returns only the O_RDONLY nonblocking anonymous pipe end (caller closes it).
 * Asynchronous writer stays inside the service. EOF without terminal frame is
 * failure. No pathname or write FD is returned. Trusted broker MUST validate
 * the exact framing, all bytes and terminal transcript described below, and
 * separately record receipt; successful creation is not completed delivery.
 * Frame: 8 ASCII bytes AQSNAP1\n; u64 big-endian JSON-header byte length;
 * compact sorted-key JSON header; raw members in header order; 8 ASCII bytes
 * AQEND1\r\n; 32-byte SHA-256 of the version prefix, header length,
 * canonical header and raw members. The terminal marker and digest are not
 * included in that digest.
 * Header keys: schema_version=1, session_id, manifest_sha256, generation,
 * members=[{path,size,sha256}]. Path is fixture_id + '/' + file.path. The
 * canonical metadata header is bounded by AQStoreMaximumExportMetadataHeaderBytes
 * and is preflighted before a request consumes a sequence. This metadata bound
 * does not cap streamed member payload bytes.
 * The broker compares parsed header values to its independently approved
 * manifest, not to a self-authenticating hash from this stream.
 */
- (int)exportPipeForRequest:(NSDictionary *)request error:(NSError **)error;

/** Explicit cleanup only. Quiesces writers, verifies the complete tree, and
 * records the observed inode identity of each entry. Immediately before each
 * unlink/rmdir, descriptor-relative no-follow fstatat revalidation checks the
 * current entry; files are reopened and rehashed. A changed or replaced entry
 * remains blocked_retained rather than being deleted. Each attempt is persisted
 * before its syscall, then directory durability precedes verified completion.
 * Uncertain attempts and foreign entries are retained, never retried under a
 * later sequence. The journal/replay tombstones live outside payload trees.
 */
- (nullable NSDictionary *)cleanupRequest:(NSDictionary *)request error:(NSError **)error;

/** Read-only classification after restart: no mutation replay or re-admission.
 * Recovered sessions remain blocked_retained, with last durable effect state.
 * `fresh_admission_available` is true until one new, unused session is durably
 * admitted during this store startup. The store remains blocked_retained after
 * that admission; reopening it marks every prior session retained again and
 * preserves all recovery obligations. Existing session identities cannot be
 * replayed or re-admitted.
 * Malformed/truncated journals make the entire root blocked_retained rather
 * than exposing an older eligible generation. Never repairs/deletes records.
 */
- (NSDictionary *)classifyRecovery;

/** Does not wait for an ongoing transfer. The cancellation flag is checked
 * before/after every bounded IO and at dispatch completion. Inspection exposes
 * it immediately. Buffered pipe bytes cannot be retracted by cancellation.
 */
- (void)revokeSession:(NSString *)sessionID reason:(NSString *)reason;
@end

NS_ASSUME_NONNULL_END
