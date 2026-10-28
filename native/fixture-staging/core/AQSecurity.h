#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const AQSecurityErrorDomain;
FOUNDATION_EXPORT NSString *const AQInstallationPath;
FOUNDATION_EXPORT NSString *const AQProductionStagingRoot;
FOUNDATION_EXPORT NSString *const AQBrokerExecutablePath;
FOUNDATION_EXPORT NSString *const AQServiceExecutablePath;
FOUNDATION_EXPORT NSString *const AQMachServiceName;

typedef NS_ENUM(NSInteger, AQSecurityError) {
    AQSecurityInvalidInput = 1,
    AQSecurityInvalidPolicy,
    AQSecurityUntrustedInstallation,
    AQSecurityUntrustedPeer,
    AQSecurityNotEnrolled,
    AQSecurityUnsupportedPlatform,
    AQSecurityOwnerConsentDenied,
    AQSecurityKeyRejected,
    AQSecurityInvalidSignature,
};

typedef NS_ENUM(NSInteger, AQPeerRole) { AQPeerBroker = 1, AQPeerService = 2 };

/** Immutable installation policy. Parsing alone never grants installation trust.
 * Obtain production authority only with AQLoadInstallationPolicy. All peer and
 * owner-key operations reject policies obtained from the standalone parser.
 */
@interface AQInstallationPolicy : NSObject
@property(nonatomic, readonly, copy) NSString *teamIdentifier;
@property(nonatomic, readonly, copy) NSString *brokerCDHash;
@property(nonatomic, readonly, copy) NSString *serviceCDHash;
@property(nonatomic, readonly) uid_t ownerUID;
@property(nonatomic, readonly) uid_t serviceUID;
@property(nonatomic, readonly, copy) NSString *keyAccessGroup;
@property(nonatomic, readonly, copy) NSString *keyTag;
@property(nonatomic, readonly, copy, nullable) NSData *ownerPublicKey;
@property(nonatomic, readonly, getter=isInstalledPolicy) BOOL installedPolicy;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/** Strict, bounded, flat installation.json decoder; no filesystem or Keychain IO.
 * Rejects duplicate/unknown fields. See security-contract.md for the nine fields.
 * This function does not parse, normalize or canonicalize operation envelopes.
 */
FOUNDATION_EXPORT AQInstallationPolicy *_Nullable AQParseInstallationPolicy(
    NSData *data, NSError **error);

/** Reads only AQInstallationPath via nofollow directory descriptors. Every
 * ancestor is root:0755 without ACL entries; the file is root:0644, one link,
 * at most 16 KiB. No caller-selected path and no creation or repair are allowed.
 */
FOUNDATION_EXPORT AQInstallationPolicy *_Nullable AQLoadInstallationPolicy(NSError **error);

/** Requires an installed policy. Resolves the pinned service UID through the
 * system account database and requires the dedicated non-login markers: an
 * unusable password marker, a non-login shell and no supplementary groups.
 * Missing or alternate account records fail closed; this check never changes
 * the account.
 */
FOUNDATION_EXPORT BOOL AQValidateNonLoginServiceIdentity(
    AQInstallationPolicy *policy, NSError **error);

/** Verifies absolute, lexical, nofollow root-owned ancestry and a single inode.
 * Directories must be 0755; regular files may require 0644 or 0755. ACL entries,
 * symlinks, hard-linked files, special files and group/other writes are refused.
 * Authentication additionally compares the live executable to its exact path.
 */
FOUNDATION_EXPORT BOOL AQValidateProtectedPath(NSString *path, BOOL directory,
                                               mode_t mode, NSError **error);

/** Opens the fixed production staging anchor through descriptor-relative,
 * nofollow traversal. Every ancestor must be root-owned 0755 and the leaf must
 * be the policy service UID's 0700 directory; all must have empty ACLs. The
 * caller owns and must close the returned descriptor, then perform all staging
 * work relative to it. No caller-selected root is accepted.
 */
