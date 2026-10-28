#import "AQJSON.h"

NS_ASSUME_NONNULL_BEGIN
/** Validate manifest schema 2 and oracle/evidence schema 1 declarations.
 * Inputs are already securely acquired document bytes; this API performs no
 * filesystem/network operations. The service must authenticate the three pins
 * and check authorized plan coverage separately. Legacy schemas are rejected.
 *
 * Returns a deeply immutable dictionary with manifest_sha256, source_authority,
 * and fixtures (ordered assessment dictionaries). Each assessment has fixture_id,
 * oracle_ref, oracle_revision, oracle_sha256, corpus_origin, byte_integrity,
 * structural_expectation, independent_support, and owner_approval. Byte integrity
 * and owner approval are always not_checked; structural expectation is validated.
 * Independent support is synthetic_only for synthetic corpora or
 * pinned_unverified for genuine declarations. This API cannot mint
 * verified_independent_reference because no separately authenticated native
 * reference provider is installed. These are separate tiers, not proof labels.
 * No partial result survives failure; NSError exposes only fixed codes.
 */
FOUNDATION_EXPORT NSDictionary * _Nullable AQValidateSnapshotContract(
    NSData *manifest, NSArray<NSData *> *oracles, NSArray<NSData *> *evidence,
    NSString *authorizedManifestSHA256, NSString *authorizedPlanSHA256,
    NSString *authorizedRulesSHA256,
    NSError **error);
NS_ASSUME_NONNULL_END
