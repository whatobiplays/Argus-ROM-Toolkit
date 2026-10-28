#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Performs one fixed filesystem mutation used to exercise the isolation proof.

 The caller supplies an already-open directory descriptor. The operation name
 selects one fixed synthetic operation: `renameat` replaces
 `rename-destination` with `rename-source`; `renameatx_np` swaps `swap-left`
 and `swap-right`; `linkat` links `link-source` to `link-destination`;
 `symlinkat` creates `symlink-link`; `unlinkat` removes `unlink-entry`; and
 `rmdir` removes the empty `remove-directory`. Callers cannot supply paths or
 choose another destination. A result reports the syscall's actual return
 value, errno, and effective UID. This function does not authorize a production
 run or establish kernel isolation.
 */
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
AQProofActorPerformOperation(int directoryFD, NSString * _Nullable operation);

/**
 Runs the fixed syscall suite inside a newly created, private temporary
 directory. It refuses to run as root and labels all results synthetic. The
 suite does not access the installed staging namespace or prove service-UID
 isolation.
 */
FOUNDATION_EXPORT NSDictionary<NSString *, id> *AQProofActorRunSyntheticSuite(void);

NS_ASSUME_NONNULL_END