FOUNDATION_EXPORT int AQOpenProductionStagingRoot(
    AQInstallationPolicy *policy, NSError **error) __attribute__((warn_unused_result));

/** Reports whether the running macOS release and loaded Security/XPC
 * frameworks provide both public facilities used below. The function resolves
 * each symbol at runtime and fails closed when either is absent. Availability
 * is a prerequisite only; it never grants peer or owner authority.
 */
FOUNDATION_EXPORT BOOL AQAuthenticatedPeerAPIsAvailable(NSError **error);

/** Builds the exact team + identifier + approved CodeDirectory requirement.
 * Pure formatting/compilation validation; does not establish peer authority.
 */
FOUNDATION_EXPORT NSString *_Nullable AQPeerSigningRequirement(
    AQInstallationPolicy *policy, AQPeerRole role, NSError **error);

/** Call exactly once on each NEW INACTIVE connection before activate/resume,
 * including the service listener, its accepted connections and broker outgoing
 * connections. On failure cancel the connection and send no data. This sets the
 * OS receive-side requirement; it does not authorize outgoing private data.
 */
FOUNDATION_EXPORT BOOL AQConfigurePeerRequirement(xpc_connection_t connection,
    AQInstallationPolicy *policy, AQPeerRole expectedPeer, NSError **error);

/** Additional per-message validation using SecCodeCreateWithXPCMessage and
 * SecCodeCheckValidity. The executable path comes exclusively from that live
 * code object. Checks exact installed path, filesystem protection, CDHash,
 * hardened runtime, entitlements, dynamic debug state and expected peer UID.
 * A locally constructed dictionary has no peer and is rejected. On an older
 * runtime or any unavailable identity primitive, returns NO and an
 * AQSecurityUnsupportedPlatform error. Authenticate a non-sensitive handshake
 * before sending private data in either direction.
 */
FOUNDATION_EXPORT BOOL AQValidatePeerMessage(xpc_object_t message,
    AQInstallationPolicy *policy, AQPeerRole expectedPeer, NSError **error);

/** Verifies ECDSA P-256/SHA-256 over the EXACT canonical envelope bytes using
 * only the public key pinned by the installed policy. A valid signature is NOT
 * session authorization: the parent FSM must bind session, nonce, challenge,
 * input pins, operation and replay state before any authority-bearing action.
 */
FOUNDATION_EXPORT BOOL AQVerifyOwnerSignature(AQInstallationPolicy *policy,
    NSData *canonicalEnvelope, NSData *signature, NSError **error);

typedef void (^AQSecurityCompletion)(NSData *_Nullable result, NSError *_Nullable error);

/** Broker-only consent: copies 1..65536 envelope bytes at entry, shows their
 * exact escaped/hex representation in a cancel-default AppKit dialog, and signs
 * only after explicit approval with a fresh zero-reuse LAContext. The existing
 * Secure Enclave key, actual access group and ACL must match policy. Never
 * enrolls, substitutes a software key, or accepts a caller's signing key.
 * Completion runs asynchronously on the main queue; contexts are invalidated.
 */
FOUNDATION_EXPORT void AQRequestOwnerSignature(AQInstallationPolicy *policy,
    NSData *canonicalEnvelope, AQSecurityCompletion completion);

/** Separate, explicitly invoked enrollment UI. Requires an installed policy
 * with a null owner_public_key, the approved broker/owner identity, an explicit
 * cancel-default enrollment confirmation and fresh LocalAuthentication approval.
 * Creates a permanent P-256 Secure Enclave key in the Data Protection keychain
 * with userPresence + privateKeyUsage. Returns its public key ONLY after actual
 * readback/ACL/access-group and signing checks. Never overwrites a key, writes
 * installation.json, or silently repairs partial enrollment. The installer must
 * separately pin the returned public key. Do not invoke during unit tests.
 */
FOUNDATION_EXPORT void AQEnrollOwnerKey(AQInstallationPolicy *policy,
                                       AQSecurityCompletion completion);

NS_ASSUME_NONNULL_END
