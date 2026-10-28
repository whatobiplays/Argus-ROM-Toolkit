#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Fixed, non-sensitive failures shared by JSON and snapshot contract validation. */
FOUNDATION_EXPORT NSString * const AQContractErrorDomain;
typedef NS_ENUM(NSInteger, AQContractErrorCode) {
    AQInputInvalid = 1, AQLimitExceeded, AQSchemaUnsupported, AQPinMismatch,
    AQMissingReference, AQReferenceCycle, AQEvidenceConflict, AQUnusedRecord,
};
FOUNDATION_EXPORT NSError *AQContractError(AQContractErrorCode code);

/** Parse one immutable UTF-8 JSON object, at most 64 KiB and depth 32.
 * Duplicate keys, invalid scalar encodings, non-NFC values, non-ASCII keys,
 * floats, negative zero, and integers outside signed 64-bit are rejected.
 * Parsing never rounds integers or conflates booleans with integers.
 * The raw input and canonical output byte buffers are each capped at 64 KiB.
 * During canonicality validation both can coexist, making the byte-buffer
 * ceiling 128 KiB; decoded Foundation object storage is proportional to the
 * returned document and is not part of that byte-buffer ceiling.
 */
FOUNDATION_EXPORT id _Nullable AQParseJSON(NSData *data, NSError **error);

/** Parse one JSON object with an explicitly selected byte bound no greater
 * than 12 MiB. The default parser remains capped at 64 KiB. Protocol callers
 * should pass the maximum content bytes after accounting for framing. */
FOUNDATION_EXPORT id _Nullable AQParseJSONWithMaximumBytes(
    NSData *data, NSUInteger maximumBytes, NSError **error);

/** Encode bounded JSON values exactly as Python ensure_ascii=False canonical JSON.
 * Dictionary keys are ASCII and sorted; controls use Python's JSON escapes.
 * Accepts Foundation dictionaries, arrays, strings, signed-range integer
 * NSNumbers, CFBoolean-backed NSNumbers, and NSNull. Rejects floating NSNumbers.
 */
FOUNDATION_EXPORT NSData * _Nullable AQCanonicalJSON(id value, NSError **error);

/** Encode JSON with an explicit byte bound no greater than 12 MiB. */
FOUNDATION_EXPORT NSData * _Nullable AQCanonicalJSONWithMaximumBytes(
    id value, NSUInteger maximumBytes, NSError **error);

/** SHA-256 lowercase hex of canonical JSON, prefixed by ASCII domain + NUL
 * when domain is nonempty. An empty domain hashes only the canonical bytes.
 * Hashing proves neither schema validity nor authority.
 */
FOUNDATION_EXPORT NSString * _Nullable AQDigest(NSString *domain, id value, NSError **error);
NS_ASSUME_NONNULL_END
