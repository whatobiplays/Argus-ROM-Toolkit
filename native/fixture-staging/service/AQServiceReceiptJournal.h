#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Service-owned durable export acknowledgments, scoped to authenticated XPC.
 * The caller must authenticate the broker peer before recording completion or
 * returning a query result. This journal does not create transferable proofs. */
@interface AQServiceReceiptJournal : NSObject
- (nullable instancetype)initWithDirectory:(NSString *)directory
                                      error:(NSError **)error;
/** Opens or creates the fixed `receipts` child relative to an already
 * authenticated protected staging-root descriptor. */
- (nullable instancetype)initWithProtectedRootFD:(int)rootFD
                                           error:(NSError **)error;
/** Durably reserves bounded aggregate receipt capacity for a session before
 * admission permits any mutation that can later require an export receipt.
 * Reservations are retained until their durable receipt is recorded, so
 * uncertain outcomes remain recoverable after restart. */
- (BOOL)reserveCapacityForSessionID:(NSString *)sessionID
                              error:(NSError **)error;
/** Reports whether this call created the reservation so a failed admission
 * can release only capacity owned by that attempt. */
- (BOOL)reserveCapacityForSessionID:(NSString *)sessionID
                            created:(BOOL *)created
                              error:(NSError **)error;
/** Releases a reservation only after admission has failed without creating a
 * store session. Durable receipts and existing reservations are preserved. If
 * the unlink cannot be durably recorded, the journal attempts to restore the
 * reservation before returning failure; the caller must keep that session
 * blocked. */
- (BOOL)releaseCapacityForSessionID:(NSString *)sessionID
                              error:(NSError **)error;
/** Persists a broker completion in a bounded 256 KiB record. The bound covers
 * the 64 KiB export metadata header and the member list repeated in both the
 * authenticated binding and completion. Both frame_sha256 and receipt_sha256
 * must be exactly 64 lowercase hexadecimal characters. */
- (BOOL)recordBrokerCompletion:(NSDictionary *)completion
                       binding:(NSDictionary *)binding
                         error:(NSError **)error;
- (nullable NSDictionary *)receiptForBinding:(NSDictionary *)binding
                                        error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
